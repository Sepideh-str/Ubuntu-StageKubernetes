# Argo CD Installation

## Overview

Argo CD is deployed as the GitOps continuous delivery component of the Kubernetes platform.

**Deployment:**

* Kubernetes: `v1.36.4`

* Argo CD: `v3.4.3`

* Helm chart: `argo-cd 9.5.21`

* Helm repository: Internal Nexus

* Namespace: `argocd`

* Argo CD Server: `ClusterIP`

* Dex: Disabled

* Server TLS: Disabled internally (`insecure: true`)

* Redis: Internal Redis deployment

* Argo CD workloads: Scheduled on Frontend worker nodes using `zone=frontend`

## 1. Add the Internal Helm Repository

The Argo CD Helm repository is proxied through Nexus because the Kubernetes environment does not have direct Internet access.

```bash

helm repo add argo https://repository.crouseco.com/repository/argo-helm/

helm repo update

```

Verify:

```bash

helm repo list

```

Expected:

```text

argo    https://repository.crouseco.com/repository/argo-helm/

```

Check the available chart versions:

```bash

helm search repo argo/argo-cd --versions

```

The validated version is:

```text

Chart: 9.5.21

App:   v3.4.3

```

## 2. Create the Namespace

```bash

kubectl create namespace argocd

```

Verify:

```bash

kubectl get namespace argocd

```

## 3. Verify Frontend Node Labels

Argo CD workloads are scheduled on Kubernetes worker nodes labeled:

```text

zone=frontend

```

Verify the labels:

```bash

kubectl get nodes -L zone

```

Expected Frontend workers:

```text

stage-workerf1    zone=frontend

stage-workerf2    zone=frontend

```

The `zone` label is a custom scheduling label used by the platform.

## 4. Create Argo CD Values

Create the values file:

```bash

mkdir -p ~/argocd-install

nano ~/argocd-install/values.yaml

```

Use:

```yaml

# =========================

# Argo CD Helm Values

# =========================

global:

  image:

    repository: repository.crouseco.com/quay-proxy/argoproj/argocd

# =========================

# SERVER

# =========================

server:

  nodeSelector:

    zone: frontend

  service:

    type: ClusterIP

  insecure: true

configs:

  params:

    server.insecure: true

# =========================

# AUTHENTICATION

# =========================

dex:

  enabled: false

# =========================

# REDIS

# =========================

redis:

  nodeSelector:

    zone: frontend

  image:

    repository: repository.crouseco.com/docker-proxy/redis

    tag: latest

# =========================

# CONTROLLER

# =========================

controller:

  nodeSelector:

    zone: frontend

  resources:

    requests:

      cpu: 250m

      memory: 256Mi

# =========================

# APPLICATIONSET

# =========================

applicationSet:

  nodeSelector:

    zone: frontend

# =========================

# NOTIFICATIONS

# =========================

notifications:

  nodeSelector:

    zone: frontend

# =========================

# REPOSITORY SERVER

# =========================

repoServer:

  nodeSelector:

    zone: frontend

  resources:

    requests:

      cpu: 250m

      memory: 256Mi

  livenessProbe:

    timeoutSeconds: 10

```

### Frontend Scheduling

The following Argo CD components explicitly use:

```yaml

nodeSelector:

  zone: frontend

```

This applies to:

* Application Controller

* ApplicationSet Controller

* Notifications Controller

* Redis

* Repository Server

* Argo CD Server

Kubernetes therefore schedules these continuously running workloads only on nodes labeled:

```text

zone=frontend

```

## 5. Install Argo CD

Install the validated version:

```bash

helm install argocd argo/argo-cd \

  --version 9.5.21 \

  -n argocd \

  -f ~/argocd-install/values.yaml

```

Verify the Helm release:

```bash

helm list -n argocd

```

Expected:

```text

NAME     NAMESPACE   STATUS     CHART          APP VERSION

argocd   argocd      deployed   argo-cd-9.5.21 v3.4.3

```

## 6. Verify Argo CD Pods

```bash

kubectl get pods -n argocd -o wide

```

Expected continuously running components:

```text

argocd-application-controller

argocd-applicationset-controller

argocd-notifications-controller

argocd-redis

argocd-repo-server

argocd-server

```

All continuously running components should be:

```text

1/1 Running

```

### Verify Node Placement

Check the `NODE` column:

```bash

kubectl get pods -n argocd -o wide

```

The running Argo CD components should be scheduled on:

```text

stage-workerf1

stage-workerf2

```

These nodes have:

```text

zone=frontend

```

Example:

```text

argocd-application-controller       stage-workerf1

argocd-applicationset-controller    stage-workerf2

argocd-notifications-controller     stage-workerf2

argocd-redis                         stage-workerf1

argocd-repo-server                   stage-workerf2

argocd-server                        stage-workerf1

```

