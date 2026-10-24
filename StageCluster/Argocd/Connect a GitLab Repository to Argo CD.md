# Connect a GitLab Repository to Argo CD

## 1. Repository

The GitLab repository I connected to Argo CD was:

```text
https://git.crouseco.com/software/k8s/helm.git
```

## 2. Argo CD Repository Configuration

In Argo CD:

**Settings → Repositories → Connect Repo**

I selected:

```text
Connection Method: HTTPS
```

Then I entered:

```text
Repository URL:
https://git.crouseco.com/software/k8s/helm.git
```

For authentication, I used:

```text
Username:
OAuth2

Password:
<GitLab Access Token>
```

I also enabled:

```text
Skip server verification: ✓
```

## 3. Final Configuration

The configuration that worked was:

```text
Repository URL:
https://git.crouseco.com/software/k8s/helm.git

Connection:
HTTPS

Username:
OAuth2

Password:
GitLab Access Token

Skip server verification:
Enabled
```

I then selected **Connect** / **Test Connection**.

The repository connection succeeded.

## 4. Authentication Flow

```text
Argo CD
   |
   | HTTPS
   | Username: OAuth2
   | Password: GitLab Access Token
   | Skip server verification
   |
   v
GitLab
   |
   v
software/k8s/helm.git
```

## 5. Important Notes

### Username

The username was set to:

```text
OAuth2
```

### Password

The password field contains the **GitLab Access Token**, not the normal GitLab password.

### Skip Server Verification

I enabled **Skip server verification** because of the TLS/certificate configuration of the internal GitLab server.

This means Argo CD does not verify the GitLab server certificate when establishing the HTTPS connection.

> **Security note:** Skipping server verification reduces TLS security because Argo CD does not validate the server certificate. A better long-term solution is to configure Argo CD with the internal GitLab CA certificate and leave server verification enabled.

## 6. Working Configuration Summary

```text
┌─────────────────────────────────────────────┐
│              Argo CD Repository             │
├─────────────────────────────────────────────┤
│ URL:                                        │
│ https://git.crouseco.com/software/k8s/      │
│ helm.git                                    │
│                                             │
│ Connection: HTTPS                           │
│                                             │
│ Username: OAuth2                            │
│                                             │
│ Password: GitLab Access Token               │
│                                             │
│ Skip server verification: Enabled           │
└─────────────────────────────────────────────┘
```

This configuration successfully connected Argo CD to the private GitLab repository.
