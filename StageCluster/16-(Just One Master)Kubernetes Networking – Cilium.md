# Kubernetes Networking – Cilium

## Overview

Cilium is used as the Kubernetes CNI for:

* Pod networking
* Network policy
* eBPF-based networking
* Kubernetes Gateway API
* Cilium Envoy

The cluster uses:

* Cilium `1.20.2`
* Tunnel mode
* Geneve tunneling
* `kubeProxyReplacement=true`
* Cilium Gateway API
* Internal Nexus for Helm charts and container images

---

## Nexus Repositories

### Helm Repository

Cilium is installed from the internal Nexus Helm repository:

```text
https://repository.crouseco.com/repository/cilium-helm-proxy/
```

Add and update the repository:

```bash
helm repo add cilium https://repository.crouseco.com/repository/cilium-helm-proxy/
helm repo update
```

Check the available Cilium charts:

```bash
helm search repo cilium
```

The cluster uses:

```text
Cilium: 1.20.2
```

### Docker Image Repository

Kubernetes nodes use the internal Nexus Docker registry:

```text
repository.crouseco.com/cilium-images/
```

For containerd/Docker image references, do **not** include `/repository/`.

Correct:

```text
repository.crouseco.com/cilium-images/...
```

Nexus REST/API URLs may contain `/repository/`, for example:

```text
https://repository.crouseco.com/repository/cilium-images/
```

---

## Required Cilium Images

Because the Kubernetes nodes do not have direct Internet access, the required Cilium images must be available in Nexus before deployment.

The current images are:

```text
repository.crouseco.com/cilium-images/cilium/cilium:v1.20.2

repository.crouseco.com/cilium-images/cilium/operator-generic:v1.20.2

repository.crouseco.com/cilium-images/cilium/cilium-envoy:v1.37.6-1789133542-cbec91f666af0bf742da986d43832932dbb26b82
```

The Envoy image is pinned by digest:

```text
sha256:af7382699576b9e65e9184efa52eeca0b58aea70ad6e511bf260c91d9f740463
```

### Pre-cache Images

From a machine that can access the Nexus Docker registry:

```bash
docker pull repository.crouseco.com/cilium-images/cilium/cilium:v1.20.2

docker pull repository.crouseco.com/cilium-images/cilium/operator-generic:v1.20.2

docker pull repository.crouseco.com/cilium-images/cilium/cilium-envoy:v1.37.6-1789133542-cbec91f666af0bf742da986d43832932dbb26b82
```

This ensures that the required image layers are available in Nexus before the offline Kubernetes nodes attempt to pull them.

---

## Cilium Configuration

Create the Cilium values file:

```bash
nano /root/cilium-values-1.20.2.yaml
```

Use:

```yaml
image:
  repository: repository.crouseco.com/cilium-images/cilium/cilium
  tag: v1.20.2
  useDigest: false

operator:
  image:
    repository: repository.crouseco.com/cilium-images/cilium/operator
    tag: v1.20.2
    useDigest: false

envoy:
  image:
    repository: repository.crouseco.com/cilium-images/cilium/cilium-envoy
    tag: v1.37.6-1789133542-cbec91f666af0bf742da986d43832932dbb26b82
    digest: sha256:af7382699576b9e65e9184efa52eeca0b58aea70ad6e511bf260c91d9f740463
    useDigest: true

k8sServiceHost: 172.25.3.199
k8sServicePort: 7443

kubeProxyReplacement: true

tunnelProtocol: geneve

gatewayAPI:
  enabled: true
```

The Kubernetes API endpoint used by Cilium is:

```text
172.25.3.199:7443
```

---

## Cilium Installation

Install Cilium using the internal Nexus Helm repository and the values file:

```bash
helm install cilium cilium/cilium \
  --version 1.20.2 \
  -n kube-system \
  -f /root/cilium-values-1.20.2.yaml
```

Verify the Helm release:

```bash
helm list -n kube-system
```

Expected:

```text
cilium    kube-system    ...    deployed
```

---

## Cilium Networking

The cluster uses Cilium tunnel mode with Geneve:

```text
Cilium
└── Tunnel mode
    └── Geneve
        └── UDP 6081
```

Verify the configuration:

```bash
kubectl -n kube-system get configmap cilium-config -o yaml | \
  grep -E 'routing|tunnel'
```

Expected relevant configuration:

```text
routing-mode: tunnel
tunnel-protocol: geneve
```

---

## Gateway API

Cilium Gateway API support is enabled:

```yaml
gatewayAPI:
  enabled: true
```

This allows Cilium to manage Kubernetes Gateway API resources using the Cilium Gateway controller and Envoy.

The cluster uses a Cilium GatewayClass:

```text
cilium
```

