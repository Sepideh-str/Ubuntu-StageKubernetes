# Kubernetes Cluster Initialization

At this point, the host preparation and control-plane HA infrastructure are ready. The next step is to create the Kubernetes cluster using `kubeadm`.

## 1. Create the kubeadm Configuration

Create the cluster configuration:

```bash
vi /root/kubeadm-config.yaml
```

Use the following configuration:

```yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration

kubernetesVersion: v1.36.4

controlPlaneEndpoint: "172.25.3.199:7443"

imageRepository: repository.crouseco.com/k8s-proxy

networking:
  podSubnet: "10.244.0.0/16"

dns:
  imageRepository: repository.crouseco.com/k8s-proxy/coredns
```

### Configuration Overview

| Setting                | Purpose                                         |
| ---------------------- | ----------------------------------------------- |
| `kubernetesVersion`    | Kubernetes version used by the cluster          |
| `controlPlaneEndpoint` | Stable HA endpoint for the Kubernetes API       |
| `imageRepository`      | Internal Nexus repository for Kubernetes images |
| `podSubnet`            | CIDR allocated for Kubernetes Pods              |
| `dns.imageRepository`  | Internal Nexus repository for CoreDNS           |

The `controlPlaneEndpoint` points to the HA VIP and HAProxy frontend:

```text
172.25.3.199:7443
        |
      HAProxy
        |
   Control Planes :6443
```

## 2. Validate the Configuration

After creating the configuration, validate it before using it:

```bash
kubeadm config validate --config /root/kubeadm-config.yaml
```

Expected output:

```text
ok
```

## 3. Verify Required Images

List the images that kubeadm will use:

```bash
kubeadm config images list \
  --config /root/kubeadm-config.yaml
```

All images should resolve through the internal Nexus repository.

Pull the images before initializing the cluster:

```bash
kubeadm config images pull \
  --config /root/kubeadm-config.yaml
```

This verifies that the required Kubernetes images are available from Nexus before cluster initialization.

## 4. Initialize the First Control Plane

Run the following on the first control-plane node:

```bash
kubeadm init \
  --config /root/kubeadm-config.yaml \
  --upload-certs
```

The `--upload-certs` option allows the additional control-plane nodes to retrieve the required control-plane certificates when joining the cluster.

After successful initialization, kubeadm provides separate `kubeadm join` commands for:

* Additional control-plane nodes
* Worker nodes


