#!/usr/bin/env bash

# ============================================================
# install-talos-k8s.sh
#
# Creates a small Talos Kubernetes cluster on Proxmox:
#
#   801  k8s-master
#   802  k8s-worker-01
#   803  k8s-worker-02
#
# Per VM:
#   2 vCPU
#   4 GB RAM
#   32 GB disk
#
# Networking:
#   DHCP
#
# DNS:
#   k8s-master.home
#   k8s-worker-01.home
#   k8s-worker-02.home
#
# Run on a Proxmox node as root.
# ============================================================

set -Eeuo pipefail

# ============================================================
# DEFAULT CONFIGURATION
# ============================================================

DEFAULT_TALOS_VERSION="v1.13.3"

# Leave empty so the script explicitly asks for the URL.
# Obtain the ISO URL from:
# https://factory.talos.dev/
DEFAULT_TALOS_ISO_URL=""

DEFAULT_TALOSCTL_URL="https://github.com/siderolabs/talos/releases/download/${DEFAULT_TALOS_VERSION}/talosctl-linux-amd64"

# ============================================================
# PROXMOX CONFIGURATION
# ============================================================

STORAGE="local-lvm"
ISO_STORAGE="local"
BRIDGE="vmbr0"

# ============================================================
# VM IDs
# ============================================================

MASTER_VMID=801
WORKER1_VMID=802
WORKER2_VMID=803

# ============================================================
# VM RESOURCES
# ============================================================

CORES=2
MEMORY_MB=4096
DISK_GB=32

# ============================================================
# DNS HOSTNAMES
# ============================================================

MASTER_HOST="k8s-master.home"
WORKER1_HOST="k8s-worker-01.home"
WORKER2_HOST="k8s-worker-02.home"

# ============================================================
# KUBERNETES
# ============================================================

CLUSTER_NAME="proxmox-k8s"

KUBERNETES_ENDPOINT="https://${MASTER_HOST}:6443"

# ============================================================
# WORKING DIRECTORY
# ============================================================

WORK_DIR="/root/${CLUSTER_NAME}"
CONFIG_DIR="${WORK_DIR}/talos"
KUBECONFIG="${WORK_DIR}/kubeconfig"

# ============================================================
# DETERMINISTIC MAC ADDRESSES
#
# Configure these in your router as DHCP reservations:
#
#   02:00:00:00:03:21 -> k8s-master.home
#   02:00:00:00:03:22 -> k8s-worker-01.home
#   02:00:00:00:03:23 -> k8s-worker-02.home
# ============================================================

MASTER_MAC="02:00:00:00:03:21"
WORKER1_MAC="02:00:00:00:03:22"
WORKER2_MAC="02:00:00:00:03:23"

# ============================================================
# HELPERS
# ============================================================

log() {
    echo
    echo "[$(date '+%H:%M:%S')] $*"
}

warn() {
    echo
    echo "WARNING: $*" >&2
}

die() {
    echo
    echo "ERROR: $*" >&2
    exit 1
}

ask_default() {
    local PROMPT="$1"
    local DEFAULT="${2:-}"
    local VALUE

    if [[ -n "${DEFAULT}" ]]; then
        read -rp "${PROMPT} [${DEFAULT}]: " VALUE
        echo "${VALUE:-$DEFAULT}"
    else
        read -rp "${PROMPT}: " VALUE
        echo "${VALUE}"
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ============================================================
# REQUIRE ROOT
# ============================================================

[[ "${EUID}" -eq 0 ]] || die "Run this script as root."

# ============================================================
# REQUIRE PROXMOX
# ============================================================

command_exists qm || die "The 'qm' command was not found."
command_exists pvesm || die "The 'pvesm' command was not found."

# ============================================================
# REQUIRE BASIC COMMANDS
# ============================================================

command_exists curl || die "curl is required."
command_exists getent || die "getent is required."
command_exists awk || die "awk is required."
command_exists sha256sum || die "sha256sum is required."

# ============================================================
# HEADER
# ============================================================

echo
echo "============================================================"
echo "        Talos Kubernetes Cluster on Proxmox"
echo "============================================================"
echo
echo "This will create:"
echo
echo "  ${MASTER_VMID}  k8s-master"
echo "  ${WORKER1_VMID}  k8s-worker-01"
echo "  ${WORKER2_VMID}  k8s-worker-02"
echo
echo "Resources per VM:"
echo
echo "  CPU : ${CORES} cores"
echo "  RAM : ${MEMORY_MB} MB"
echo "  Disk: ${DISK_GB} GB"
echo

# ============================================================
# ASK TALOS VERSION
# ============================================================

TALOS_VERSION="$(
    ask_default \
        "Talos version" \
        "${DEFAULT_TALOS_VERSION}"
)"

