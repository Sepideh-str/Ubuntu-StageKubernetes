
# Using Vault from a .NET Application on Kubernetes

This document describes a reusable pattern for a .NET application to read a secret from HashiCorp Vault. It covers the application code, Kubernetes ConfigMaps, Helm values, and the role of `envFrom`.

## 1. Overview

The application uses VaultSharp to retrieve a secret from Vault.

- **Local development:** authenticate with a Vault token.
- **Kubernetes:** authenticate with a Kubernetes ServiceAccount JWT and a Vault role.
- **ConfigMap:** store non-secret settings such as the Vault address, role, mount point, and secret path.
- **`envFrom`:** import ConfigMap values into the application container as environment variables.

Do not store Vault tokens or application secrets in a ConfigMap.

## 2. Define the ConfigMap in Helm values

The chart's `configMap.files` setting defines ConfigMaps. Each entry defines a separate ConfigMap; its key is used as the ConfigMap name suffix.

```yaml
configMap:
  enabled: true
  files:
    vault-config:
      Vault__Address: "https://vault.example.com"
      Vault__Role: "my-app-role"
      Vault__MountPoint: "my-kv-mount"
      Vault__SecretPath: "path/to/my/secret"
```

The names and structure above are example values. Use the Vault address, role, mount point, and secret path configured for your environment.

## 3. Reference the ConfigMap with `envFrom`

In this Helm chart, the `envFrom` values reference the ConfigMap:

```yaml
envFrom:
  vault-config:
    type: configmap
    nameSuffix: vault-config
```

This is chart-specific values syntax. The chart renders it into Kubernetes' standard container configuration:

```yaml
envFrom:
  - configMapRef:
      name: <actual-configmap-name>
```

`envFrom` is a built-in field in the Kubernetes container specification. It imports all key-value pairs from the referenced ConfigMap as environment variables.

## 4. Optional: use separate ConfigMaps

General application settings can be kept in a separate ConfigMap:

```yaml
configMap:
  enabled: true
  files:
    vault-config:
      Vault__Address: "https://vault.example.com"
      Vault__Role: "my-app-role"
      Vault__MountPoint: "my-kv-mount"
      Vault__SecretPath: "path/to/my/secret"

    app-config:
      ASPNETCORE_ENVIRONMENT: "Development"
      Logging__LogLevel__Default: "Information"

envFrom:
  vault-config:
    type: configmap
    nameSuffix: vault-config

  app-config:
    type: configmap
    nameSuffix: app-config
```

Keeping them separate is optional. It can make the purpose of each ConfigMap clearer and allow application settings to be maintained independently from Vault settings.

## 5. How .NET reads the configuration

The .NET configuration system maps double underscores (`__`) in environment variable names to colons (`:`).

| Environment variable | .NET configuration key |
|---|---|
| `Vault__Address` | `Vault:Address` |
| `Vault__Role` | `Vault:Role` |
| `Vault__MountPoint` | `Vault:MountPoint` |
| `Vault__SecretPath` | `Vault:SecretPath` |

The application can read these values through `IConfiguration`, for example:

```csharp
var vaultAddress = configuration["Vault:Address"];
var vaultRole = configuration["Vault:Role"];
```

## 6. VaultSharp service

The service below uses the Kubernetes ServiceAccount token when the token file exists. Otherwise, it uses a locally configured Vault token.

