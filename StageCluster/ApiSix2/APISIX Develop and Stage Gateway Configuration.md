# APISIX Develop and Stage Gateway Configuration

## 1. Purpose

The Kubernetes cluster hosts separate APISIX instances for the develop and stage environments.

Both environments use the existing Cilium `shared-gateway` as the external entry point. Cilium receives incoming HTTPS traffic and forwards requests to the appropriate APISIX instance according to the hostname.

APISIX then handles API routing to the appropriate backend services.

The configuration is managed through Git and Argo CD rather than by manually applying persistent configuration changes to the cluster.

### Target architecture

```text
External Client
      |
      | HTTPS :443
      v
Cilium shared-gateway
Namespace: gateway-system
      |
      | Host-based HTTPRoute matching
      |
      +--------------------------------+
      |                                |
      v                                v
api-develop.crouseco.com       api-stage.crouseco.com
      |                                |
      v                                v
HTTPRoute                       HTTPRoute
Namespace: apisix-develop       Namespace: apisix-stage
      |                                |
      v                                v
APISIX Develop Service          APISIX Stage Service
      |                                |
      v                                v
APISIX Develop Instance         APISIX Stage Instance
      |                                |
      v                                v
Develop API backends            Stage API backends
```

The existing Cilium `shared-gateway` remains the external entry point. APISIX does not replace Cilium.

## 2. Environment separation

Each environment has its own APISIX namespace, GatewayClass, Gateway, GatewayProxy configuration, and ingress-controller configuration.

| Resource | Develop | Stage |
|---|---|---|
| Namespace | `apisix-develop` | `apisix-stage` |
| GatewayClass | `apisix-develop` | `apisix-stage` |
| APISIX Gateway | `apisix-develop-gateway` | `apisix-stage-gateway` |
| GatewayProxy | `apisix-develop-config` | `apisix-stage-config` |
| Ingress controller ConfigMap | `apisix-develop-ingress-config` | `apisix-stage-ingress-config` |
| Public hostname | `api-develop.crouseco.com` | `api-stage.crouseco.com` |
| APISIX Gateway Service port | `80` | `80` |

The existing Cilium Gateway remains:

- Namespace: `gateway-system`
- Name: `shared-gateway`
- GatewayClass: `cilium-nodeport`
- HTTPS listener: port `443`
- TLS certificate Secret: `crouseco-wildcard-tls`

The Gateway's listener allows HTTPRoutes from other namespaces.

## 3. Why separate APISIX GatewayClasses are required

A GatewayClass identifies which controller is responsible for managing a Gateway.

The APISIX develop and stage ingress controllers must use distinct controller identities. If both controllers use the same controller identity and observe the same GatewayClass, they may compete to manage the same Gateway resources.

The following identities were configured.

### Develop GatewayClass

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: apisix-develop
spec:
  controllerName: apisix.apache.org/apisix-develop-ingress-controller
```

### Stage GatewayClass

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: apisix-stage
spec:
  controllerName: apisix.apache.org/apisix-stage-ingress-controller
```

The `controllerName` must match the controller identity configured for the corresponding APISIX ingress controller.

Cilium uses its own controller identity, `io.cilium/gateway-controller`. This keeps Cilium and APISIX responsible for their respective Gateway resources.

## 4. Ingress-controller configuration changes

Each APISIX installation has its own ingress-controller configuration.

The ConfigMaps were updated to ensure that each controller uses the correct identity and a unique leader-election ID.

### Develop configuration

ConfigMap: `apisix-develop-ingress-config`

Namespace: `apisix-develop`

Relevant settings:

```yaml
controller_name: apisix.apache.org/apisix-develop-ingress-controller
leader_election_id: apisix-develop-ingress-controller-leader
```

### Stage configuration

ConfigMap: `apisix-stage-ingress-config`

Namespace: `apisix-stage`

Relevant settings:

```yaml
controller_name: apisix.apache.org/apisix-stage-ingress-controller
leader_election_id: apisix-stage-ingress-controller-leader
```

### Why these changes matter

**`controller_name`**

This value identifies the controller responsible for a GatewayClass. It must match the corresponding GatewayClass's `spec.controllerName`.

For example:

- The develop controller watches resources assigned to the develop controller identity.
- The stage controller watches resources assigned to the stage controller identity.

Previously, the controller identity did not match the intended GatewayClass identity. This caused the GatewayClass to remain unaccepted by the APISIX controller. Updating the ConfigMaps and aligning the GatewayClass identities resolved that mismatch.

**`leader_election_id`**

This identifies the leader-election group used by the controller.

