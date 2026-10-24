#!/bin/bash

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

INFRA=(
    "repository.crouseco.com 172.25.9.82"
    "git.crouseco.com 172.25.2.242"
    "harbor.crouseco.com 172.25.2.243"
)

LOCAL_IP=$(hostname -I | awk '{print $1}')

echo
echo "============================================================"
echo " Kubernetes Node Connectivity Check"
echo "============================================================"
echo "Hostname : $(hostname)"
echo "Local IP : $LOCAL_IP"
echo "============================================================"

echo
echo "TCP 4240 - Cilium Health"
echo "------------------------------------------------------------"

for ENTRY in "${NODES[@]}"; do
    NAME=$(echo "$ENTRY" | awk '{print $1}')
    IP=$(echo "$ENTRY" | awk '{print $2}')

    if [[ "$IP" == "$LOCAL_IP" ]]; then
        printf "%-20s %-16s TCP/4240  LOCAL\n" "$NAME" "$IP"
        continue
    fi

    if timeout 3 bash -c "</dev/tcp/$IP/4240" 2>/dev/null; then
        printf "%-20s %-16s TCP/4240  OK\n" "$NAME" "$IP"
    else
        printf "%-20s %-16s TCP/4240  FAILED\n" "$NAME" "$IP"
    fi
done

echo
echo "UDP 6081 - Cilium Geneve"
echo "------------------------------------------------------------"

for ENTRY in "${NODES[@]}"; do
    NAME=$(echo "$ENTRY" | awk '{print $1}')
    IP=$(echo "$ENTRY" | awk '{print $2}')

    if [[ "$IP" == "$LOCAL_IP" ]]; then
        printf "%-20s %-16s UDP/6081  LOCAL\n" "$NAME" "$IP"
        continue
    fi

    if timeout 3 bash -c "</dev/udp/$IP/6081" 2>/dev/null; then
        printf "%-20s %-16s UDP/6081  SENT\n" "$NAME" "$IP"
    else
        printf "%-20s %-16s UDP/6081  FAILED\n" "$NAME" "$IP"
    fi
done

echo
echo "TCP 443 - Infrastructure"
echo "------------------------------------------------------------"

for ENTRY in "${INFRA[@]}"; do
    NAME=$(echo "$ENTRY" | awk '{print $1}')
    IP=$(echo "$ENTRY" | awk '{print $2}')

    if timeout 3 bash -c "</dev/tcp/$IP/443" 2>/dev/null; then
        printf "%-25s %-16s TCP/443   OK\n" "$NAME" "$IP"
    else
        printf "%-25s %-16s TCP/443   FAILED\n" "$NAME" "$IP"
    fi
done

echo
echo "============================================================"
echo "Check completed."
echo "============================================================"
echo