### Redis Secret Initialization Job

During installation or upgrade, Argo CD may create a temporary Job:

```text

argocd-redis-secret-init-xxxxx

```

This Job may temporarily run on a different worker, including a DMZ worker.

This does not mean Redis is running on that node.

The Job initializes the Kubernetes Secret required by Redis and then finishes:

```text

STATUS: Completed

```

The actual Redis pod is controlled by the `redis.nodeSelector` and must run on a Frontend worker.

Check:

```bash

kubectl get pods -n argocd -o wide

```

The important distinction is:

```text

argocd-redis                  → Running → Frontend

argocd-redis-secret-init-*    → Completed → temporary Job

```

Check for unexpected restarts:

```bash

kubectl get pods -n argocd

```

The initial deployment should have no unexpected restarts.

## 7. Verify Services

```bash

kubectl get svc -n argocd

```

The Argo CD server is intentionally configured as:

```text

argocd-server    ClusterIP

```

This keeps Argo CD internal to the cluster. External access is provided through the platform's Gateway API configuration.

## 8. Configure HTTPRoute

Argo CD is exposed externally through an `HTTPRoute` attached to the platform's shared Gateway.

The `HTTPRoute` defines:

* The shared Gateway used for external access

* The hostname used to access Argo CD

* The backend Kubernetes Service

* The backend Service port

The Argo CD server remains a `ClusterIP` Service. The Gateway handles external traffic and routes requests to the internal `argocd-server` Service.

### 8.1 Create the HTTPRoute

Create the HTTPRoute manifest:

```bash

nano ~/argocd-install/argocd-route.yaml

```

Use:

```yaml

apiVersion: gateway.networking.k8s.io/v1

kind: HTTPRoute

metadata:

  name: argocd-route

  namespace: argocd

spec:

  parentRefs:

  - name: shared-gateway

    namespace: gateway-system

  hostnames:

  - "gitops-stage.crouseco.com"

  rules:

  - matches:

    - path:

        type: PathPrefix

        value: /

    backendRefs:

    - name: argocd-server

      port: 80

```

Apply the configuration:

```bash

kubectl apply -f ~/argocd-install/argocd-route.yaml

```

### 8.2 Verify the HTTPRoute

Check the HTTPRoute:

```bash

kubectl get httproute argocd-route -n argocd

```

For detailed status:

```bash

kubectl describe httproute argocd-route -n argocd

```

The HTTPRoute should report:

```text

Accepted=True

ResolvedRefs=True

```

`Accepted=True` confirms that the shared Gateway has accepted the route.

`ResolvedRefs=True` confirms that the referenced Gateway and backend Service can be resolved.

### 8.3 Verify the Parent Gateway

The HTTPRoute must reference the shared Gateway:

```text

Gateway:

  shared-gateway

Namespace:

  gateway-system

```

This allows multiple applications to use the same Gateway while maintaining separate hostnames and backend Services.

For example:

```text

HTTPRoute: app1-route

Hostname:  app1.crouseco.com

Backend:   app1-service

HTTPRoute: app2-route

Hostname:  app2.crouseco.com

Backend:   app2-service

```

Each application can therefore have its own `HTTPRoute` while sharing the same Gateway infrastructure.

## 9. Verify Repository Server

The repository server is an important component because it handles Git repository operations and manifest generation.

Check the image:

```bash

kubectl get pod -n argocd -l app.kubernetes.io/name=argocd-repo-server \

  -o jsonpath='{.items[0].spec.containers[0].image}'

```

Expected:

```text

repository.crouseco.com/quay-proxy/argoproj/argocd:v3.4.3

```

Check logs:

```bash

kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server

```

Healthy startup includes:

```text

ArgoCD Repository Server is starting

argocd-repo-server is listening on 0.0.0.0:8081

starting grpc server

```

Verify that the repository server is running on a Frontend worker:

```bash

kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server -o wide

```

## 10. Verify Redis

Check the Redis pod:

```bash

kubectl get pod -n argocd -l app.kubernetes.io/name=argocd-redis -o wide

```

The Redis pod should be running on a node with:

```text

zone=frontend

```

Check the service:

```bash

kubectl get svc argocd-redis -n argocd

```

Verify Redis authentication from inside the Redis pod:

```bash

redis-cli -a "$(kubectl get secret argocd-redis \

  -n argocd \

  -o jsonpath='{.data.auth}' | base64 -d)" ping

```

Expected:

```text

PONG

```

## 11. Verify Argo CD Server

Check the server:

```bash

kubectl get pod -n argocd -l app.kubernetes.io/name=argocd-server -o wide

```

The server should be running on a Frontend worker.

Check logs:

```bash

kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

```