# ============================================================
# ASK TALOS ISO URL
# ============================================================

echo
echo "Talos ISO URL."
echo
echo "Generate/download an ISO from:"
echo
echo "  https://factory.talos.dev/"
echo
echo "The URL normally looks like:"
echo
echo "  https://factory.talos.dev/image/<SCHEMATIC-ID>/${TALOS_VERSION}/metal-amd64.iso"
echo

TALOS_ISO_URL="$(
    ask_default \
        "Talos ISO URL" \
        "${DEFAULT_TALOS_ISO_URL}"
)"

[[ -n "${TALOS_ISO_URL}" ]] || die "A Talos ISO URL is required."

# ============================================================
# ASK TALOSCTL URL
# ============================================================

DEFAULT_TALOSCTL_URL="https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/talosctl-linux-amd64"

echo
echo "talosctl URL."
echo
echo "Default:"
echo
echo "  ${DEFAULT_TALOSCTL_URL}"
echo

TALOSCTL_URL="$(
    ask_default \
        "talosctl URL" \
        "${DEFAULT_TALOSCTL_URL}"
)"

# ============================================================
# SHOW CONFIGURATION
# ============================================================

echo
echo "============================================================"
echo "Configuration"
echo "============================================================"
echo
echo "Talos version:"
echo "  ${TALOS_VERSION}"
echo
echo "Talos ISO URL:"
echo "  ${TALOS_ISO_URL}"
echo
echo "talosctl URL:"
echo "  ${TALOSCTL_URL}"
echo
echo "Proxmox storage:"
echo "  ${STORAGE}"
echo
echo "ISO storage:"
echo "  ${ISO_STORAGE}"
echo
echo "Bridge:"
echo "  ${BRIDGE}"
echo
echo "Kubernetes endpoint:"
echo "  ${KUBERNETES_ENDPOINT}"
echo
echo "============================================================"
echo

read -rp "Continue? [y/N] " CONFIRM
[[ "${CONFIRM}" =~ ^[Yy]$ ]] || die "Installation cancelled."

# ============================================================
# ROUTER DHCP RESERVATIONS
# ============================================================

echo
echo "============================================================"
echo "Router DHCP reservations"
echo "============================================================"
echo
echo "Configure these MAC addresses in your router:"
echo
echo "  ${MASTER_HOST}"
echo "      MAC: ${MASTER_MAC}"
echo
echo "  ${WORKER1_HOST}"
echo "      MAC: ${WORKER1_MAC}"
echo
echo "  ${WORKER2_HOST}"
echo "      MAC: ${WORKER2_MAC}"
echo
echo "Your router should also provide DNS for these names."
echo
echo "Example:"
echo
echo "  k8s-master.home       -> 192.168.1.80"
echo "  k8s-worker-01.home    -> 192.168.1.81"
echo "  k8s-worker-02.home    -> 192.168.1.82"
echo
echo "The actual IP addresses are up to your router."
echo
echo "============================================================"
echo

read -rp "Have you configured DHCP and DNS? [y/N] " ANSWER
[[ "${ANSWER}" =~ ^[Yy]$ ]] || die "Configure DHCP/DNS first."

# ============================================================
# CHECK PROXMOX BRIDGE
# ============================================================

ip link show "${BRIDGE}" >/dev/null 2>&1 ||
    die "Proxmox bridge '${BRIDGE}' does not exist."

# ============================================================
# CHECK STORAGE
# ============================================================

pvesm status --storage "${STORAGE}" >/dev/null 2>&1 ||
    die "Proxmox storage '${STORAGE}' is not available."

