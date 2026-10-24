# Helm Installation – Offline Environment

Helm is used as the Kubernetes package manager to install and manage applications such as Cilium.

Because the Kubernetes nodes do not have direct Internet access, Helm is downloaded on an Internet-connected Windows machine and then transferred to the Kubernetes control-plane node.

## 1. Download Helm

On an Internet-connected Windows machine, download:

```text
helm-v3.19.0-linux-amd64.tar.gz
```

Extract the archive until the Linux executable is available:

```text
linux-amd64/helm
```

## 2. Transfer Helm to the Kubernetes Node

Transfer the `helm` executable to the server.

Since `/usr/local/bin` may not be directly writable through the file-transfer tool, first copy it to:

```text
/tmp/helm
```

## 3. Move Helm to the System Path

On the Kubernetes control-plane node:

```bash
mv /tmp/helm /usr/local/bin/helm
```

Make the binary executable:

```bash
chmod +x /usr/local/bin/helm
```

## 4. Verify Installation

Check the Helm executable:

```bash
which helm
```

Expected:

```text
/usr/local/bin/helm
```

Verify the installed version:

```bash
helm version
```

## Installation Scope

Helm is a client-side Kubernetes administration tool. It does not need to run as a Kubernetes workload and does not need to be installed on worker nodes.

For this setup, Helm is installed on the control-plane administration node.

## Next Step

After Helm is installed and verified, configure the internal Nexus Helm repository and use it to install **Cilium**.