Check the server service:

```bash

kubectl get svc argocd-server -n argocd

```

Because the service is `ClusterIP`, it is currently accessible only from inside the cluster.

## 12. Final Health Check


Run:

```bash

kubectl get pods -n argocd -o wide

kubectl get svc -n argocd

kubectl get nodes -L zone

helm list -n argocd

```

Expected state:

* All continuously running Argo CD pods are `Running`

* Argo CD workloads are scheduled on `zone=frontend` nodes

* No unexpected pod restarts

* Repo-server is healthy

* Redis responds with `PONG`

* Argo CD server is `ClusterIP`

* Helm release is `deployed`

* Argo CD version is `v3.4.3`




## 13. Configure Argo CD CLI and Read-Only User

This section documents the complete process for:

- Installing the Argo CD CLI on `Stage-MasterF1`
- Creating a local Argo CD user named `devops`
- Setting a password for the `devops` user
- Creating a temporary NodePort for CLI access
- Logging in with the `devops` user
- Assigning the built-in `role:readonly` role
- Verifying the user's permissions
- Removing the temporary NodePort

The temporary NodePort is used only for administration and is removed after the configuration is completed.

---

### 13.1 Install the Argo CD CLI on the Kubernetes Master

The Linux Argo CD CLI binary was copied to:

```text
/home/user/argocd-linux-amd64
```

Make the binary executable:

```bash
chmod +x /home/user/argocd-linux-amd64
```

Test the CLI:

```bash
/home/user/argocd-linux-amd64 version --client
```

Install the CLI system-wide:

```bash
mv /home/user/argocd-linux-amd64 /usr/local/bin/argocd
```

Verify the installation:

```bash
argocd version --client
```

Expected output:

```text
argocd: v3.4.x
Platform: linux/amd64
```

The Argo CD CLI is now available system-wide:

```bash
argocd
```

---

### 13.2 Create the `devops` Argo CD User

Local Argo CD users are configured in the `argocd-cm` ConfigMap.

Edit the ConfigMap:

```bash
kubectl edit configmap argocd-cm -n argocd
```

Under `data:`, add:

```yaml
data:
  accounts.devops: login
```

For example:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  accounts.devops: login
```

The important configuration is:

```yaml
accounts.devops: login
```

This creates a local Argo CD account named:

```text
devops
```

The `login` capability allows the user to authenticate with a username and password.

Verify the configuration:

```bash
kubectl get configmap argocd-cm -n argocd -o yaml
```

Look for:

```yaml
accounts.devops: login
```

---

### 13.3 Create a Temporary NodePort for CLI Access

The normal Argo CD server service remains a `ClusterIP`.

A temporary `NodePort` is created so that the Argo CD CLI can connect directly to the Argo CD server.

Create the following file:

```text
argocd-server-nodeport.yaml
```

Use:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: argocd-server-nodeport
  namespace: argocd
spec:
  type: NodePort
  selector:
    app.kubernetes.io/instance: argocd
    app.kubernetes.io/name: argocd-server
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 8080
      nodePort: 30080
    - name: https
      protocol: TCP
      port: 443
      targetPort: 8080
      nodePort: 30443
```

Apply the Service:

```bash
kubectl apply -f argocd-server-nodeport.yaml
```

Verify:

```bash
kubectl get svc -n argocd argocd-server-nodeport
```

Expected output:

```text
NAME                     TYPE       CLUSTER-IP   EXTERNAL-IP   PORT(S)
argocd-server-nodeport   NodePort   ...          <none>        80:30080/TCP,443:30443/TCP
```

The NodePort used for CLI access is:

```text
30080
```

The temporary access path is:

```text
Argo CD CLI
     |
     v
172.25.3.197:30080
     |
     v
argocd-server
```

---

### 13.4 Set the `devops` Password

Creating the user does not automatically configure a password.

Set the password using the Argo CD CLI:

```bash
argocd account update-password --account devops
```

The CLI asks for the password interactively.

The actual password must **not** be stored in this documentation.

After this step:

```text
Username: devops
Password: configured separately
```

---

### 13.5 Login as the `devops` User

Use the temporary NodePort:

```bash
argocd login 172.25.3.197:30080 --plaintext
```

Enter:

```text
Username: devops
Password: <devops-password>
```

A successful login should show a message similar to:

```text
'devops:login' logged in successfully
```

At this point, the user exists and can authenticate.

Authentication and authorization are separate.

The user's permissions are configured through Argo CD RBAC.

---

### 13.6 Configure Read-Only Permissions

Argo CD RBAC permissions are configured in:

```text
argocd-rbac-cm
```

Edit the ConfigMap:

```bash
kubectl edit configmap argocd-rbac-cm -n argocd
```

Configure:

