#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Talos Kubernetes cluster on Proxmox
#
# Creates:
#   801 k8s-master
#   802 k8s-worker-01
#   803 k8s-worker-02
#
# Networking:
#   DHCP
#
# DNS:
#   k8s-master.home
#   k8s-worker-01.home
#   k8s-worker-02.home
# ============================================================


# ============================================================
# Configuration
# ============================================================

# ---- Proxmox ------------------------------------------------

STORAGE="local-lvm"
ISO_STORAGE="local"
BRIDGE="vmbr0"

# Change this to your uploaded Talos ISO.
#
# Example:
#   local:iso/metal-amd64.iso
#
ISO="local:iso/metal-amd64.iso"


# ---- VM IDs -------------------------------------------------

MASTER_VMID=801
WORKER1_VMID=802
WORKER2_VMID=803


# ---- VM resources -------------------------------------------

CORES=2
MEMORY_MB=4096
DISK_GB=32


# ---- Hostnames ----------------------------------------------

MASTER_HOST="k8s-master.home"
WORKER1_HOST="k8s-worker-01.home"
WORKER2_HOST="k8s-worker-02.home"


# ---- Kubernetes ---------------------------------------------

CLUSTER_NAME="proxmox-k8s"

KUBERNETES_ENDPOINT="https://${MASTER_HOST}:6443"


# ---- Talos --------------------------------------------------

# Match this to the ISO you uploaded.
#
# Current stable release at the time this script was prepared:
# Talos v1.13.3
#
# The generated machine configuration must match the ISO.
#
TALOS_VERSION="v1.13.3"


# ---- Working directory --------------------------------------

WORK_DIR="/root/${CLUSTER_NAME}"

CONFIG_DIR="${WORK_DIR}/talos"

KUBECONFIG="${WORK_DIR}/kubeconfig"


# ============================================================
# Colors / logging
# ============================================================

log() {
    echo
    echo "[$(date '+%H:%M:%S')] $*"
}

die() {
    echo
    echo "ERROR: $*" >&2
    exit 1
}


# ============================================================
# Checks
# ============================================================

[[ $EUID -eq 0 ]] || die "Run this script as root."

command -v qm >/dev/null 2>&1 \
    || die "Proxmox 'qm' command not found."

command -v curl >/dev/null 2>&1 \
    || die "curl is required."

command -v getent >/dev/null 2>&1 \
    || die "getent is required."


# ============================================================
# Check ISO
# ============================================================

log "Checking Talos ISO..."

pvesm path "$ISO" >/dev/null 2>&1 \
    || die "Cannot find ISO: ${ISO}"

log "ISO found: ${ISO}"


# ============================================================
# Install talosctl if necessary
# ============================================================

if ! command -v talosctl >/dev/null 2>&1; then

    log "talosctl not found."

    log "Installing talosctl..."

    curl -sL https://talos.dev/install | sh

    if ! command -v talosctl >/dev/null 2>&1; then
        die "talosctl installation failed."
    fi
fi

log "talosctl version:"
talosctl version --client


# ============================================================
# Optional kubectl installation
# ============================================================

if ! command -v kubectl >/dev/null 2>&1; then

    log "kubectl not found."
    log "Kubernetes cluster will still be created."

    log "Installing kubectl..."

    KUBECTL_VERSION="$(curl -L -s \
        https://dl.k8s.io/release/stable.txt)"

    curl -L \
        -o /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

    chmod +x /usr/local/bin/kubectl

fi


# ============================================================
# Generate deterministic MAC addresses
# ============================================================
#
# Locally administered MAC addresses:
#
# 02:00:00:00:03:21
# 02:00:00:00:03:22
# 02:00:00:00:03:23
#
# The last byte corresponds to the VM ID.
#
# This means you can configure the DHCP reservations once
# in your router.
# ============================================================

MASTER_MAC="02:00:00:00:03:21"
WORKER1_MAC="02:00:00:00:03:22"
WORKER2_MAC="02:00:00:00:03:23"


# ============================================================
# Print router configuration
# ============================================================

cat <<EOF

============================================================
ROUTER DHCP RESERVATIONS
============================================================

Configure these MAC addresses in your router:

MASTER

  Hostname:
    ${MASTER_HOST}

  MAC:
    ${MASTER_MAC}


WORKER 1

  Hostname:
    ${WORKER1_HOST}

  MAC:
    ${WORKER1_MAC}


WORKER 2

  Hostname:
    ${WORKER2_HOST}

  MAC:
    ${WORKER2_MAC}

============================================================

