# HashiCorp Vault Integration Strategy

## 1. Purpose

HashiCorp Vault will be used as the centralized system for managing sensitive application data, including database connection strings, passwords, API keys, and credentials.

Our goal is to retrieve secrets securely at runtime without hardcoding them in source code or storing them unnecessarily in application configuration.

## 2. Selected Approach: Direct SDK Integration

We prefer direct application integration using an SDK, such as **VaultSharp for .NET applications**.

The application communicates directly with Vault, authenticates, retrieves authorized secrets, and uses them at runtime.

### Why this approach?

- **Reduced secret exposure:** Secrets do not need to be stored in Kubernetes Secret objects, environment variables, or files for the application to consume them.
- **Local development:** Developers can retrieve development secrets from their workstations.
- **Kubernetes support:** Applications can retrieve environment-specific secrets while running in Kubernetes.
- **Access control:** Vault policies restrict which secrets each identity can access.
- **Application awareness:** Developers explicitly manage how their applications retrieve and use secrets.

## 3. Integration Options

- **Vault Secrets Operator:** Synchronizes Vault secrets into Kubernetes Secret resources.
- **Vault Agent:** Handles supported authentication workflows and can deliver secrets through files or templates.
- **Direct SDK integration:** Allows applications to retrieve secrets directly from Vault into application memory.

We prefer SDK integration to reduce the need to materialize secrets in Kubernetes resources or files. This reduces certain exposure risks but does not eliminate them; secrets still exist in application memory while being used.

## 4. Authentication and Environment Separation

| Environment | Authentication | Access |
|---|---|---|
| Local development | Developer authentication or development token | Development secrets only |
| Development in Kubernetes | Kubernetes auth | Development secrets only |
| Stage in Kubernetes | Kubernetes auth | Stage secrets only |
| Production in Kubernetes | Kubernetes auth | Production secrets only |

Developers must not use their personal tokens in deployed applications. Each workload should use an appropriate identity, with separate Vault roles and least-privilege policies.

Company SSO can be integrated with Vault for developer access if supported by the company's identity provider and configured by the platform team.

## 5. Security Requirements

- Use TLS for communication with Vault.
- Never hardcode or commit secrets to Git.
- Protect Vault tokens and avoid shared, long-lived credentials.
- Prevent secrets from appearing in logs or diagnostic output.
- Handle authentication failures, token expiration, and secret rotation.
- Restrict access to Kubernetes workloads, Vault, and worker nodes.
- Audit secret access and apply least-privilege policies.

## 6. Implementation Roadmap

1. Configure Vault, authentication methods, secret engines, and policies.
2. Establish secure local developer access.
3. Test reading a development secret.
4. Integrate VaultSharp into a .NET application.
5. Configure Kubernetes authentication and workload-specific Vault roles.
6. Test development, stage, and production access boundaries.
7. Implement monitoring, auditing, and credential rotation procedures.

## 7. Conclusion

Our preferred strategy is **direct SDK integration with HashiCorp Vault**, using VaultSharp for .NET applications.

This approach supports local development and Kubernetes deployments while keeping identities and permissions separate across environments. Vault remains responsible for authorization, and applications retrieve only the secrets they are permitted to access.

Security depends on correct authentication, Vault policies, token lifecycle management, TLS, and protection of the application runtime.