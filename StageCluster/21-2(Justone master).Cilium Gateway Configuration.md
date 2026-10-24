# Cilium Gateway Configuration

## 1. GatewayClass

Cilium automatically creates and manages the default `cilium` GatewayClass when Gateway API is enabled.

Verify:

```bash
kubectl get gatewayclass
```

Expected:

```text
NAME              CONTROLLER                     ACCEPTED
cilium            io.cilium/gateway-controller   True
cilium-nodeport   io.cilium/gateway-controller   True
```

The default `cilium` GatewayClass uses a LoadBalancer Service. Since this cluster does not have a LoadBalancer implementation, the Gateway would remain without an assigned external address.

For this cluster, a custom `cilium-nodeport` GatewayClass is used to expose the Gateway through NodePort.

Create the Cilium GatewayClass configuration:

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumGatewayClassConfig
metadata:
  name: nodeport-gateway-config
  namespace: kube-system
spec:
  service:
    externalTrafficPolicy: Cluster
    loadBalancerSourceRangesPolicy: Allow
    type: NodePort
```

Apply:

```bash
kubectl apply -f cilium-nodeport-config.yaml
```

Create the GatewayClass:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: cilium-nodeport
spec:
  controllerName: io.cilium/gateway-controller
  parametersRef:
    group: cilium.io
    kind: CiliumGatewayClassConfig
    name: nodeport-gateway-config
    namespace: kube-system
```

Apply:

```bash
kubectl apply -f gatewayclass.yaml
```

Verify:

```bash
kubectl get gatewayclass
```

The `cilium-nodeport` GatewayClass should show:

```text
ACCEPTED   True
```

---

## 2. Shared HTTPS Gateway

The shared Gateway provides a common HTTPS entry point for multiple applications.

The listener uses the wildcard hostname `*.crouseco.com`, allowing multiple application hostnames to use the same Gateway.

Create the Gateway:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shared-gateway
  namespace: gateway-system
spec:
  gatewayClassName: cilium-nodeport

  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    hostname: "*.crouseco.com"

    tls:
      mode: Terminate
      certificateRefs:
      - name: crouseco-wildcard-tls

    allowedRoutes:
      namespaces:
        from: All
```

Apply:

```bash
kubectl apply -f shared-gateway.yaml
```

Verify:

```bash
kubectl get gateway shared-gateway -n gateway-system
```

Expected:

```text
NAME             CLASS             ADDRESS        PROGRAMMED
shared-gateway   cilium-nodeport   172.25.3.194   True
```

The Gateway is assigned node addresses across the cluster.

The important Gateway conditions are:

```text
Accepted=True
Programmed=True
```

For detailed status:

```bash
kubectl describe gateway shared-gateway -n gateway-system
```

The listener should also show:

```text
Accepted=True
Programmed=True
ResolvedRefs=True
```

### Hostname and routing

The Gateway listener defines the hostnames that can enter through the shared HTTPS listener:

```text
*.crouseco.com
```

Individual `HTTPRoute` resources define which specific hostname is routed to which application Service.

For example:

```text
app1.crouseco.com ──> app1-route ──> app1-service
app2.crouseco.com ──> app2-route ──> app2-service
gitops-stage.crouseco.com ──> argocd-route ──> argocd-server
```

This allows multiple applications to share the same Gateway and NodePort.

---

## 3. Generated Gateway Service

Cilium automatically creates a Service for the Gateway.

Verify:

```bash
kubectl get svc -n gateway-system
```

The Gateway Service is:

```text
cilium-gateway-shared-gateway
```

Current configuration:

```text
TYPE       PORT(S)
NodePort   443:31792/TCP
```

Inspect the Service:

```bash
kubectl describe svc cilium-gateway-shared-gateway -n gateway-system
```

The HTTPS Gateway listens on port `443`, while the generated NodePort exposes it externally on:

```text
31792/TCP
```

External Nginx/WAF can therefore forward HTTPS traffic to the Kubernetes nodes on port `31792`.

---

## 4. HTTPRoute

Applications are exposed through `HTTPRoute` resources attached to the shared Gateway.

Each route specifies the hostname and backend Service for an application.

Example For Argo CD:

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

Apply:

```bash
kubectl apply -f argocd-route.yaml
```

Verify:

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

The `parentRefs` must reference the shared Gateway:

```text
shared-gateway
namespace: gateway-system
```

Additional applications can use the same Gateway by creating additional `HTTPRoute` resources with their own hostnames and backend Services.

Example:

```text
HTTPRoute: app1-route
Hostname: app1.crouseco.com
Backend: app1-service

HTTPRoute: app2-route
Hostname: app2.crouseco.com
Backend: app2-service
```

---

## 5. Traffic Flow

The shared Gateway architecture is:

```text
Client
  |
  | HTTPS :443
  v
Nginx / WAF
  |
  | HTTPS :31792
  v
Kubernetes Node
  |
  v
Cilium Envoy
  |
  v
shared-gateway
  |
  +-- Host: gitops-stage.crouseco.com
  |       |
  |       v
  |   argocd-route
  |       |
  |       v
  |   argocd-server:80
  |
  +-- Host: app1.crouseco.com
  |       |
  |       v
  |   app1-route
  |       |
  |       v
  |   app1-service
  |
  +-- Host: app2.crouseco.com
          |
          v
      app2-route
          |
          v
      app2-service
```

The Gateway provides the shared HTTPS entry point, while `HTTPRoute` resources perform hostname-based application routing.

Cilium Envoy handles the Gateway traffic on the Kubernetes nodes. The NodePort allows the external Nginx/WAF to reach the Gateway without requiring a separate LoadBalancer implementation.

---

## 6. Verification

Check GatewayClasses:

```bash
kubectl get gatewayclass
```

Check Gateways:

```bash
kubectl get gateways -A
```

Check HTTPRoutes:

```bash
kubectl get httproutes -A
```

Check the generated Gateway Service:

```bash
kubectl get svc -n gateway-system
```

Check the Gateway status:

```bash
kubectl get gateway shared-gateway -n gateway-system
```

Check the Argo CD route:

```bash
kubectl get httproute argocd-route -n argocd
```

For detailed route status:

```bash
kubectl describe httproute argocd-route -n argocd
```

The final architecture is:

```text
GatewayClass
    cilium-nodeport
          |
          v
shared-gateway
    *.crouseco.com
          |
          +-------------------+
          |                   |
          v                   v
   argocd-route          other HTTPRoutes
          |                   |
          v                   v
   argocd-server          application Services
```

The temporary `test-gateway` used during Gateway API validation is not part of the final configuration.