The router should provide DNS records such as:

  k8s-master.home
  k8s-worker-01.home
  k8s-worker-02.home

============================================================

EOF

read -rp "Have you configured the DHCP reservations? [y/N] " ANSWER

[[ "${ANSWER}" =~ ^[Yy]$ ]] \
    || die "Configure the DHCP reservations first."


# ============================================================
# Check whether VMs already exist
# ============================================================

for VMID in \
    "$MASTER_VMID" \
    "$WORKER1_VMID" \
    "$WORKER2_VMID"
do

    if qm status "$VMID" >/dev/null 2>&1; then

        die "VM ${VMID} already exists. Refusing to overwrite it."

    fi

done


# ============================================================
# Create VM function
# ============================================================

create_vm() {

    local VMID="$1"
    local NAME="$2"
    local MAC="$3"

    log "Creating VM ${VMID}: ${NAME}"

    qm create "${VMID}" \
        --name "${NAME}" \
        --machine q35 \
        --bios ovmf \
        --cpu host \
        --cores "${CORES}" \
        --sockets 1 \
        --memory "${MEMORY_MB}" \
        --balloon 0 \
        --ostype l26 \
        --scsihw virtio-scsi-single \
        --scsi0 "${STORAGE}:${DISK_GB},discard=on,ssd=1" \
        --ide2 "${ISO},media=cdrom" \
        --net0 "virtio=${MAC},bridge=${BRIDGE}" \
        --boot "order=scsi0;ide2" \
        --serial0 socket \
        --vga serial0 \
        --onboot 1

    log "VM ${VMID} created."

}


# ============================================================
# Create VMs
# ============================================================

create_vm \
    "$MASTER_VMID" \
    "k8s-master" \
    "$MASTER_MAC"

create_vm \
    "$WORKER1_VMID" \
    "k8s-worker-01" \
    "$WORKER1_MAC"

create_vm \
    "$WORKER2_VMID" \
    "k8s-worker-02" \
    "$WORKER2_MAC"


# ============================================================
# Start VMs
# ============================================================

log "Starting Kubernetes VMs..."

qm start "$MASTER_VMID"
qm start "$WORKER1_VMID"
qm start "$WORKER2_VMID"


# ============================================================
# Resolve hostname
# ============================================================

resolve_host() {

    local HOST="$1"

    getent ahostsv4 "$HOST" \
        | awk 'NR==1 {print $1}'

}


# ============================================================
# Wait for DHCP + DNS
# ============================================================

wait_for_dns() {

    local HOST="$1"

    log "Waiting for DHCP/DNS: ${HOST}"

    local IP=""

    for ((i=1; i<=120; i++)); do

        IP="$(resolve_host "$HOST" || true)"

        if [[ -n "$IP" ]]; then

            log "${HOST} -> ${IP}"

            echo "$IP"

            return 0

        fi

        sleep 2

    done

    die "Could not resolve ${HOST}."

}


MASTER_IP="$(wait_for_dns "$MASTER_HOST")"
WORKER1_IP="$(wait_for_dns "$WORKER1_HOST")"
WORKER2_IP="$(wait_for_dns "$WORKER2_HOST")"


# ============================================================
# Display network configuration
# ============================================================

cat <<EOF

============================================================
KUBERNETES NODES
============================================================

Control plane:

  ${MASTER_HOST}
  ${MASTER_IP}

Worker 1:

  ${WORKER1_HOST}
  ${WORKER1_IP}

Worker 2:

  ${WORKER2_HOST}
  ${WORKER2_IP}

============================================================

EOF


# ============================================================
# Wait for Talos maintenance API
# ============================================================

wait_for_talos() {

    local HOST="$1"
    local IP="$2"

    log "Waiting for Talos API on ${HOST} (${IP})..."

    for ((i=1; i<=120; i++)); do

        if timeout 2 bash -c \
            "</dev/tcp/${IP}/50000" \
            >/dev/null 2>&1
        then

            log "Talos API available: ${HOST}"

            return 0

        fi

        sleep 2

    done

    die "Talos API did not become available on ${HOST}."

}


wait_for_talos "$MASTER_HOST" "$MASTER_IP"
wait_for_talos "$WORKER1_HOST" "$WORKER1_IP"
wait_for_talos "$WORKER2_HOST" "$WORKER2_IP"


# ============================================================
# Prepare configuration directory
# ============================================================

log "Preparing Talos configuration directory..."

rm -rf "${CONFIG_DIR}"

mkdir -p "${CONFIG_DIR}"


# ============================================================
# Generate Talos configuration
# ============================================================

log "Generating Talos machine configuration..."

