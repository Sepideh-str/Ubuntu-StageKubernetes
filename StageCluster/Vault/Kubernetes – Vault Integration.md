# Kubernetes – Vault Integration

## 1. Overview

Kubernetes integrates with HashiCorp Vault through the Kubernetes Authentication Method.

Vault uses the Kubernetes API's **TokenReview API** to validate ServiceAccount JWTs issued to workloads running inside the cluster.

For this integration, Kubernetes provides a dedicated ServiceAccount that Vault uses to perform token reviews.

The integration involves two separate ServiceAccounts:

| ServiceAccount | Namespace | Purpose |
|---|---|---|
| `vault-reviewer` | `kube-system` | Allows Vault to validate Kubernetes ServiceAccount tokens |
| `loan-develop` | `crouseserviceloan-develop` | Identity used by the application when authenticating to Vault |

## 2. Create the Vault Reviewer ServiceAccount

Create a dedicated ServiceAccount in the `kube-system` namespace.

**File:** `vault-reviewer-serviceaccount.yaml`

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-reviewer
  namespace: kube-system
```

Apply the configuration:

```bash
kubectl apply -f vault-reviewer-serviceaccount.yaml
```

## 3. Grant Token Review Permissions

Vault needs permission to call the Kubernetes TokenReview API.

Kubernetes provides a built-in ClusterRole named `system:auth-delegator`, which grants the permissions required for delegated authentication.

Create a ClusterRoleBinding to associate this role with the `vault-reviewer` ServiceAccount.

**File:** `vault-reviewer-clusterrolebinding.yaml`

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-reviewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: vault-reviewer
    namespace: kube-system
```

Apply the configuration:

```bash
kubectl apply -f vault-reviewer-clusterrolebinding.yaml
```

This grants the ServiceAccount permission to submit TokenReview requests to the Kubernetes API.

## 4. Create a ServiceAccount Token Secret

Kubernetes versions 1.24 and later do not automatically create long-lived ServiceAccount token Secrets.

To provide Vault with a reviewer JWT, create a dedicated Secret.

**File:** `vault-reviewer-token.yaml`

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

Apply the configuration:

```bash
kubectl apply -f vault-reviewer-token.yaml
```

Kubernetes automatically populates the Secret with the ServiceAccount token and related certificate information.

Wait until the token is populated before extracting it.

## 5. Retrieve the Reviewer JWT

Retrieve the JWT generated for the `vault-reviewer` ServiceAccount:

```bash
kubectl get secret vault-reviewer-token -n kube-system \
  -o jsonpath="{.data.token}"
```

The returned value is Base64 encoded.

To decode it in PowerShell:

```powershell
$token = kubectl get secret vault-reviewer-token `
  -n kube-system `
  -o jsonpath="{.data.token}"

[System.Text.Encoding]::UTF8.GetString(
    [System.Convert]::FromBase64String($token)
)
```

The decoded JWT is provided to the Vault administrator for configuring Kubernetes authentication.

**Important:** This token grants Kubernetes authentication review permissions. It must be handled as a sensitive credential and must not be committed to Git repositories.

## 6. Retrieve the Kubernetes CA Certificate

Vault needs the Kubernetes cluster CA certificate to establish a trusted TLS connection with the Kubernetes API.

Retrieve the CA certificate associated with the reviewer token:

```bash
kubectl get secret vault-reviewer-token -n kube-system \
  -o jsonpath="{.data.ca\.crt}"
```

The result is Base64 encoded. Decode it before providing the certificate to the Vault administrator.

## 7. Create the Application ServiceAccount

Each application authenticating to Vault uses its own Kubernetes ServiceAccount.

For the Loan application, create a ServiceAccount in the application namespace.

**File:** `loan-develop-serviceaccount.yaml`

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: loan-develop
  namespace: crouseserviceloan-develop
```

Apply the configuration:

```bash
kubectl apply -f loan-develop-serviceaccount.yaml
```

The application Deployment must reference this ServiceAccount:

```yaml
spec:
  template:
    spec:
      serviceAccountName: loan-develop
```

Kubernetes automatically provides a projected ServiceAccount token to the application Pod, unless automatic token mounting has been disabled.

This token represents the application's Kubernetes identity when authenticating to Vault.

Unlike the reviewer ServiceAccount, the application ServiceAccount does not require the `system:auth-delegator` permission.

## 8. Verify Kubernetes Resources

Verify the reviewer ServiceAccount:

```bash
kubectl get serviceaccount vault-reviewer -n kube-system
```

Verify the ClusterRoleBinding:

```bash
kubectl get clusterrolebinding vault-reviewer
```

Verify the reviewer token Secret:

```bash
kubectl get secret vault-reviewer-token -n kube-system


kubectl get secret vault-reviewer-token \
  -n kube-system \
  -o jsonpath='{.data.token}' | base64 -d
```

Verify the application ServiceAccount:

```bash
kubectl get serviceaccount loan-develop \
  -n crouseserviceloan-develop
```

Verify the application Deployment:

```bash
kubectl get deployment -n crouseserviceloan-develop
```

Inspect the Deployment's configured ServiceAccount:

```bash
kubectl get deployment <deployment-name> \
  -n crouseserviceloan-develop \
  -o jsonpath="{.spec.template.spec.serviceAccountName}"
```

## 9. Kubernetes Resources Summary

| Resource | Namespace | Name |
|---|---|---|
| ServiceAccount | `kube-system` | `vault-reviewer` |
| ClusterRoleBinding | Cluster-wide | `vault-reviewer` |
| Secret | `kube-system` | `vault-reviewer-token` |
| ServiceAccount | `crouseserviceloan-develop` | `loan-develop` |

## 10. Integration Workflow

The Kubernetes-side authentication workflow is:

1. Kubernetes creates and manages ServiceAccount identities.
2. The application Pod receives a projected ServiceAccount JWT.
3. Vault receives the JWT and submits a TokenReview request to the Kubernetes API.
4. Kubernetes validates the JWT and returns the authentication result.
5. Vault uses the validated Kubernetes identity to determine the associated Vault role and permissions.

The `vault-reviewer` ServiceAccount provides the permissions Vault needs to perform step 3.

The `loan-develop` ServiceAccount provides the workload identity used in step 2.

**Security consideration:** The reviewer JWT is a long-lived credential in this configuration. Protect its Secret with appropriate Kubernetes RBAC and operational controls, and establish a rotation procedure.