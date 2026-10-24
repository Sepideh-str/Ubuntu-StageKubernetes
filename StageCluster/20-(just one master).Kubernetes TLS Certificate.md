# Kubernetes TLS Certificate

## 1. Certificate Files

The TLS certificate and private key are available on the Kubernetes node:

```text
/tmp/public.crt
/tmp/private.key
```

The certificate includes the following SANs:

```text
crouseco.com
crouse.ir
crsap.ir
*.crouseco.com
*.crouse.ir
*.crsap.ir
```

## 2. Create Gateway Namespace

```bash
kubectl create namespace gateway-system
```

If the namespace already exists:

```text
Error from server (AlreadyExists): namespaces "gateway-system" already exists
```

No action is required.

## 3. Create Kubernetes TLS Secret

Create the TLS Secret:

```bash
kubectl create secret tls crouseco-wildcard-tls \
  --cert=/tmp/public.crt \
  --key=/tmp/private.key \
  -n gateway-system
```

## 4. Verify the Secret

```bash
kubectl get secret -n gateway-system
```

Expected:

```text
NAME                    TYPE                DATA
crouseco-wildcard-tls   kubernetes.io/tls   2
```

The Secret is used by the Cilium Gateway to terminate HTTPS traffic for:

```text
gitops-stage.crouseco.com
```

## 5. Important Notes

* The Kubernetes Secret must contain both `tls.crt` and `tls.key`.
* The Secret is created in the `gateway-system` namespace.
* The Gateway references this Secret through `certificateRefs`.
* The certificate private key should not be committed to Git.
* The certificate files under `/tmp` are only used during Secret creation.
