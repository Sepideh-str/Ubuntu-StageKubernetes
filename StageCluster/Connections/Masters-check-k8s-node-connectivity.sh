#!/bin/bash

# ============================================================
# Kubernetes Master Connectivity Check
#
# Run this script on each Kubernetes master.
# It checks the network connectivity required by:
#   - Cilium
#   - Kubernetes control plane
#   - Kubelet
#   - Infrastructure repositories/services
# ============================================================

NODES=(
    "stage-masterf1 172.25.3.194"
    "stage-masterf2 172.25.3.195"
    "stage-masterf3 172.25.3.196"
    "stage-workerf1 172.25.3.197"
    "stage-workerf2 172.25.3.198"
    "stage-workerb1 172.25.9.114"
    "stage-workerb2 172.25.9.115"
    "stage-workerd1 172.25.25.18"
    "stage-workerd2 172.25.25.19"
)

MASTERS=(
    "stage-masterf1 172.25.3.194"
    "stage-masterf2 172.25.3.195"
    "stage-masterf3 172.25.3.196"
)

WORKERS=(
    "stage-workerf1 172.25.3.197"
    "stage-workerf2 172.25.3.198"
    "stage-workerb1 172.25.9.114"
    "stage-workerb2 172.25.9.115"
    "stage-workerd1 172.25.25.18"
    "stage-workerd2 172.25.25.19"
)

INFRA=(
    "repository.crouseco.com 172.25.9.82"
    "git.crouseco.com 172.25.2.242"
    "harbor.crouseco.com 172.25.2.243"
)

# Kubernetes API endpoint / VIP
K8S_API_IP="172.25.3.199"
K8S_API_PORT="7443"

# Change this if your DNS server is different
DNS_SERVER="172.25.3.1"


LOCAL_IP=$(hostname -I | awk '{print $1}')


# ============================================================
# Helper functions
# ============================================================

check_tcp()
{
    NAME="$1"
    IP="$2"
    PORT="$3"

    if timeout 3 bash -c "</dev/tcp/$IP/$PORT" 2>/dev/null; then
        printf "%-25s %-16s TCP/%-5s OK\n" "$NAME" "$IP" "$PORT"
    else
        printf "%-25s %-16s TCP/%-5s FAILED\n" "$NAME" "$IP" "$PORT"
    fi
}


# ============================================================
# Header
# ============================================================

echo
echo "============================================================"
echo " Kubernetes Master Connectivity Check"
echo "============================================================"
echo "Hostname : $(hostname)"
echo "Local IP : $LOCAL_IP"
echo "============================================================"
echo


# ============================================================
# 1. Cilium Health - TCP 4240
# ============================================================

echo "TCP 4240 - Cilium Health"
echo "------------------------------------------------------------"

for ENTRY in "${NODES[@]}"; do

    NAME=$(echo "$ENTRY" | awk '{print $1}')
    IP=$(echo "$ENTRY" | awk '{print $2}')

    if [[ "$IP" == "$LOCAL_IP" ]]; then
        printf "%-25s %-16s TCP/4240  LOCAL\n" "$NAME" "$IP"
        continue
    fi

    check_tcp "$NAME" "$IP" "4240"

done

echo


# ============================================================
# 2. Cilium Geneve - UDP 6081
# ============================================================

echo "UDP 6081 - Cilium Geneve"
echo "------------------------------------------------------------"

for ENTRY in "${NODES[@]}"; do

    NAME=$(echo "$ENTRY" | awk '{print $1}')
    IP=$(echo "$ENTRY" | awk '{print $2}')

    if [[ "$IP" == "$LOCAL_IP" ]]; then
        printf "%-25s %-16s UDP/6081  LOCAL\n" "$NAME" "$IP"
        continue
    fi

    # UDP does not provide a real connection handshake.
    # This only verifies that the local host can send a UDP packet.
    if timeout 3 bash -c "</dev/udp/$IP/6081" 2>/dev/null; then
        printf "%-25s %-16s UDP/6081  SENT\n" "$NAME" "$IP"
    else
        printf "%-25s %-16s UDP/6081  FAILED\n" "$NAME" "$IP"
    fi

done

echo


# ============================================================
# 3. Kubernetes API - TCP 6443
# ============================================================

echo "TCP 6443 - Kubernetes API (Control Plane)"
echo "------------------------------------------------------------"

for ENTRY in "${MASTERS[@]}"; do

    NAME=$(echo "$ENTRY" | awk '{print $1}')
    IP=$(echo "$ENTRY" | awk '{print $2}')

    if [[ "$IP" == "$LOCAL_IP" ]]; then
        printf "%-25s %-16s TCP/6443  LOCAL\n" "$NAME" "$IP"
        continue
    fi

    check_tcp "$NAME" "$IP" "6443"

done

echo


# ============================================================
# 4. Kubernetes API Endpoint - TCP 7443
# ============================================================

echo "TCP 7443 - Kubernetes API Endpoint"
echo "------------------------------------------------------------"

check_tcp "kubernetes-api-vip" "$K8S_API_IP" "$K8S_API_PORT"

echo


# ============================================================
# 5. Kubelet - TCP 10250
# ============================================================

echo "TCP 10250 - Kubelet"
echo "------------------------------------------------------------"

for ENTRY in "${WORKERS[@]}"; do

    NAME=$(echo "$ENTRY" | awk '{print $1}')
    IP=$(echo "$ENTRY" | awk '{print $2}')

    check_tcp "$NAME" "$IP" "10250"

done

echo


# ============================================================
# 6. Infrastructure - TCP 443
# ============================================================

echo "TCP 443 - Infrastructure Services"
echo "------------------------------------------------------------"

for ENTRY in "${INFRA[@]}"; do

    NAME=$(echo "$ENTRY" | awk '{print $1}')
    IP=$(echo "$ENTRY" | awk '{print $2}')

    check_tcp "$NAME" "$IP" "443"

done

echo


# ============================================================
# 7. DNS - UDP 53
# ============================================================

echo "UDP 53 - DNS"
echo "------------------------------------------------------------"

if command -v dig >/dev/null 2>&1; then

    if timeout 3 dig @"$DNS_SERVER" kubernetes.default.svc.cluster.local A +short >/dev/null 2>&1; then
        printf "%-25s %-16s UDP/53    OK\n" "DNS" "$DNS_SERVER"
    else
        printf "%-25s %-16s UDP/53    FAILED\n" "DNS" "$DNS_SERVER"
    fi

else

    echo "dig is not installed - DNS check skipped."

fi

echo


# ============================================================
# Summary
# ============================================================

echo "============================================================"
echo " Check completed."
echo "============================================================"
