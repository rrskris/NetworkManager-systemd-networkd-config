#!/bin/bash
# ---------------------------------------------------------------------
# Author: Vamshi Krishna Santhapuri
# Script: eks-production-ami-prep.sh
# Objective: Migrate to systemd-networkd, fix stale DNS & disable Stub
# ---------------------------------------------------------------------

set -euo pipefail

log() { echo -e "\n[$(date +'%Y-%m-%dT%H:%M:%S')] $1"; }

log "Starting production network stack migration..."

# 1. Identify Primary Interface
PRIMARY_IF=$(ip route | grep default | awk '{print $5}' | head -n1)
[ -z "$PRIMARY_IF" ] && PRIMARY_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|en)' | head -n1)

if [ -z "$PRIMARY_IF" ]; then
    echo "[ERROR] No primary interface detected."
    exit 1
fi
log "Targeting interface: $PRIMARY_IF"

# 2. Lock Cloud-Init Network Config
log "Step 1: Disabling cloud-init network management..."
sudo mkdir -p /etc/cloud/cloud.cfg.d/
echo "network: {config: disabled}" | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

# 3. Deploy systemd-networkd Config
log "Step 2: Configuring systemd-networkd..."
sudo mkdir -p /etc/systemd/network/
cat <<EOF | sudo tee /etc/systemd/network/10-$PRIMARY_IF.network
[Match]
Name=$PRIMARY_IF

[Network]
DHCP=ipv4
LinkLocalAddressing=yes
IPv6AcceptRA=no

[DHCPv4]
ClientIdentifier=mac
RouteMetric=100
UseMTU=true
EOF

# 4. Disable DNS Stub for EKS/CoreDNS compatibility
log "Step 3: Disabling systemd-resolved stub listener..."
sudo mkdir -p /etc/systemd/resolved.conf.d/
cat <<EOF | sudo tee /etc/systemd/resolved.conf.d/99-eks-dns.conf
[Resolve]
DNSStubListener=no
EOF

# 5. Destroy Stale Data & Point resolv.conf to Uplink
log "Step 4: Linking /etc/resolv.conf to Uplink file (Fixing stale IPs)..."
sudo rm -f /etc/resolv.conf
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

# 6. Decommission NetworkManager
log "Step 5: Stopping and masking NetworkManager..."
sudo systemctl stop NetworkManager NetworkManager-wait-online.service || true
sudo systemctl mask NetworkManager NetworkManager-wait-online.service

# 7. Clean up Legacy Artifacts
log "Step 6: Purging legacy network artifacts..."
sudo rm -f /etc/NetworkManager/system-connections/*
sudo rm -f /etc/sysconfig/network-scripts/ifcfg-$PRIMARY_IF || true
sudo rm -rf /run/systemd/netif/leases/*

# 8. Restart and Enable Services
log "Step 7: Activating new network stack..."
sudo systemctl unmask systemd-networkd
sudo systemctl enable --now systemd-networkd systemd-resolved
sudo systemctl restart systemd-resolved
sudo systemctl restart systemd-networkd
sudo networkctl reconfigure "$PRIMARY_IF"

# =====================================================================
# PRODUCTION VALIDATION SUITE
# =====================================================================
log "RUNNING PRODUCTION VALIDATION..."

# CHECK 1: Ensure systemd-networkd is managing the interface
if ! networkctl status "$PRIMARY_IF" | grep -q "configured"; then
    echo "[FAIL] $PRIMARY_IF is not in 'configured' state."
    exit 1
fi

# CHECK 2: Ensure the Stub Listener (127.0.0.53) is DEAD
if ss -lnpt | grep -q "127.0.0.53:53"; then
    echo "[FAIL] DNS Stub Listener is still active on 127.0.0.53! CoreDNS will fail."
    exit 1
fi

# CHECK 3: Verify /etc/resolv.conf link integrity
if [ "$(readlink /etc/resolv.conf)" != "/run/systemd/resolve/resolv.conf" ]; then
    echo "[FAIL] /etc/resolv.conf is not pointing to the uplink resolv.conf."
    exit 1
fi

# CHECK 4: Verify DNS resolution is functional on the node
if ! host -W 2 google.com > /dev/null 2>&1; then
    # Fallback to check if nameservers exist if internet isn't available in VPC during build
    if ! grep -q "nameserver" /etc/resolv.conf; then
        echo "[FAIL] No nameservers found in /etc/resolv.conf."
        exit 1
    fi
fi

log "SUCCESS: All production validations passed."
echo "--------------------------------------------------------"
echo "Primary IF: $PRIMARY_IF"
echo "Resolv.conf Target: $(readlink /etc/resolv.conf)"
grep "nameserver" /etc/resolv.conf
resolvectl status "$PRIMARY_IF" | grep "DNS Servers" || true
echo "--------------------------------------------------------"
