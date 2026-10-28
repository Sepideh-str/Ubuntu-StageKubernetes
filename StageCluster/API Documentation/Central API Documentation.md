# Central API Documentation

## 1. Overview

The central API documentation system provides one Swagger UI for discovering and testing multiple APIs running on the Kubernetes platform.

Instead of maintaining a separate Swagger UI for every application, a central Swagger UI dynamically discovers registered APIs and presents them in a dropdown list.

The current implementation focuses on the development environment and the `CrouseServiceLoan` API.

### Objectives

- Provide a central location for API documentation.
- Automatically discover APIs without manually maintaining a list of OpenAPI specifications.
- Use Kubernetes metadata to register and configure APIs.
- Route requests through the existing APISIX Gateway API infrastructure.
- Manage all Kubernetes resources through GitOps and Argo CD.
- Keep application APIs independent from the central documentation interface.

## 2. Architecture

### Request flow

There are two distinct flows: loading documentation and executing API requests.

**Documentation discovery and loading**

1. An application exposes its OpenAPI JSON document.
2. The application's Kubernetes Service contains documentation discovery metadata.
3. The discovery controller watches eligible Services and builds an API catalog.
4. Swagger UI requests the generated Swagger configuration.
5. Swagger UI displays the discovered APIs in its dropdown.
6. Selecting an API loads its OpenAPI JSON document.

**Executing API requests**

1. A developer selects an API operation and clicks **Try it out**.
2. Swagger UI sends the request to the server URL declared in that API's OpenAPI document.
3. The request enters the existing external gateway path.
4. Cilium's shared gateway forwards external traffic to APISIX.
5. APISIX matches the HTTPRoute and forwards the request to the application Service.

### Logical architecture

```text
Developer's Browser
        |
        | HTTPS
        v
Cilium Shared Gateway
        |
        v
APISIX Gateway
        |
        +-- /swagger/*
        |       |
        |       +-- Swagger UI Service
        |       |
        |       +-- Discovery Controller
        |
        +-- /loan/*
                |
                v
        CrouseServiceLoan Service
                |
                v
        ASP.NET Core API
                |
                v
        OpenAPI JSON
```

The exact backend is selected by the APISIX HTTPRoute. The Swagger configuration endpoint is handled by the discovery controller, while the API specification and API operations are served through the application route.

## 3. Kubernetes components

### 3.1 Namespace: `api-docs-develop`

This namespace contains the central documentation components.

#### Swagger UI

Swagger UI is the web interface that renders OpenAPI specifications and lets developers explore API operations.

- Kubernetes Service: `swagger-ui`
- Service type: `ClusterIP`
- Service port: `8080`
- Container image: `repository.crouseco.com/docker-proxy/swaggerapi/swagger-ui:v5.17.14`

Relevant environment variables:

```yaml
env:
  - name: PORT
    value: "8080"

  - name: BASE_URL
    value: /swagger

  - name: CONFIG_URL
    value: /swagger/swagger-config.json
```

`BASE_URL` configures the path under which Swagger UI is served.

`CONFIG_URL` tells Swagger UI where to retrieve its API catalog.

A ClusterIP Service keeps the UI internal to the cluster. External access is provided through APISIX rather than by exposing a separate NodePort.

#### Discovery controller

The discovery controller is a small Flask application responsible for building the central API catalog.

- Kubernetes Service: `api-docs-discovery`
- Service type: `ClusterIP`
- Service port: `8081`
- Application health endpoint: `/healthz`
- Kubernetes ServiceAccount: `api-docs-discovery`
- Deployment scheduling: `zone=frontend`

The controller discovers eligible Services, reads their metadata, and generates the Swagger UI configuration dynamically.

Relevant configuration:

```yaml
env:
  - name: DOCS_ENVIRONMENT
    value: develop

  - name: DOCS_HOST
    value: api-develop.crouseco.com

  - name: ALLOWED_NAMESPACE_SUFFIX
    value: -develop

  - name: ENABLED_LABEL
    value: api-documentation.crouseco.com/enabled

  - name: DISPLAY_NAME_ANNOTATION
    value: api-documentation.crouseco.com/display-name

  - name: SPEC_URL_ANNOTATION
    value: api-documentation.crouseco.com/spec-url
```

