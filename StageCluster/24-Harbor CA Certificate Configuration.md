# Harbor CA Certificate Configuration on Kubernetes Nodes

## 1. Purpose

This document describes how to configure Ubuntu Kubernetes nodes to trust the internal Harbor registry:

```text
https://harbor.crouseco.com
```

The Harbor server uses the internal `CrouseCA` certificate authority.

The CA certificate must be installed on the Kubernetes nodes so that the nodes can establish a trusted HTTPS connection to Harbor.

> Harbor itself is **not** installed on the Kubernetes nodes. Only the Harbor CA certificate is installed.

---

## 2. Environment

Harbor:

```text
harbor.crouseco.com
```

Harbor CA certificate:

```text
CrouseHarborCA.crt
```

Operating system:

```text
Ubuntu
```

Container runtime:

```text
containerd
```

---

## 3. Copy the Harbor CA Certificate

On **each Kubernetes node**, copy the Harbor CA certificate into Ubuntu's local CA directory:

```bash
cp /home/user/CrouseHarborCA.crt \
  /usr/local/share/ca-certificates/CrouseHarborCA.crt
```

The certificate is installed under:

```text
/usr/local/share/ca-certificates/
```

This is the appropriate location for locally trusted CA certificates on Ubuntu.

---

## 4. Update the Ubuntu CA Store

After copying the certificate, run:

```bash
update-ca-certificates
```

A successful result should indicate that the certificate was added:

```text
1 added, 0 removed; done.
```

Ubuntu updates its system certificate store under:

```text
/etc/ssl/certs/
```

---

## 5. Test Harbor HTTPS Connection

Test the connection to Harbor:

```bash
curl https://harbor.crouseco.com
```

A successful result should return the Harbor web interface HTML, for example:

```html
<!DOCTYPE html>
<html>
    <head>
        <meta charset="utf-8"/>
        <title>Harbor</title>
```

The important point is that the command succeeds **without** using the `-k` option.

Do not use:

```bash
curl -k https://harbor.crouseco.com
```

for this verification because `-k` disables TLS certificate verification.

A successful `curl` test confirms that the node can:

* Resolve `harbor.crouseco.com`
* Connect to Harbor over HTTPS
* Trust the Harbor CA certificate
* Validate the Harbor TLS certificate
* Receive a response from Harbor

---

## 6. Restart containerd

After updating the CA certificates, restart `containerd`:

```bash
systemctl restart containerd
```

Check the service:

```bash
systemctl status containerd
```

The expected state is:

```text
Active: active (running)
```

---

## 7. Repeat on All Kubernetes Nodes

The CA certificate configuration must be performed on **all Kubernetes nodes that may run workloads which pull images from Harbor**.

For each node, perform:

```bash
cp /home/user/CrouseHarborCA.crt \
  /usr/local/share/ca-certificates/CrouseHarborCA.crt

update-ca-certificates

curl https://harbor.crouseco.com

systemctl restart containerd

systemctl status containerd
```

Each node should successfully return the Harbor page from:

```bash
curl https://harbor.crouseco.com
```

---

## 8. Why This Configuration Is Required

When Kubernetes needs to start a Pod that uses an image stored in Harbor, the container runtime on the node pulls the image.

The basic flow is:

```text
Kubernetes Pod
      |
      v
   containerd
      |
      | HTTPS
      v
harbor.crouseco.com
      |
      v
Container Image
```

Because Harbor uses an internal CA, the Ubuntu node must trust:

```text
CrouseCA
```

Installing:

```text
CrouseHarborCA.crt
```

allows the node to validate Harbor's TLS certificate.

---

## 9. Important Distinction

This configuration is **node-level configuration**.

It is separate from the Kubernetes Harbor authentication Secret.

### Harbor CA

Installed on each relevant node:

```text
CrouseHarborCA.crt
        |
        v
Ubuntu CA Store
        |
        v
containerd trusts Harbor
```

### Harbor Authentication

Configured later in Kubernetes:

```text
harbor-secret
        |
        v
Kubernetes ServiceAccount
        |
        v
Pod
        |
        v
Authentication to Harbor
```

The CA certificate provides **TLS trust**.

The Harbor Secret provides **authentication credentials**.

---

## 10. Final Verification

After completing the configuration on all relevant nodes, verify:

```bash
curl https://harbor.crouseco.com
```

and:

```bash
systemctl status containerd
```

Expected result:

```text
Harbor HTTPS request: successful
containerd: active (running)
```

At this point, the Kubernetes nodes are configured to trust the Harbor registry.

The next configuration step is to create the Kubernetes `harbor-secret` for authenticated image pulls from private Harbor repositories.