pvesm status --storage "${ISO_STORAGE}" >/dev/null 2>&1 ||
    die "Proxmox ISO storage '${ISO_STORAGE}' is not available."

# ============================================================
# TALOS ISO
# ============================================================

ISO_FILENAME="$(basename "${TALOS_ISO_URL%%\?*}")"

[[ "${ISO_FILENAME}" == *.iso ]] ||
    die "The supplied URL does not appear to point to an ISO."

ISO_PATH="/var/lib/vz/template/iso/${ISO_FILENAME}"

log "Checking Talos ISO..."

if [[ -f "${ISO_PATH}" ]]; then

    log "Talos ISO already exists."

    echo
    echo "  ${ISO_PATH}"
    echo
    echo "Skipping download."

else

    log "Talos ISO not found."

    echo
    echo "Downloading:"
    echo
    echo "  ${TALOS_ISO_URL}"
    echo

    mkdir -p "$(dirname "${ISO_PATH}")"

    read -rp "Download the ISO now? [Y/n] " DOWNLOAD_ISO

    if [[ "${DOWNLOAD_ISO}" =~ ^[Nn]$ ]]; then
        die "Talos ISO is required."
    fi

    TMP_ISO="$(mktemp --suffix=.iso)"

    curl \
        --fail \
        --location \
        --progress-bar \
        --output "${TMP_ISO}" \
        "${TALOS_ISO_URL}"

    mv "${TMP_ISO}" "${ISO_PATH}"

    log "Talos ISO downloaded."

fi

# ============================================================
# REGISTER ISO WITH PROXMOX
# ============================================================

ISO="${ISO_STORAGE}:iso/${ISO_FILENAME}"

pvesm path "${ISO}" >/dev/null 2>&1 ||
    die "Proxmox cannot access ${ISO}"

log "Using Proxmox ISO:"
echo "  ${ISO}"

# ============================================================
# TALOSCTL
# ============================================================

if command_exists talosctl; then

    TALOSCTL_BIN="$(command -v talosctl)"

    log "talosctl already installed:"
    echo "  ${TALOSCTL_BIN}"

    echo
    talosctl version --client || true
    echo

    read -rp \
        "Use the existing talosctl installation? [Y/n] " \
        USE_EXISTING_TALOSCTL

    if [[ "${USE_EXISTING_TALOSCTL}" =~ ^[Nn]$ ]]; then

        log "Installing talosctl from supplied URL."

        TMP_TALOSCTL="$(mktemp)"

        curl \
            --fail \
            --location \
            --progress-bar \
            --output "${TMP_TALOSCTL}" \
            "${TALOSCTL_URL}"

        chmod +x "${TMP_TALOSCTL}"

        install \
            -m 0755 \
            "${TMP_TALOSCTL}" \
            /usr/local/bin/talosctl

        rm -f "${TMP_TALOSCTL}"

    fi

else

    log "talosctl is not installed."

    echo
    echo "Downloading:"
    echo
    echo "  ${TALOSCTL_URL}"
    echo

    TMP_TALOSCTL="$(mktemp)"

    curl \
        --fail \
        --location \
        --progress-bar \
        --output "${TMP_TALOSCTL}" \
        "${TALOSCTL_URL}"

    chmod +x "${TMP_TALOSCTL}"

    install \
        -m 0755 \
        "${TMP_TALOSCTL}" \
        /usr/local/bin/talosctl

    rm -f "${TMP_TALOSCTL}"

fi

command_exists talosctl || die "talosctl installation failed."

log "talosctl client version:"
talosctl version --client

# ============================================================
# KUBECTL
# ============================================================

if command_exists kubectl; then

    log "kubectl already installed."

else

    echo
    read -rp "kubectl is missing. Install it? [Y/n] " INSTALL_KUBECTL

    if [[ ! "${INSTALL_KUBECTL}" =~ ^[Nn]$ ]]; then

        KUBECTL_VERSION="$(
            curl \
                --fail \
                --location \
                --silent \
                https://dl.k8s.io/release/stable.txt
        )"

        log "Installing kubectl ${KUBECTL_VERSION}..."

        TMP_KUBECTL="$(mktemp)"

        curl \
            --fail \
            --location \
            --progress-bar \
            --output "${TMP_KUBECTL}" \
            "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

        chmod +x "${TMP_KUBECTL}"

        install \
            -m 0755 \
            "${TMP_KUBECTL}" \
            /usr/local/bin/kubectl

        rm -f "${TMP_KUBECTL}"

    fi

