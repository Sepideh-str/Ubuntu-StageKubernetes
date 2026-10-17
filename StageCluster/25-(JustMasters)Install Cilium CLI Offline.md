# Install Cilium CLI Offline

This section documents how to install the **Cilium CLI** on Kubernetes nodes in an offline environment.

The Kubernetes cluster is using:

```text
Kubernetes: v1.36.4
Cilium:     v1.20.2
```

The Cilium CLI used for troubleshooting is:

```text
Cilium CLI: v0.20.1
```

The CLI is installed manually because the Kubernetes environment does not have direct Internet access.

---

## 1. Download the Cilium CLI

The Cilium CLI is downloaded from the official Cilium GitHub releases page:

https://github.com/cilium/cilium-cli/releases

For Linux AMD64, download:

```text
cilium-linux-amd64.tar.gz
```

The download is performed from an **Internet-connected machine**.

The official release page is:

https://github.com/cilium/cilium-cli/releases

---

## 2. Transfer the CLI to the Offline Environment

After downloading the archive, transfer it to the Kubernetes node.

For example:

```text
/home/user/cilium-linux-amd64.tar.gz
```

The file can be transferred using SCP or another approved file-transfer method.

Example:

```bash
scp cilium-linux-amd64.tar.gz root@172.25.3.194:/home/user/
```

In this example:

```text
172.25.3.194
```

is `Stage-MasterF1`.

---

## 3. Extract the Cilium CLI

On the Kubernetes node:

```bash
cd /home/user
tar -xzf cilium-linux-amd64.tar.gz
```

This extracts:

```text
/home/user/cilium
```

---

## 4. Install the Cilium CLI

Install the binary into `/usr/local/bin`:

```bash
install -m 0755 /home/user/cilium /usr/local/bin/cilium
```

This makes the CLI available system-wide.

---

## 5. Verify the Installation

Run:

```bash
cilium version
```

Expected output:

```text
cilium-cli: v0.20.1 compiled with go1.27.1 on linux/amd64
cilium image (default): v1.20.1
```

The CLI is now available as:

```bash
cilium
```

---

## 6. Install on Additional Nodes

The same CLI can be installed on additional Kubernetes nodes when required for troubleshooting.

For example, on `Stage-MasterF2`:

```bash
cd /home/user
tar -xzf cilium-linux-amd64.tar.gz
install -m 0755 /home/user/cilium /usr/local/bin/cilium
cilium version
```

The same procedure can be used on other nodes.

---

## 7. Verify Cilium Cluster Status

After installing the CLI, check the cluster:

```bash
cilium status
```

This provides information about:

* Cilium agent status
* Cilium health
* Kubernetes connectivity
* Cilium version
* Cilium operator status

---

## 8. CLI and Cilium Agent Versions

The Cilium CLI version and Cilium agent version are separate.

Current environment:

```text
Cilium CLI:
v0.20.1

Cilium Agent:
v1.20.2
```

Installing the CLI does **not** install, upgrade, or modify the Cilium agents running in Kubernetes.

The CLI is used for Cilium administration and troubleshooting.
