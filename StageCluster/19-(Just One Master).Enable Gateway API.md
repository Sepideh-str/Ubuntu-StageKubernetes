# Enable Gateway API

Cilium Gateway API support is enabled during the Cilium installation. The required Gateway API CRDs are installed separately from the internal Nexus repository.

## 1. Enable Gateway API in Cilium

Gateway API is enabled in the Cilium values file:

```yaml
gatewayAPI:
  enabled: true
```

The values file is:

```text
/root/cilium-values-1.20.2.yaml
```

Cilium is installed with:

```bash
helm install cilium cilium/cilium \
  --version 1.20.2 \
  -n kube-system \
  -f /root/cilium-values-1.20.2.yaml
```

Verify the installed configuration:

```bash
helm get values cilium -n kube-system
```

Confirm:

```yaml
gatewayAPI:
  enabled: true
```

---

## 2. Verify Cilium Rollout

```bash
kubectl rollout status daemonset/cilium -n kube-system
```

The rollout should complete successfully.

---

## 3. Install Gateway API CRDs

Gateway API CRDs are installed separately from the internal Nexus repository.

The current cluster uses:

```text
Gateway API: v1.6.1
```

Install the required CRDs:

```bash
kubectl apply -f https://repository.crouseco.com/repository/gateway-api-proxy/v1.6.1/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml

kubectl apply -f https://repository.crouseco.com/repository/gateway-api-proxy/v1.6.1/config/crd/standard/gateway.networking.k8s.io_gateways.yaml

kubectl apply -f https://repository.crouseco.com/repository/gateway-api-proxy/v1.6.1/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml

kubectl apply -f https://repository.crouseco.com/repository/gateway-api-proxy/v1.6.1/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml

kubectl apply -f https://repository.crouseco.com/repository/gateway-api-proxy/v1.6.1/config/crd/standard/gateway.networking.k8s.io_grpcroutes.yaml

kubectl apply -f https://repository.crouseco.com/repository/gateway-api-proxy/v1.6.1/config/crd/standard/gateway.networking.k8s.io_tlsroutes.yaml

kubectl apply -f https://repository.crouseco.com/repository/gateway-api-proxy/v1.6.1/config/crd/standard/gateway.networking.k8s.io_backendtlspolicies.yaml
```

---

## 4. Verify Gateway API CRDs

```bash
kubectl get crd | grep gateway.networking.k8s.io
```

Expected CRDs:

```text
backendtlspolicies.gateway.networking.k8s.io
gatewayclasses.gateway.networking.k8s.io
gateways.gateway.networking.k8s.io
grpcroutes.gateway.networking.k8s.io
httproutes.gateway.networking.k8s.io
referencegrants.gateway.networking.k8s.io
tlsroutes.gateway.networking.k8s.io
```

---

## 5. Verify the Cilium GatewayClass

Cilium creates the GatewayClass when Gateway API support is enabled.

Verify:

```bash
kubectl get gatewayclass
```

Expected:

```text
NAME     CONTROLLER                     ACCEPTED
cilium   io.cilium/gateway-controller   True
```

The `Accepted` condition must be `True`.

---

## 6. Configure Gateway Resources

Once the GatewayClass is available, Gateway resources can be created.

Verify existing Gateways:

```bash
kubectl get gateway -A
```

A successfully programmed Gateway should show:

```text
PROGRAMMED   True
```

Verify HTTPRoutes:

```bash
kubectl get httproute -A
```

Inspect a specific HTTPRoute:

```bash
kubectl describe httproute <route-name> -n <namespace>
```

A successfully accepted route should report:

```text
Accepted      True
ResolvedRefs  True
```

These conditions indicate that:

* Cilium accepted the HTTPRoute.
* The referenced backend Service was successfully resolved.

---

## 7. Verify Cilium Gateway Components

Check Cilium components:

```bash
kubectl get pods -n kube-system | grep cilium
```

The Cilium agents, Cilium Envoy pods, and Cilium Operator should be running.

Check Cilium status:

```bash
cilium status
```

Verify Gateway API configuration:

```bash
helm get values cilium -n kube-system
```

Expected:

```yaml
gatewayAPI:
  enabled: true
```

---

## Important Note

Gateway API support is enabled as part of the Cilium installation.

Therefore, when Cilium has already been installed with:

```yaml
gatewayAPI:
  enabled: true
```

a separate command such as:

```bash
helm upgrade cilium cilium/cilium \
  -n kube-system \
  --reuse-values \
  --set gatewayAPI.enabled=true
```

is not required.

The Cilium Operator also does not need to be manually restarted as part of the normal installation procedure.

The resulting deployment flow is:

```text
Cilium installation
        ↓
Gateway API enabled
        ↓
Gateway API CRDs
        ↓
Cilium GatewayClass
        ↓
Gateway
        ↓
HTTPRoute
        ↓
Cilium Envoy
        ↓
Backend Service
```
