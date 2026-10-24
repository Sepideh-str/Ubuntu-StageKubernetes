# Kubernetes Control Plane – Joining Additional Master Nodes

## Overview

The initial control-plane node was created with `kubeadm init`.

Additional control-plane nodes were joined using the Kubernetes HA endpoint:

```text
172.25.3.199:7443
```

Traffic to this endpoint is handled by HAProxy and distributed to the three control-plane nodes on TCP `6443`.

---

## Generate Join Credentials

On the initial control-plane node:

```bash
kubeadm init phase upload-certs --upload-certs
```

This uploads the control-plane certificates and generates a certificate key.

Generate a new bootstrap token:

```bash
kubeadm token create --print-join-command
```

The output provides the base join command:

```bash
kubeadm join <CONTROL_PLANE_ENDPOINT> \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<CA_HASH>
```

For an additional control-plane node, add:

```bash
--control-plane \
--certificate-key <CERTIFICATE_KEY>
```

---

## Join Additional Control-Plane Nodes

Run the complete command on each additional master:

```bash
kubeadm join <CONTROL_PLANE_ENDPOINT> \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<CA_HASH> \
  --control-plane \
  --certificate-key <CERTIFICATE_KEY>
```

The command was executed on:

* Master-F2
* Master-F3

Both nodes joined successfully.

---

## Verify Control Plane

From any configured Kubernetes administration host:

```bash
kubectl get nodes -o wide
```

Expected result:

```text
NAME             STATUS   ROLES           VERSION
stage-masterf1   Ready    control-plane   v1.36.4
stage-masterf2   Ready    control-plane   v1.36.4
stage-masterf3   Ready    control-plane   v1.36.4
```

Verify control-plane components:

```bash
kubectl get pods -n kube-system -o wide
```

The following components should be running on all three control-plane nodes:

* etcd
* kube-apiserver
* kube-controller-manager
* kube-scheduler
* kube-proxy
* Cilium

CoreDNS and Cilium Operator should also be healthy.

---

## Notes

* Generate a fresh certificate key when adding control-plane nodes if the previous key has expired.
* Join commands contain temporary credentials and should not be stored in public documentation.
* The control-plane endpoint is the HA VIP, not an individual master IP.