The controller's source code must use these environment variables for them to have an effect. They define the intended discovery rules and metadata keys.

## 4. Dynamic API discovery

### 4.1 Why dynamic discovery?

A manually maintained Swagger configuration would require a developer to update a ConfigMap whenever a new API was added.

That approach creates duplicated configuration and increases the risk of stale documentation entries.

The discovery controller removes this manual registration step. An application team registers its API by adding the required metadata to its Kubernetes Service.

The controller watches eligible Services and builds the catalog from their metadata.

### 4.2 Discovery rules

The development controller is configured to discover Services in namespaces ending in `-develop`.

Each eligible Service must have the required label and annotations.

The controller uses these metadata keys:

| Metadata | Purpose |
|---|---|
| `api-documentation.crouseco.com/enabled` | Enables discovery when set to `"true"` |
| `api-documentation.crouseco.com/display-name` | Name displayed in Swagger UI |
| `api-documentation.crouseco.com/spec-url` | URL of the OpenAPI JSON document |

The metadata belongs on the **Kubernetes Service**, not merely on the application Deployment.

### 4.3 Registering an API

The following example shows the metadata for the Loan API.

Add it to the Service section of the application's Helm values:

```yaml
service:
  enabled: true
  type: ClusterIP

  additionalLabels:
    api-documentation.crouseco.com/enabled: "true"

  annotations:
    api-documentation.crouseco.com/display-name: "Loan API"
    api-documentation.crouseco.com/spec-url: "https://api-develop.crouseco.com/loan/swagger/v1/swagger.json"

  ports:
    - port: 8080
      name: http
      protocol: TCP
      targetPort: 8080
```

Retain any existing labels, annotations, and port settings required by the application.

The chart must render these values into the Kubernetes Service's `metadata.labels` and `metadata.annotations`. Verify the rendered result after deployment.

### 4.4 What happens when an API is registered?

1. Argo CD applies the updated application configuration.
2. Kubernetes updates the application's Service metadata.
3. The discovery controller observes the eligible Service.
4. The controller reads its display name and specification URL.
5. The API is added to the dynamically generated catalog.
6. Swagger UI displays the API in its dropdown.

No separate Swagger UI deployment is required for each API.

## 5. Swagger configuration endpoint

Swagger UI loads the configuration from:

`https://api-develop.crouseco.com/swagger/swagger-config.json`

The APISIX HTTPRoute directs this request to `api-docs-discovery`, which generates the JSON response.

The current confirmed response after registering the Loan API is:

```json
{
  "displayRequestDuration": true,
  "urls": [
    {
      "name": "Loan API",
      "url": "https://api-develop.crouseco.com/loan/swagger/v1/swagger.json"
    }
  ],
  "urls.primaryName": "Loan API"
}
```

### Configuration properties

| Property | Purpose |
|---|---|
| `displayRequestDuration` | Displays request execution duration in Swagger UI |
| `urls` | Lists the available OpenAPI specifications |
| `urls[].name` | API name displayed in the dropdown |
| `urls[].url` | URL from which Swagger UI loads the OpenAPI document |
| `urls.primaryName` | Selects the initial API in the dropdown |

This JSON is generated by the discovery controller. It is not the OpenAPI document itself.

The controller returns `Cache-Control: no-store` to discourage caching of the dynamic catalog. The configuration response also currently sets `Access-Control-Allow-Origin: *`; review whether this is necessary for the deployed routing and whether it matches the platform's security requirements.

## 6. APISIX routing

The existing APISIX Gateway remains the entry point for application traffic.

The central documentation implementation uses an HTTPRoute in the `api-docs-develop` namespace that attaches to the existing `apisix-develop-gateway` in the `apisix-develop` namespace.

### 6.1 HTTPRoute