fi

# ============================================================
# CHECK EXISTING VMS
# ============================================================

log "Checking VM IDs..."

for VMID in \
    "${MASTER_VMID}" \
    "${WORKER1_VMID}" \
    "${WORKER2_VMID}"
do

    if qm status "${VMID}" >/dev/null 2>&1; then
        die "VM ${VMID} already exists. Refusing to modify it."
    fi

done

# ============================================================
# WORK DIRECTORY
# ============================================================

if [[ -d "${WORK_DIR}" ]]; then

    warn "Working directory already exists:"
    echo "  ${WORK_DIR}"
    echo

    read -rp "Remove it and start again? [y/N] " REMOVE_WORKDIR

    if [[ "${REMOVE_WORKDIR}" =~ ^[Yy]$ ]]; then
        rm -rf "${WORK_DIR}"
    else
        die "Existing working directory was not removed."
    fi

fi

mkdir -p "${CONFIG_DIR}"

# ============================================================
# CREATE VM FUNCTION
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
        --boot "order=ide2;scsi0" \
        --serial0 socket \
        --vga serial0 \
        --onboot 1

    log "VM ${VMID} created."

}

# ============================================================
# CREATE VMS
# ============================================================

create_vm \
    "${MASTER_VMID}" \
    "k8s-master" \
    "${MASTER_MAC}"

create_vm \
    "${WORKER1_VMID}" \
    "k8s-worker-01" \
    "${WORKER1_MAC}"

create_vm \
    "${WORKER2_VMID}" \
    "k8s-worker-02" \
    "${WORKER2_MAC}"

# ============================================================
# START VMS
# ============================================================

log "Starting Kubernetes VMs..."

qm start "${MASTER_VMID}"
qm start "${WORKER1_VMID}"
qm start "${WORKER2_VMID}"

# ============================================================
# DNS RESOLUTION
# ============================================================

resolve_ipv4() {

    local HOST="$1"

    getent ahostsv4 "${HOST}" |
        awk 'NR==1 {print $1}'

}

wait_for_dns() {

    local HOST="$1"
    local IP=""

    log "Waiting for DHCP/DNS: ${HOST}"

    for ((i=1; i<=120; i++)); do

        IP="$(resolve_ipv4 "${HOST}" || true)"

        if [[ -n "${IP}" ]]; then

            log "${HOST} -> ${IP}"

            echo "${IP}"
            return 0

        fi

        sleep 2

    done

    die "Unable to resolve ${HOST}."

}

# ============================================================
# RESOLVE NODE IPS
# ============================================================

MASTER_IP="$(wait_for_dns "${MASTER_HOST}")"
WORKER1_IP="$(wait_for_dns "${WORKER1_HOST}")"
WORKER2_IP="$(wait_for_dns "${WORKER2_HOST}")"

# ============================================================
# SHOW NETWORK
# ============================================================

echo
echo "============================================================"
echo "Kubernetes node addresses"
echo "============================================================"
echo
echo "  ${MASTER_HOST}"
echo "      ${MASTER_IP}"
echo
echo "  ${WORKER1_HOST}"
echo "      ${WORKER1_IP}"
echo
echo "  ${WORKER2_HOST}"
echo "      ${WORKER2_IP}"
echo
echo "============================================================"
echo

# ============================================================
# WAIT FOR TALOS API
# ============================================================

wait_for_port() {

    local IP="$1"
    local PORT="$2"
    local NAME="$3"

    log "Waiting for ${NAME} on ${IP}:${PORT}..."

    for ((i=1; i<=120; i++)); do

        if timeout 2 bash -c \
            "</dev/tcp/${IP}/${PORT}" \
            >/dev/null 2>&1
        then

            log "${NAME} is reachable."
            return 0

        fi

        sleep 2

    done

    die "${NAME} did not become reachable."

}

