## Create Harbor Image Pull Secret

Kubernetes needs credentials to pull private container images from the internal Harbor registry.

For the `stage` environment, a Docker registry secret named `harbor-secret` is created in the `stage` namespace.

### 1. Create the Harbor Secret

Run the following command from a Kubernetes control-plane node:

```bash
kubectl create secret docker-registry harbor-secret \
  --docker-server=harbor.crouseco.com \
  --docker-username=sre \
  --docker-password='<HARBOR_PASSWORD>' \
  --docker-email='<EMAIL_ADDRESS>' \
  -n stage
```

Example:

```bash
kubectl create secret docker-registry harbor-secret \
  --docker-server=harbor.crouseco.com \
  --docker-username=sre \
  --docker-password='<HARBOR_PASSWORD>' \
  --docker-email='<EMAIL_ADDRESS>' \
  -n stage
```

Expected result:

```text
secret/harbor-secret created
```

### 2. Verify the Secret

Check that the secret exists in the `stage` namespace:

```bash
kubectl get secret harbor-secret -n stage
```

Expected output will be similar to:

```text
NAME             TYPE                             DATA   AGE
harbor-secret    kubernetes.io/dockerconfigjson   1      ...
```

The important values are:

* **Name:** `harbor-secret`
* **Namespace:** `stage`
* **Type:** `kubernetes.io/dockerconfigjson`

### 3. Why the Secret Is Required

The application image is stored in the private Harbor registry:

```text
harbor.crouseco.com
```

For example:

```text
harbor.crouseco.com/hr-webapp/crousewebapploan:<VERSION>
```

Kubernetes cannot pull a private image without valid registry credentials.

The `harbor-secret` contains the authentication information required by the Kubernetes nodes to pull the image.

### 4. Namespace Is Important

The secret must exist in the **same namespace as the workload**.

For the Stage environment:

```text
Namespace: stage
Secret:    harbor-secret
```

For example:

```bash
kubectl get secret harbor-secret -n stage
```

A secret created in another namespace cannot be directly used by a Pod in `stage`.

### 5. Using the Secret from a Deployment

The application's Deployment should reference the secret through `imagePullSecrets`:

```yaml
spec:
  template:
    spec:
      imagePullSecrets:
        - name: harbor-secret
```

This tells Kubernetes to use `harbor-secret` when pulling private container images.

### 6. Verify the Deployment Configuration

You can verify that the Deployment references the secret:

```bash
kubectl get deployment <DEPLOYMENT_NAME> -n stage \
  -o jsonpath='{.spec.template.spec.imagePullSecrets}'
```

You should see:

```text
[{"name":"harbor-secret"}]
```

### 7. Troubleshooting Image Pull Errors

If the secret is missing or the credentials are incorrect, Pods may show errors such as:

```text
ErrImagePull
```

or:

```text
ImagePullBackOff
```

Check the Pod events:

```bash
kubectl describe pod <POD_NAME> -n stage
```

Look for messages such as:

```text
Failed to pull image
```

or:

```text
no basic auth credentials
```

If the secret was created after the Pod entered `ImagePullBackOff`, delete the affected Pod so that Kubernetes creates a new Pod and retries the image pull:

```bash
kubectl delete pod <POD_NAME> -n stage
```

The Deployment will automatically create a replacement Pod.

### 8. Security Note

Do not store the Harbor password directly in Git repositories, Helm values files, or other publicly accessible configuration files.

When documenting the procedure, use a placeholder:

```text
<HARBOR_PASSWORD>
```

instead of storing the actual password in the documentation.

The secret itself is stored in Kubernetes as a `kubernetes.io/dockerconfigjson` Secret.