The working routing configuration is:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: swagger-ui
  namespace: api-docs-develop
spec:
  parentRefs:
    - name: apisix-develop-gateway
      namespace: apisix-develop

  rules:
    # Swagger configuration is served by the discovery controller.
    - matches:
        - path:
            type: Exact
            value: /swagger/swagger-config.json
      backendRefs:
        - name: api-docs-discovery
          port: 8081

    # Swagger UI is served under /swagger.
    - matches:
        - path:
            type: PathPrefix
            value: /swagger
      backendRefs:
        - name: swagger-ui
          port: 8080
```

The exact configuration path is more specific than the `/swagger` prefix, so the configuration request is directed to the discovery controller.

**Important:** Do not add a URLRewrite filter to the Swagger UI route without checking the effects on `BASE_URL` and the configuration path. The no-rewrite version above is the known working configuration.

### 6.2 Loan API route

The existing Loan API HTTPRoute matches the `/loan` prefix and forwards requests to:

- Namespace: `crouseserviceloan-develop`
- Service: `crouseserviceloan`
- Service port: `8080`

The route strips the external `/loan` prefix before forwarding the request to the application.

For example:

```text
External request:
https://api-develop.crouseco.com/loan/Doc

APISIX forwards to the Loan API:
http://crouseserviceloan:8080/Doc
```

This is why the API's OpenAPI server URL must account for the external `/loan` prefix.

## 7. OpenAPI `servers` configuration

The central Swagger configuration specifies where to download an OpenAPI document. It does not specify the base URL used by **Try it out**.

That base URL comes from the selected API's OpenAPI document.

The intended development server URL for the Loan API is:

```json
"servers": [
  {
    "url": "https://api-develop.crouseco.com/loan",
    "description": "Development API through APISIX"
  }
]
```

This property belongs at the top level of the OpenAPI document, alongside `info` and `paths`.

For example:

```json
{
  "openapi": "3.0.1",
  "info": {
    "title": "CrouseServiceLoan API",
    "version": "Version1.2.0"
  },
  "servers": [
    {
      "url": "https://api-develop.crouseco.com/loan",
      "description": "Development API through APISIX"
    }
  ],
  "paths": {
    "/Doc": {
      "get": {}
    }
  }
}
```

The operation definition above is illustrative; retain the actual generated operation details in the application.

With this server URL, an operation at `/Doc` is called through `/loan/Doc`.

The `servers` value has to match the actual API route and operation paths. If the OpenAPI paths already include `/loan`, do not add the prefix twice.

### Where to configure it

For an ASP.NET Core application using Swashbuckle, the server can be configured in the Swagger generation pipeline using a document filter or another appropriate OpenAPI customization.

The configuration should be generated consistently by the application rather than manually editing the generated JSON, because generated JSON can be overwritten on the next request or deployment.

The central catalog currently loads the Loan API specification, and the API appears in the dropdown. The `servers` setting and successful end-to-end execution through **Try it out** still need to be verified separately.

## 8. GitOps and Argo CD

The documentation components are intended to be managed through the existing GitOps repository.

The workflow is:

1. Update the relevant Kubernetes manifests, Helm values, or application source code in Git.
2. Commit and push the changes.
3. Allow Argo CD to detect the repository change.
4. Synchronize the affected application.
5. Verify the resulting Kubernetes resources and application behavior.

The components managed through GitOps include:

- Swagger UI Deployment and Service.
- Discovery controller Deployment, Service, configuration, and ServiceAccount.
- HTTPRoute connecting the documentation endpoints to the APISIX Gateway.
- Application Service metadata used for discovery.

The discovery controller's image is built and published through the application's image delivery process. When controller source code changes, publish the updated image and update its deployed image reference through GitOps.

Avoid making permanent manual edits to live ConfigMaps or Services. Those changes should be represented in Git so that the repository remains the source of truth.

The precise repository directory structure and Argo CD Application names should be documented from the current repository manifests rather than inferred from resource names.

## 9. Verification and troubleshooting

### 9.1 Verify the API catalog

From a machine with access to the development endpoint:

```powershell
$catalog = Invoke-RestMethod `
  "https://api-develop.crouseco.com/swagger/swagger-config.json"

$catalog.urls | Format-Table name, url
```