```csharp
using VaultSharp;
using VaultSharp.V1.AuthMethods;
using VaultSharp.V1.AuthMethods.Kubernetes;
using VaultSharp.V1.AuthMethods.Token;
using VaultSharp.V1.Commons;

public sealed class VaultSecretService
{
    private const string ServiceAccountTokenPath =
        "/var/run/secrets/kubernetes.io/serviceaccount/token";

    private readonly IVaultClient _client;
    private readonly IConfiguration _configuration;

    public VaultSecretService(IConfiguration configuration)
    {
        _configuration = configuration
            ?? throw new ArgumentNullException(nameof(configuration));

        var vaultAddress = GetRequiredConfiguration("Vault:Address");
        var authMethod = CreateAuthMethod();

        _client = new VaultClient(
            new VaultClientSettings(vaultAddress, authMethod));
    }

    public Task<Secret<SecretData<Dictionary<string, object>>>> ReadSecretAsync(
        string mountPoint,
        string secretPath)
    {
        ValidateRequired(mountPoint, nameof(mountPoint));
        ValidateRequired(secretPath, nameof(secretPath));

        return _client.V1.Secrets.KeyValue.V2
            .ReadSecretAsync<Dictionary<string, object>>(
                path: secretPath,
                mountPoint: mountPoint);
    }

    public async Task<string> GetSecretValueAsync(string fieldName)
    {
        ValidateRequired(fieldName, nameof(fieldName));

        var mountPoint = GetRequiredConfiguration("Vault:MountPoint");
        var secretPath = GetRequiredConfiguration("Vault:SecretPath");

        var secret = await ReadSecretAsync(mountPoint, secretPath);
        var data = secret?.Data?.Data
            ?? throw new InvalidOperationException(
                "Vault returned an empty secret.");

        if (!data.TryGetValue(fieldName, out var value) || value is null)
        {
            throw new InvalidOperationException(
                $"Vault secret field '{fieldName}' was not found.");
        }

        var secretValue = value.ToString();

        if (string.IsNullOrWhiteSpace(secretValue))
        {
            throw new InvalidOperationException(
                $"Vault secret field '{fieldName}' is empty.");
        }

        return secretValue;
    }

    private IAuthMethodInfo CreateAuthMethod()
    {
        if (!File.Exists(ServiceAccountTokenPath))
        {
            return new TokenAuthMethodInfo(
                GetRequiredConfiguration("Vault:Token"));
        }

        var serviceAccountJwt = File.ReadAllText(ServiceAccountTokenPath);

        if (string.IsNullOrWhiteSpace(serviceAccountJwt))
        {
            throw new InvalidOperationException(
                "Kubernetes service account JWT is empty.");
        }

        return new KubernetesAuthMethodInfo(
            GetRequiredConfiguration("Vault:Role"),
            serviceAccountJwt);
    }

    private string GetRequiredConfiguration(string key)
    {
        var value = _configuration[key];

        if (string.IsNullOrWhiteSpace(value))
        {
            throw new InvalidOperationException($"{key} is not configured.");
        }

        return value;
    }

    private static void ValidateRequired(string value, string parameterName)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new ArgumentException(
                "Value cannot be null, empty, or whitespace.",
                parameterName);
        }
    }
}
```

Register the service with dependency injection:

```csharp
builder.Services.AddSingleton<VaultSecretService>();
```

Then request a value by its field name in Vault:

```csharp
var secretValue =
    await vaultSecretService.GetSecretValueAsync("MySecretField");
```

Use the returned value where needed, and avoid logging it.

## 7. KV v2 mount point and secret path

Vault KV v2 API URLs use this format:

```text
/v1/<mount-point>/data/<secret-path>
```

When calling VaultSharp, provide the mount point and secret path separately:

- `mountPoint`: the KV v2 secrets engine mount.
- `secretPath`: the path within that mount.
- Do not include `/v1/` or the API's `/data/` segment in either value.

For example, if the actual Vault API endpoint is:

```text
/v1/my-kv-mount/data/team/my-app/config
```

then the configuration values are:

```yaml
Vault__MountPoint: "my-kv-mount"
Vault__SecretPath: "team/my-app/config"
```

Confirm the actual mount point and secret path with your Vault administrator.

## 8. Kubernetes requirements

For Kubernetes authentication to work:

1. The Pod must use the intended ServiceAccount.
2. The ServiceAccount JWT must be available at the token path used by the code.
3. The Vault Kubernetes auth role must be configured for that ServiceAccount and namespace.
4. The Vault policy must grant read access to the required KV v2 secret path.

## 9. Verify the rendered resources

After deploying the Helm release, inspect the Deployment and ConfigMap:

```bash
kubectl get deployment <deployment-name> -n <namespace> -o yaml
kubectl get configmap -n <namespace>
kubectl get configmap <configmap-name> -n <namespace> -o yaml
```

Confirm that the Deployment's container `envFrom` references the generated ConfigMap name and that the ConfigMap contains only non-secret settings.