wait_for_port \
    "${MASTER_IP}" \
    50000 \
    "Talos control plane API"

wait_for_port \
    "${WORKER1_IP}" \
    50000 \
    "Talos worker 01 API"

wait_for_port \
    "${WORKER2_IP}" \
    50000 \
    "Talos worker 02 API"

# ============================================================
# DETECT TALOS DISKS
# ============================================================

log "Detecting disks on the control-plane node..."

talosctl get disks \
    --insecure \
    --nodes "${MASTER_IP}"

echo
echo "The Proxmox VM uses one SCSI disk."
echo "It should normally appear to Talos as /dev/sda."
echo

INSTALL_DISK="/dev/sda"

read -rp \
    "Talos installation disk [${INSTALL_DISK}]: " \
    CUSTOM_INSTALL_DISK

if [[ -n "${CUSTOM_INSTALL_DISK}" ]]; then
    INSTALL_DISK="${CUSTOM_INSTALL_DISK}"
fi

[[ "${INSTALL_DISK}" == /dev/* ]] ||
    die "Invalid installation disk: ${INSTALL_DISK}"

# ============================================================
# GENERATE TALOS CONFIGURATION
# ============================================================

log "Generating Talos configuration..."

rm -rf "${CONFIG_DIR}"
mkdir -p "${CONFIG_DIR}"

talosctl gen config \
    "${CLUSTER_NAME}" \
    "${KUBERNETES_ENDPOINT}" \
    --output-dir "${CONFIG_DIR}" \
    --install-disk "${INSTALL_DISK}" \
    --additional-sans "${MASTER_HOST}"

# ============================================================
# HOSTNAME PATCHES
# ============================================================

cat > "${CONFIG_DIR}/master-patch.yaml" <<'EOF'
machine:
  network:
    hostname: k8s-master
EOF

cat > "${CONFIG_DIR}/worker-01-patch.yaml" <<'EOF'
machine:
  network:
    hostname: k8s-worker-01
EOF

cat > "${CONFIG_DIR}/worker-02-patch.yaml" <<'EOF'
machine:
  network:
    hostname: k8s-worker-02
EOF

# ============================================================
# PATCH CONTROL PLANE
# ============================================================

log "Patching control-plane configuration..."

talosctl machineconfig patch \
    "${CONFIG_DIR}/controlplane.yaml" \
    --patch "@${CONFIG_DIR}/master-patch.yaml" \
    -o "${CONFIG_DIR}/master.yaml"

# ============================================================
# PATCH WORKER 01
# ============================================================

log "Patching worker 01 configuration..."

talosctl machineconfig patch \
    "${CONFIG_DIR}/worker.yaml" \
    --patch "@${CONFIG_DIR}/worker-01-patch.yaml" \
    -o "${CONFIG_DIR}/worker-01.yaml"

# ============================================================
# PATCH WORKER 02
# ============================================================

log "Patching worker 02 configuration..."

talosctl machineconfig patch \
    "${CONFIG_DIR}/worker.yaml" \
    --patch "@${CONFIG_DIR}/worker-02-patch.yaml" \
    -o "${CONFIG_DIR}/worker-02.yaml"

# ============================================================
# APPLY CONTROL PLANE CONFIG
# ============================================================

log "Applying control-plane configuration..."

talosctl apply-config \
    --insecure \
    --nodes "${MASTER_IP}" \
    --file "${CONFIG_DIR}/master.yaml"

# ============================================================
# APPLY WORKER 01 CONFIG
# ============================================================

log "Applying worker 01 configuration..."

talosctl apply-config \
    --insecure \
    --nodes "${WORKER1_IP}" \
    --file "${CONFIG_DIR}/worker-01.yaml"

# ============================================================
# APPLY WORKER 02 CONFIG
# ============================================================

log "Applying worker 02 configuration..."

talosctl apply-config \
    --insecure \
    --nodes "${WORKER2_IP}" \
    --file "${CONFIG_DIR}/worker-02.yaml"

# ============================================================
# CONFIGURE TALOSCTL
# ============================================================

export TALOSCONFIG="${CONFIG_DIR}/talosconfig"

log "Configuring talosctl..."

talosctl config endpoint \
    "${MASTER_IP}"

talosctl config node \
    "${MASTER_IP}"

# ============================================================
# WAIT FOR TALOS INSTALLATION
# ============================================================

log "Talos is installing to the VM disks."

log "Waiting for the control plane to reboot..."

sleep 20

# ============================================================
# WAIT FOR TALOS AGAIN
# ============================================================

wait_for_port \
    "${MASTER_IP}" \
    50000 \
    "Talos control plane API after installation"

# ============================================================
# HEALTH CHECK
# ============================================================

log "Checking Talos health..."

talosctl health \
    --nodes "${MASTER_IP}" \
    --endpoints "${MASTER_IP}" \
    --wait-timeout 10m

# ============================================================
# BOOTSTRAP ETCD / KUBERNETES
# ============================================================

log "Bootstrapping Kubernetes..."

talosctl bootstrap \
    --nodes "${MASTER_IP}" \
    --endpoints "${MASTER_IP}"

# ============================================================
# WAIT FOR KUBERNETES
# ============================================================

log "Waiting for Kubernetes control plane..."

sleep 30

# ============================================================
# RETRIEVE KUBECONFIG
# ============================================================

log "Retrieving kubeconfig..."

rm -f "${KUBECONFIG}"

talosctl kubeconfig \
    --nodes "${MASTER_IP}" \
    --endpoints "${MASTER_IP}" \
    "${KUBECONFIG}"

chmod 600 "${KUBECONFIG}"

export KUBECONFIG="${KUBECONFIG}"

# ============================================================
# WAIT FOR KUBERNETES NODES
# ============================================================

log "Waiting for Kubernetes nodes..."

for ((i=1; i<=120; i++)); do

    NODE_COUNT="$(
        kubectl get nodes \
            --no-headers \
            2>/dev/null |
            wc -l
    )"

    if [[ "${NODE_COUNT}" -ge 3 ]]; then
        break
    fi

    echo "  Kubernetes nodes available: ${NODE_COUNT}/3"

    sleep 5

done

# ============================================================
# FINAL NODE STATUS
# ============================================================

echo
echo "============================================================"
echo "Kubernetes nodes"
echo "============================================================"
echo

kubectl get nodes -o wide

echo

# ============================================================
# VERIFY
# ============================================================

NODE_COUNT="$(
    kubectl get nodes \
        --no-headers |
        wc -l
)"

if [[ "${NODE_COUNT}" -lt 3 ]]; then

    warn "Expected 3 Kubernetes nodes, but found ${NODE_COUNT}."

    echo
    echo "Check with:"
    echo
    echo "  export KUBECONFIG=${KUBECONFIG}"
    echo "  kubectl get nodes"
    echo

else

    log "All three Kubernetes nodes are registered."

fi

# ============================================================
# FINAL OUTPUT
# ============================================================

echo
echo
echo "============================================================"
echo "       Kubernetes cluster installation complete"
echo "============================================================"
echo
echo "Cluster:"
echo
echo "  ${CLUSTER_NAME}"
echo
echo "Control plane:"
echo
echo "  ${MASTER_HOST}"
echo "  ${MASTER_IP}"
echo
echo "Workers:"
echo
echo "  ${WORKER1_HOST}"
echo "  ${WORKER1_IP}"
echo
echo "  ${WORKER2_HOST}"
echo "  ${WORKER2_IP}"
echo
echo "Talos configuration:"
echo
echo "  ${CONFIG_DIR}"
echo
echo "Talosconfig:"
echo
echo "  ${CONFIG_DIR}/talosconfig"
echo
echo "Kubeconfig:"
echo
echo "  ${KUBECONFIG}"
echo
echo "============================================================"
echo
echo "Use Kubernetes:"
echo
echo "  export KUBECONFIG=${KUBECONFIG}"
echo "  kubectl get nodes"
echo
echo "Use Talos:"
echo
echo "  export TALOSCONFIG=${CONFIG_DIR}/talosconfig"
echo "  talosctl health"
echo
echo "============================================================"
echo
