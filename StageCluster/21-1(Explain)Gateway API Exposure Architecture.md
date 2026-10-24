## Gateway API Exposure Architecture

The Gateway API is exposed externally through a Kubernetes `NodePort` Service.

Instead of using a Kubernetes `LoadBalancer` Service, the `cilium-nodeport` GatewayClass configures the Gateway Service as `NodePort`. This is suitable for the current environment because there is no Kubernetes LoadBalancer implementation.

The external Nginx/WAF acts as the entry point for client HTTPS traffic and forwards requests to the Gateway NodePort on the Kubernetes nodes.

```text
Client
  |
  | HTTPS :443
  v
Nginx / WAF
  |
  | HTTPS :31792
  |
  +-------------------+
  |                   |
  v                   v
Kubernetes Node    Kubernetes Node
  :31792             :31792
  |                   |
  v                   v
Cilium Gateway /   Cilium Gateway /
Envoy              Envoy
  |                   |
  +---------+---------+
            |
            v
       shared-gateway
            |
            v
       HTTPRoute
            |
            v
      Kubernetes Service
```

The Gateway Service is exposed as:

```text
443:31792/TCP
```

Port `443` is the Gateway listener port, while `31792` is the externally accessible NodePort.

The external Nginx/WAF can therefore use the Kubernetes nodes as Gateway entry points:

```text
172.25.3.197:31792
172.25.3.198:31792
172.25.9.114:31792
172.25.9.115:31792
172.25.25.18:31792
172.25.25.19:31792
```

Nginx/WAF can maintain an upstream pool containing the appropriate Kubernetes nodes and distribute incoming HTTPS traffic across them.

For example:

```nginx
upstream kubernetes_gateway {
    least_conn;

    server 172.25.3.197:31792;
    server 172.25.3.198:31792;
}
```

The Gateway API then performs the application-level routing based on the request hostname:

```text
gitops-stage.crouseco.com
        |
        v
   shared-gateway
        |
        v
   argocd-route
        |
        v
   argocd-server


app1.crouseco.com
        |
        v
   shared-gateway
        |
        v
     app1-route
        |
        v
    app1-service
```

### Why this architecture is used

This architecture separates the responsibilities of the external and Kubernetes layers:

| Component              | Responsibility                                                                                 |
| ---------------------- | ---------------------------------------------------------------------------------------------- |
| Nginx / WAF            | External HTTPS entry point, TLS handling for the external connection, and traffic distribution |
| NodePort               | Provides an externally reachable port on Kubernetes nodes                                      |
| Cilium Gateway / Envoy | Implements the Gateway API data plane                                                          |
| Gateway                | Defines the shared HTTPS entry point and accepted hostnames                                    |
| HTTPRoute              | Performs hostname/path-based application routing                                               |
| Kubernetes Service     | Provides access to the application workloads                                                   |

This provides a shared Gateway API entry point while keeping application routing inside Kubernetes.

The external Nginx/WAF does not need to know which Kubernetes Service hosts an application. It only needs to forward traffic to the Gateway NodePort. Gateway API handles the routing to the appropriate application Service.