talosctl gen config \
    "${CLUSTER_NAME}" \
    "${KUBERNETES_ENDPOINT}" \
    --output-dir "${CONFIG_DIR}" \
    --additional-sans "${MASTER_HOST}"


# ============================================================
# Hostname patches
# ============================================================

cat > "${CONFIG_DIR}/master.patch.yaml" <<EOF
machine:
  network:
    hostname: k8s-master
EOF


cat > "${CONFIG_DIR}/worker-01.patch.yaml" <<EOF
machine:
  network:
    hostname: k8s-worker-01
EOF


cat > "${CONFIG_DIR}/worker-02.patch.yaml" <<EOF
machine:
  network:
    hostname: k8s-worker-02
EOF


# ============================================================
# Patch generated machine configurations
# ============================================================

log "Patching control-plane configuration..."

talosctl machineconfig patch \
    "${CONFIG_DIR}/controlplane.yaml" \
    --patch "@${CONFIG_DIR}/master.patch.yaml" \
    -o "${CONFIG_DIR}/master.yaml"


log "Patching worker 1 configuration..."

talosctl machineconfig patch \
    "${CONFIG_DIR}/worker.yaml" \
    --patch "@${CONFIG_DIR}/worker-01.patch.yaml" \
    -o "${CONFIG_DIR}/worker-01.yaml"


log "Patching worker 2 configuration..."

talosctl machineconfig patch \
    "${CONFIG_DIR}/worker.yaml" \
    --patch "@${CONFIG_DIR}/worker-02.patch.yaml" \
    -o "${CONFIG_DIR}/worker-02.yaml"


# ============================================================
# Configure Talos
# ============================================================

log "Applying control-plane configuration..."

talosctl apply-config \
    --insecure \
    --nodes "${MASTER_IP}" \
    --file "${CONFIG_DIR}/master.yaml"


log "Applying worker 1 configuration..."

talosctl apply-config \
    --insecure \
    --nodes "${WORKER1_IP}" \
    --file "${CONFIG_DIR}/worker-01.yaml"


log "Applying worker 2 configuration..."

talosctl apply-config \
    --insecure \
    --nodes "${WORKER2_IP}" \
    --file "${CONFIG_DIR}/worker-02.yaml"


# ============================================================
# Configure talosctl
# ============================================================

export TALOSCONFIG="${CONFIG_DIR}/talosconfig"

talosctl config endpoint \
    "${MASTER_IP}"

talosctl config node \
    "${MASTER_IP}"


# ============================================================
# Wait for Talos nodes after installation/reboot
# ============================================================

log "Waiting for Talos installation to complete..."

sleep 20


log "Checking Talos health..."

talosctl health \
    --nodes "${MASTER_IP}" \
    --endpoints "${MASTER_IP}" \
    --wait-timeout 10m


# ============================================================
# Bootstrap Kubernetes
# ============================================================

log "Bootstrapping Kubernetes..."

talosctl bootstrap \
    --nodes "${MASTER_IP}" \
    --endpoints "${MASTER_IP}"


# ============================================================
# Wait for Kubernetes
# ============================================================

log "Waiting for Kubernetes control plane..."

sleep 30


# ============================================================
# Retrieve kubeconfig
# ============================================================

log "Retrieving kubeconfig..."

rm -f "${KUBECONFIG}"

talosctl kubeconfig \
    --nodes "${MASTER_IP}" \
    --endpoints "${MASTER_IP}" \
    "${KUBECONFIG}"


chmod 600 "${KUBECONFIG}"


# ============================================================
# Verify cluster
# ============================================================

export KUBECONFIG="${KUBECONFIG}"


log "Waiting for Kubernetes nodes..."

for ((i=1; i<=60; i++)); do

    if kubectl get nodes >/dev/null 2>&1; then
        break
    fi

    sleep 5

done


# ============================================================
# Final output
# ============================================================

echo
echo
echo "============================================================"
echo " Kubernetes cluster successfully created"
echo "============================================================"
echo

echo "Nodes:"
echo

kubectl get nodes -o wide

echo
echo "Talos configuration:"
echo

echo "  ${CONFIG_DIR}"

echo
echo "Kubeconfig:"
echo

echo "  ${KUBECONFIG}"

echo
echo "Use it with:"
echo

echo "  export KUBECONFIG=${KUBECONFIG}"

echo
echo "Then:"
echo

echo "  kubectl get nodes"

echo
echo "Talos:"
echo

echo "  export TALOSCONFIG=${CONFIG_DIR}/talosconfig"

echo
echo "============================================================"
