# Kubernetes Integration with HashiCorp Vault

## 1. Overview

This document describes the Kubernetes configuration required to integrate the Kubernetes cluster with HashiCorp Vault using Kubernetes Authentication.

The integration allows applications running inside Kubernetes Pods to authenticate to Vault using their Kubernetes ServiceAccount identities instead of storing Vault tokens directly inside application configurations.

### Authentication flow

1. The application runs inside a Kubernetes Pod.
2. Kubernetes automatically provides the Pod with a ServiceAccount token.
3. The application uses this token to authenticate to Vault.
4. Vault uses a dedicated reviewer ServiceAccount token to validate the application's identity through the Kubernetes TokenReview API.
5. Kubernetes validates the token and returns the ServiceAccount identity to Vault.
6. Vault checks its configured roles and policies.
7. Vault issues a Vault token with the permissions assigned to the application.

## 2. Kubernetes API Server Address

Vault requires the Kubernetes API Server address to communicate with the Kubernetes cluster and validate application identities.

Retrieve the API Server address:

```bash
kubectl config view --minify \
  -o jsonpath='{.clusters[0].cluster.server}'
```

Check the active Kubernetes context:

```bash
kubectl config current-context
```

The API Server address must be provided to the Vault administrator.

## 3. Create the Vault Reviewer ServiceAccount

A dedicated ServiceAccount named `vault-reviewer` is created in the `kube-system` namespace.

This ServiceAccount is used by Vault to authenticate its requests to the Kubernetes TokenReview API.

Create the ServiceAccount:

```bash
kubectl create serviceaccount vault-reviewer \
  -n kube-system
```

Verify:

```bash
kubectl get serviceaccount vault-reviewer \
  -n kube-system
```

## 4. Assign TokenReview Permissions

Kubernetes provides a built-in ClusterRole named `system:auth-delegator`.

This ClusterRole grants permission to delegate authentication checks, including creating TokenReview requests.

A ClusterRoleBinding connects the `vault-reviewer` ServiceAccount to this ClusterRole.

Create the binding:

```bash
kubectl create clusterrolebinding vault-reviewer \
  --clusterrole=system:auth-delegator \
  --serviceaccount=kube-system:vault-reviewer
```

Verify the binding:

```bash
kubectl describe clusterrolebinding vault-reviewer
```

Inspect the built-in ClusterRole:

```bash
kubectl describe clusterrole system:auth-delegator
```

**Note:** A ClusterRoleBinding grants the assigned permissions across the Kubernetes cluster. TokenReview is a cluster-level API operation, so a ClusterRoleBinding is required.

## 5. Create the ServiceAccount JWT Token

Vault requires a reviewer JWT token to communicate with the Kubernetes API Server and validate application tokens.

A Kubernetes Secret of type `kubernetes.io/service-account-token` is created to generate a long-lived token associated with the `vault-reviewer` ServiceAccount.

Create `vault-reviewer-token.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: vault-reviewer-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: vault-reviewer
type: kubernetes.io/service-account-token
```

Apply the manifest:

```bash
kubectl apply -f vault-reviewer-token.yaml
```

Wait for Kubernetes to populate the Secret:

```bash
kubectl get secret vault-reviewer-token \
  -n kube-system -w
```

Verify the Secret:

```bash
kubectl describe secret vault-reviewer-token \
  -n kube-system
```

The Secret contains three data entries:

| Data | Description |
|---|---|
| `token` | JWT authentication token for the reviewer ServiceAccount |
| `ca.crt` | Kubernetes API Server CA certificate |
| `namespace` | ServiceAccount namespace |

### Extract the JWT token

```bash
kubectl get secret vault-reviewer-token \
  -n kube-system \
  -o jsonpath='{.data.token}' | base64 -d
```

The output is the JWT token that must be securely provided to the Vault administrator.

**Security:** This token is a long-lived credential and must be treated as a secret. Do not commit it to Git repositories or include it in ordinary documentation.

## 6. Application ServiceAccounts

The reviewer ServiceAccount is shared by Vault for the Kubernetes cluster.

Each application, however, should have its own ServiceAccount in its respective namespace.

For example:

| Environment | Namespace | ServiceAccount |
|---|---|---|
| Develop | `crouseserviceloan-develop` | `loan-develop` |
| Stage | `crouseserviceloan-stage` | `loan-stage` |

Create the application ServiceAccounts:

```bash
kubectl create serviceaccount loan-develop \
  -n crouseserviceloan-develop

kubectl create serviceaccount loan-stage \
  -n crouseserviceloan-stage
```

Configure the appropriate ServiceAccount in each Deployment:

Develop:

```yaml
spec:
  template:
    spec:
      serviceAccountName: loan-develop
```

Stage:

```yaml
spec:
  template:
    spec:
      serviceAccountName: loan-stage
```

Kubernetes provides the Pod with its own ServiceAccount identity token, which the application can use to authenticate to Vault.

New applications can follow the same approach by creating their own ServiceAccount in their respective namespaces.

## 7. Information Required by the Vault Administrator

The following information must be provided to the Vault administrator to configure Kubernetes Authentication:

| Item | Description |
|---|---|
| Kubernetes API Server Address | Address used by Vault to communicate with Kubernetes |
| Reviewer ServiceAccount | `kube-system:vault-reviewer` |
| Reviewer JWT Token | Long-lived JWT generated from `vault-reviewer-token` |
| Kubernetes CA Certificate | CA certificate used to verify the Kubernetes API Server TLS connection |

The Vault administrator will configure the Kubernetes authentication method using these values.

Additionally, Vault roles and policies must be configured for each application ServiceAccount to control access to the appropriate secrets.

## 8. Security and Access Isolation

The reviewer ServiceAccount is shared across the cluster. It only provides Vault with the ability to validate Kubernetes identities.

It does not grant applications access to Vault secrets.

Access to secrets must be controlled separately through Vault roles and policies.

For example:

- Develop applications should only access their authorized develop secrets.
- Stage applications should only access their authorized stage secrets.

The reviewer JWT must be protected because anyone possessing it can authenticate as the reviewer ServiceAccount.

Since a manually created ServiceAccount token Secret does not expire automatically, its rotation and lifecycle must be managed carefully.

## 9. Final Kubernetes Resources

The following resources have been created:

| Resource | Name | Namespace |
|---|---|---|
| ServiceAccount | `vault-reviewer` | `kube-system` |
| ClusterRoleBinding | `vault-reviewer` | Cluster-wide |
| Secret | `vault-reviewer-token` | `kube-system` |
| ServiceAccount | `loan-develop` | `crouseserviceloan-develop` |
| ServiceAccount | `loan-stage` | `crouseserviceloan-stage` |

**Result:** The Kubernetes-side reviewer configuration is ready for the Vault administrator to configure Kubernetes Authentication. Application authentication will become operational after Vault authentication roles and policies are configured.