A NodePort-based GatewayClass can also be configured when Gateway traffic needs to be exposed through Kubernetes NodePorts.

Example:

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumGatewayClassConfig
metadata:
  name: nodeport-gateway-config
  namespace: kube-system
spec:
  service:
    type: NodePort
```

Gateway API resources should be verified with:

```bash
kubectl get gatewayclass
kubectl get gateway -A
kubectl get httproute -A
```

A programmed Gateway should show:

```text
PROGRAMMED   True
```

An accepted HTTPRoute should show:

```text
Accepted      True
ResolvedRefs  True
```

---

## Network Requirements

Cilium requires node-to-node connectivity for its networking components.

Current required ports:

| Protocol | Port | Source               | Destination          | Purpose       |
| -------- | ---: | -------------------- | -------------------- | ------------- |
| UDP      | 6081 | All Kubernetes nodes | All Kubernetes nodes | Cilium Geneve |
| TCP      | 4240 | All Kubernetes nodes | All Kubernetes nodes | Cilium health |

These ports must be permitted between the Kubernetes nodes despite their placement in different network zones.

---

## Verification

### Check Cilium Pods

```bash
kubectl get pods -n kube-system -o wide
```

All Cilium agent pods should be:

```text
1/1 Running
```

Check Cilium Envoy:

```bash
kubectl get pods -n kube-system | grep cilium-envoy
```

Check Cilium Operator:

```bash
kubectl get pods -n kube-system | grep cilium-operator
```

### Check Nodes

```bash
kubectl get nodes
```

All joined Kubernetes nodes should be:

```text
Ready
```

### Check Cilium Status

```bash
cilium status
```

If the Cilium CLI is not installed:

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg status --verbose
```

### Check Helm Values

```bash
helm get values cilium -n kube-system
```

Expected relevant values:

```text
kubeProxyReplacement: true
k8sServiceHost: 172.25.3.199
k8sServicePort: 7443
tunnelProtocol: geneve
gatewayAPI:
  enabled: true
```

---

## Troubleshooting ImagePullBackOff

If a Cilium pod reports:

```text
ImagePullBackOff
```

or:

```text
ErrImagePull
```

check the pod events:

```bash
kubectl describe pod <pod-name> -n kube-system
```

Pay particular attention to the exact image reference requested by Kubernetes.

Correct Nexus Docker registry format:

```text
repository.crouseco.com/cilium-images/...
```

The following format is a Nexus REST/API path and should not be used as the container registry path:

```text
repository.crouseco.com/repository/cilium-images/...
```

If the image is already available in Nexus but the node is having difficulty pulling it, the image can be pre-pulled directly into the containerd Kubernetes namespace:

```bash
ctr -n k8s.io images pull <image>
```

After the image is available locally, recreate the affected Cilium pod:

```bash
kubectl delete pod <pod-name> -n kube-system
```

The Cilium DaemonSet will automatically recreate the pod.

---

## Cilium Gateway Troubleshooting

If a Gateway shows:

```text
PROGRAMMED=True
```

but traffic does not reach the backend, first verify the generated Gateway Service:

```bash
kubectl get svc -A | grep cilium-gateway
```

For a NodePort Gateway, the service should show:

```text
NodePort
```

For example:

```text
cilium-gateway-test-gateway   NodePort   ...   80:30526/TCP
```

Verify the HTTPRoute:

```bash
kubectl describe httproute -n argocd argocd-route
```

The route should report:

```text
Accepted=True
ResolvedRefs=True
```

A direct NodePort test can then be performed:

```bash
curl -v \
  -H "Host: gitops-stage.crouseco.com" \
  http://<node-ip>:<node-port>/
```

A successful response from an Envoy-managed Gateway should contain:

```text
HTTP/1.1 200 OK
server: envoy
```

---

## Cilium Operator

Cilium Operator runs with multiple replicas for availability.

Verify:

```bash
kubectl get pods -n kube-system | grep cilium-operator
```

Multiple replicas may be deployed depending on the cluster configuration.

---

## CoreDNS

CoreDNS is deployed with two replicas for availability.

Verify:

```bash
kubectl get pods -n kube-system | grep coredns
```

Both replicas should normally be:

```text
1/1 Running
```

---

## Current Status

The Kubernetes cluster is currently running:

* Kubernetes `v1.36.4`
* Cilium `1.20.2`
* Cilium tunnel mode
* Geneve networking
* UDP `6081`
* Cilium health on TCP `4240`
* `kubeProxyReplacement=true`
* Cilium Envoy
* Cilium Operator
* Cilium Gateway API support
* CoreDNS
* Internal Nexus Helm repository
* Internal Nexus container registry

The Cilium networking layer is operational and the Cilium Gateway API integration has been verified with a NodePort Gateway and HTTPRoute.