Expected result: the Loan API appears in the list.

### 9.2 Verify the OpenAPI specification

```powershell
$spec = Invoke-RestMethod `
  "https://api-develop.crouseco.com/loan/swagger/v1/swagger.json"

$spec.info | Format-List title, version
$spec.servers | Format-Table url, description
```

Confirm that the specification is valid, the title is correct, and the `servers` URL points to the intended public API route.

If the server list is empty, inspect the application's OpenAPI generation configuration.

### 9.3 Verify the Kubernetes metadata

```bash
kubectl get svc crouseserviceloan \
  -n crouseserviceloan-develop \
  -o yaml
```

Check that the documentation label and both annotations are present on the Service.

### 9.4 Verify the central components

```bash
kubectl get pods,svc,httproute \
  -n api-docs-develop
```

Check that the Swagger UI and discovery controller Pods are healthy, the Services have endpoints, and the HTTPRoute is accepted and attached to the intended Gateway.

### 9.5 Troubleshooting table

| Symptom | What to check |
|---|---|
| API missing from the dropdown | Service label, required annotations, namespace suffix, controller logs |
| Swagger configuration returns 404 | Exact HTTPRoute path and discovery controller endpoint |
| Swagger UI does not load correctly | `BASE_URL`, `CONFIG_URL`, and avoid unintended URL rewrites |
| OpenAPI JSON returns 404 | `spec-url` annotation and Loan API HTTPRoute |
| Try it out calls the wrong URL | OpenAPI `servers` property and operation paths |
| Try it out returns 404 | APISIX path match, prefix rewrite, and application endpoint |
| Browser reports a CORS error | Browser Network/Console details, response headers, and whether requests are same-origin |
| Swagger cannot fetch the spec | Check HTTP status, TLS, spec URL, and browser error details |

## 10. Security and operational considerations

- Keep application Services internal unless external exposure is explicitly required.
- Expose the central documentation UI through the existing gateway rather than creating unnecessary NodePorts.
- Limit discovery to approved namespaces and explicitly enabled Services.
- Ensure only trusted application teams can add or modify the metadata that publishes APIs in the central catalog.
- Do not include credentials, tokens, or secrets in OpenAPI documents or the central configuration.
- Treat Swagger's **Try it out** feature as an API client: requests still need to satisfy the application's authentication and authorization requirements.
- Review CORS headers based on the actual browser origin and routing design.
- Apply all permanent changes through GitOps.

## 11. Current status

The following items have been established during implementation:

- [x] Central Swagger UI deployed in `api-docs-develop`.
- [x] Discovery controller deployed as a separate service.
- [x] Swagger UI loads its configuration through APISIX.
- [x] Dynamic API catalog returns the registered Loan API.
- [x] Loan API appears in the Swagger dropdown.
- [x] Loan API specification is referenced through the development hostname.
- [ ] Confirm the OpenAPI `servers` property is generated with the intended external API URL.
- [ ] Verify that Swagger's **Try it out** feature successfully executes requests through APISIX.
- [ ] Confirm the equivalent stage implementation and its environment-specific configuration, if it has been deployed.

## 12. Summary

The central documentation system separates three responsibilities:

1. **Swagger UI** presents API documentation and provides the interactive interface.
2. **The discovery controller** finds registered APIs and dynamically generates the catalog.
3. **APISIX** routes documentation and API requests through the existing gateway infrastructure.

Application teams register their APIs through Kubernetes Service metadata. The controller discovers those Services, Swagger UI loads the corresponding OpenAPI documents, and APISIX remains responsible for routing requests to the correct application.

This design avoids a manually maintained API list, supports GitOps-based operations, and provides a foundation for adding more APIs without deploying a separate Swagger UI for every service.