```yaml
data:
  policy.csv: |
    g, devops, role:readonly
  policy.default: ""
  policy.matchMode: glob
  scopes: '[groups]'
```

The important RBAC rule is:

```text
g, devops, role:readonly
```

This assigns the built-in:

```text
role:readonly
```

to:

```text
devops
```

The relationship is:

```text
devops
   |
   v
role:readonly
```

Verify the RBAC configuration:

```bash
kubectl get configmap argocd-rbac-cm -n argocd -o yaml
```

Look for:

```yaml
policy.csv: |
  g, devops, role:readonly
```

---

### 13.7 Verify the `devops` Permissions

Login as `devops`:

```bash
argocd login 172.25.3.197:30080 --plaintext
```

#### Check Read Permission

```bash
argocd account can-i get applications '*'
```

Expected:

```text
yes
```

#### Check Update Permission

```bash
argocd account can-i update applications '*'
```

Expected:

```text
no
```

#### Check Delete Permission

```bash
argocd account can-i delete applications '*'
```

Expected:

```text
no
```

#### Check Sync Permission

```bash
argocd account can-i sync applications '*'
```

Expected:

```text
no
```

The intended permission model is:

| Operation | `devops` |
|---|---|
| View applications | Allowed |
| Update applications | Not allowed |
| Delete applications | Not allowed |
| Sync applications | Not allowed |

Verify that applications are visible:

```bash
argocd app list
```

---

### 13.8 Remove the Temporary NodePort

After completing and verifying:

- `devops` user creation
- Password configuration
- Login
- RBAC configuration
- Permission verification

Remove the temporary NodePort:

```bash
kubectl delete svc argocd-server-nodeport -n argocd
```

Expected output:

```text
service "argocd-server-nodeport" deleted
```

Verify:

```bash
kubectl get svc -n argocd
```

The temporary service:

```text
argocd-server-nodeport
```

should no longer exist.

The permanent Argo CD service remains:

```text
argocd-server
```

with type:

```text
ClusterIP
```

---

### 13.9 Temporary CLI Access

During configuration:

```text
Argo CD CLI
     |
     v
172.25.3.197:30080
     |
     v
Temporary NodePort
     |
     v
argocd-server
```

After configuration:

```text
Temporary NodePort
       |
       X
    Deleted
```

The temporary NodePort is not required for the permanent Argo CD configuration.

---

### 13.10 Permanent Argo CD Access

The permanent Argo CD access path remains through the existing Gateway and HTTPRoute configuration.

Conceptually:

```text
External Client
      |
      v
   Gateway
      |
      v
  HTTPRoute
      |
      v
argocd-server
      |
      v
ClusterIP Service
```

The temporary NodePort is separate from this permanent access path.

---

### 13.11 Final User Configuration

The final user configuration is:

```text
Argo CD
   |
   +-- Local User
   |      |
   |      +-- devops
   |
   +-- Authentication
   |      |
   |      +-- Username/password
   |
   +-- RBAC
   |      |
   |      +-- role:readonly
   |
   +-- Permissions
          |
          +-- Read applications
          +-- Cannot update applications
          +-- Cannot delete applications
          +-- Cannot sync applications
```

---

### 13.12 Complete Procedure

The complete procedure is:

```text
1. Install Argo CD CLI
        |
        v
2. Create `devops` local user
        |
        v
3. Create temporary NodePort
        |
        v
4. Set `devops` password
        |
        v
5. Login as `devops`
        |
        v
6. Assign `role:readonly`
        |
        v
7. Verify permissions
        |
        v
8. Delete temporary NodePort
```

---

### 13.13 Final Result

After completing the procedure:

- The local Argo CD user `devops` exists.
- The `devops` user can authenticate using a username and password.
- The `devops` user is assigned the built-in `role:readonly` role.
- The user can view Argo CD applications.
- The user cannot update applications.
- The user cannot delete applications.
- The user cannot sync applications.
- The temporary NodePort `30080` is removed.
- The permanent `argocd-server` Service remains a `ClusterIP`.
- The existing Gateway and HTTPRoute remain unchanged.

## Version Selection Note


Argo CD `v3.5.3` was tested using Helm chart `10.9.2`, but the repository server repeatedly failed its full health check:

```text

/healthz?full=true

```

Increasing the Kubernetes liveness probe timeout from `1s` to `10s` did not resolve the issue. The `v3.5.3` repository server also returned an empty response for the full health endpoint while the basic `/healthz` endpoint returned `200 OK`.

The deployment was therefore switched back to the previously validated version:

```text

Argo CD v3.4.3

Helm chart 9.5.21

```

The `v3.4.3` repository server remained stable with the same Kubernetes environment and Redis configuration.

This document records the **currently validated installation**, rather than the failed upgrade attempt.