Distinct IDs keep the develop and stage controllers' leader-election mechanisms separate. This is especially important when both installations operate in the same Kubernetes cluster.

The changes were managed through Git and Argo CD, so the committed configuration remains the source of truth.

## 5. APISIX Gateways

Each APISIX instance has its own Gateway resource and GatewayProxy configuration.

### Develop Gateway

Namespace: `apisix-develop`

Name: `apisix-develop-gateway`

GatewayClass: `apisix-develop`

GatewayProxy: `apisix-develop-config`

The Gateway uses an HTTP listener on port `80`.

### Stage Gateway

Namespace: `apisix-stage`

Name: `apisix-stage-gateway`

GatewayClass: `apisix-stage`

GatewayProxy: `apisix-stage-config`

The Gateway uses an HTTP listener on port `80`.

The GatewayProxy identifies the APISIX data-plane configuration used by the corresponding Gateway. Each environment references its own GatewayProxy rather than sharing one across both APISIX instances.

The Gateway resources report `Accepted=True` and `Programmed=True` when the controller accepts their configuration and programs them successfully.

## 6. Cilium HTTPRoutes forwarding traffic to APISIX

The Cilium HTTPRoutes connect the existing external Gateway to the correct APISIX Service.

These HTTPRoutes are intentionally placed in their respective APISIX namespaces.

This placement avoids the need for a cross-namespace `ReferenceGrant` for the backend Service reference.

### Develop HTTPRoute

File: `apisix/develop/cilium-apisix-route.yaml` (suggested repository path)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: cilium-to-apisix
  namespace: apisix-develop
spec:
  parentRefs:
    - name: shared-gateway
      namespace: gateway-system
  hostnames:
    - api-develop.crouseco.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: apisix-develop-gateway
          port: 80
```

### Stage HTTPRoute

File: `apisix/stage/cilium-apisix-route.yaml` (suggested repository path)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: cilium-to-apisix
  namespace: apisix-stage
spec:
  parentRefs:
    - name: shared-gateway
      namespace: gateway-system
  hostnames:
    - api-stage.crouseco.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: apisix-stage-gateway
          port: 80
```

The repository paths above are suggested locations. They should be adjusted to match the existing directory structure and Argo CD Application configuration.

### How the HTTPRoute works

The develop route:

1. Attaches to `gateway-system/shared-gateway`.
2. Matches requests whose hostname is `api-develop.crouseco.com`.
3. Matches paths beginning with `/`.
4. Forwards the request to `apisix-develop-gateway` on port `80`.

The stage route follows the same logic, using `api-stage.crouseco.com` and `apisix-stage-gateway`.

The hostname match prevents the develop route from being selected for the stage hostname and vice versa.

## 7. Why the HTTPRoutes are in the APISIX namespaces

A Kubernetes HTTPRoute has two different kinds of references:

- `parentRefs` identifies the Gateway to which the route attaches.
- `backendRefs` identifies the Service receiving the traffic.

These references have different namespace rules.

In this configuration, the HTTPRoute and its backend Service are in the same namespace, while the parent Cilium Gateway is in `gateway-system`.

For example:

| Resource | Namespace |
|---|---|
| Develop HTTPRoute | `apisix-develop` |
| Develop backend Service | `apisix-develop` |
| Cilium shared Gateway | `gateway-system` |

The Cilium Gateway permits routes from other namespaces through its listener configuration. Therefore, the route can attach to the shared Gateway while keeping its backend reference local to `apisix-develop`.

A `ReferenceGrant` is not required for the backend Service reference because the HTTPRoute and Service share a namespace.

If the HTTPRoute were instead located in `gateway-system` and referenced a Service in `apisix-develop`, that backend reference would require a `ReferenceGrant` in `apisix-develop`.

## 8. TLS termination and traffic flow

The external client connects using HTTPS:

- Develop: `https://api-develop.crouseco.com`
- Stage: `https://api-stage.crouseco.com`

The existing Cilium shared Gateway terminates TLS using its configured wildcard certificate Secret, `crouseco-wildcard-tls`.

The Cilium HTTPRoutes then forward traffic to the respective APISIX Gateway Services over HTTP on port `80` inside the cluster.

This means the external connection uses HTTPS, while the Cilium-to-APISIX hop uses HTTP. If encryption is required for that internal hop as well, it must be configured separately.

The existing external networking arrangement remains unchanged. Cilium continues to expose the shared Gateway through the established NodePort path.

## 9. Cilium routing versus APISIX API routing

There are two separate routing responsibilities.

### Cilium routing

Cilium selects the correct APISIX instance based on the incoming hostname:

- `api-develop.crouseco.com` goes to develop APISIX.
- `api-stage.crouseco.com` goes to stage APISIX.

The Cilium HTTPRoutes do not configure the final application backend.

### APISIX routing

APISIX is responsible for directing requests to the appropriate API backend according to its own configured routes.

For example, a request to:

`https://api-stage.crouseco.com/loan/home`

first reaches Cilium, then the stage APISIX instance. APISIX must have a matching route that forwards `/loan/home` to the intended stage API Service.

The equivalent develop API route must be configured in the develop APISIX instance.

These APISIX-to-application routes are separate from the Cilium HTTPRoutes described in this document.

## 10. GitOps workflow

The intended workflow is:

1. Edit the relevant YAML files in the Git repository.
2. Commit and push the changes to the configured branch.
3. Allow Argo CD to detect the changes and synchronize the relevant Application.
4. Verify the resources and their status in Kubernetes.

Avoid making persistent changes only through imperative `kubectl` commands, because those changes may not be reflected in Git and can be overwritten by a later synchronization.

## 11. Verification commands

Run these commands from a machine with access to the Kubernetes API.

### Verify GatewayClasses

```bash
kubectl get gatewayclass
```

Confirm that the develop and stage GatewayClasses are accepted and use their respective controller identities.

### Verify APISIX Gateways

```bash
kubectl get gateway -n apisix-develop
kubectl get gateway -n apisix-stage
```

Inspect the Gateway status:

```bash
kubectl describe gateway apisix-develop-gateway -n apisix-develop
kubectl describe gateway apisix-stage-gateway -n apisix-stage
```

Look for `Accepted=True` and `Programmed=True`.

### Verify APISIX Services

```bash
kubectl get svc -n apisix-develop
kubectl get svc -n apisix-stage
```

Confirm that the corresponding Gateway Services exist and expose port `80`.

### Verify Cilium HTTPRoutes

```bash
kubectl describe httproute cilium-to-apisix -n apisix-develop
kubectl describe httproute cilium-to-apisix -n apisix-stage
```

Check that:

- The expected hostname is present.
- The parent Gateway is `shared-gateway` in `gateway-system`.
- `Accepted=True` is reported.
- `ResolvedRefs=True` is reported.
- No backend reference errors are present.

You can also inspect all routes with:

```bash
kubectl get httproute -A
```

### Verify ingress-controller configuration

```bash
kubectl get configmap apisix-develop-ingress-config -n apisix-develop -o yaml
kubectl get configmap apisix-stage-ingress-config -n apisix-stage -o yaml
```

Confirm that the controller names and leader-election IDs are distinct and match the intended GatewayClasses.

### Verify controller logs

```bash
kubectl logs -n apisix-develop deploy/apisix-develop-ingress-controller --since=10m
kubectl logs -n apisix-stage deploy/apisix-stage-ingress-controller --since=10m
```

Check for controller identity mismatches, reconciliation errors, or APISIX Admin API authentication errors.

## 12. Troubleshooting reference

| Symptom | What to check |
|---|---|
| GatewayClass not accepted | Check that `spec.controllerName` matches the ingress-controller ConfigMap's `controller_name`. |
| HTTPRoute not accepted | Check the parent Gateway name, namespace, listener hostname, and allowed route namespaces. |
| `ResolvedRefs=False` with `RefNotPermitted` | Check whether the HTTPRoute references a backend Service in another namespace. Put the route beside the Service or add a suitable `ReferenceGrant`. |
| Gateway is programmed but the API does not respond correctly | Check the Cilium HTTPRoute, APISIX logs, and APISIX's own API routing configuration. |
| Develop hostname reaches the wrong instance | Check the hostname match and backend Service in the develop HTTPRoute. Repeat for stage. |
| APISIX cannot reconcile its configuration | Check the corresponding controller logs, GatewayProxy, APISIX Admin Service, and credentials configuration. |

## 13. Final configuration summary

The completed architecture separates the responsibilities of Cilium and APISIX:

- Cilium provides the shared external entry point and hostname-based forwarding.
- The develop and stage APISIX installations have separate namespaces and GatewayClasses.
- Each ingress controller has its own controller identity, ConfigMap, and leader-election ID.
- Each APISIX Gateway references its own GatewayProxy configuration.
- Each Cilium HTTPRoute resides beside its APISIX backend Service, avoiding an unnecessary cross-namespace backend reference.
- Argo CD manages the configuration through Git.
- APISIX routes remain responsible for forwarding API requests to the appropriate application Services.

This approach keeps the external Gateway shared while isolating the API-management layer between develop and stage.
