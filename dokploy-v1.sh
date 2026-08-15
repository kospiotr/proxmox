#!/usr/bin/env bash

# Copyright (c) 2026
# Author: Piotr
# License: MIT
# Source: https://dokploy.com/

# ------------------------------------------------------------------------------
# Community Scripts framework
# ------------------------------------------------------------------------------

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# ------------------------------------------------------------------------------
# Application configuration
# ------------------------------------------------------------------------------

APP="Dokploy"

var_tags="${var_tags:-dokploy}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-30}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_arm64="${var_arm64:-yes}"

# Dokploy/Docker in LXC is better handled as privileged.
var_unprivileged="${var_unprivileged:-0}"

# ------------------------------------------------------------------------------
# Framework initialization
# ------------------------------------------------------------------------------

header_info "$APP"
variables
color
catch_errors

# ------------------------------------------------------------------------------
# IMPORTANT:
#
# build_container() automatically runs:
#
#   https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/${var_install}.sh
#
# We want the Community Scripts Docker installer to run first.
# variables() normally sets:
#
#   var_install="dokploy-install"
#
# Override it to use the existing Docker installer.
# ------------------------------------------------------------------------------

var_install="docker-install"

# ------------------------------------------------------------------------------
# Create LXC + install Docker
# ------------------------------------------------------------------------------

start
build_container

# ------------------------------------------------------------------------------
# Install Dokploy inside the newly-created LXC
# ------------------------------------------------------------------------------

msg_info "Installing Dokploy"

pct exec "$CTID" -- bash -c '
    set -e

    curl -sSL https://dokploy.com/install.sh | sh
'

msg_ok "Dokploy installed"

# ------------------------------------------------------------------------------
# Final information
# ------------------------------------------------------------------------------

CONTAINER_IP=$(pct exec "$CTID" -- hostname -I 2>/dev/null | awk "{print \$1}")

echo ""
echo -e "${INFO}${YW} Dokploy is available at:${CL}"
echo -e "${GATEWAY}${GN} http://${CONTAINER_IP}:3000${CL}"
echo ""
echo -e "${INFO}${YW} Container ID:${CL} ${GN}${CTID}${CL}"
echo -e "${INFO}${YW} Hostname:${CL} ${GN}$(pct config "$CTID" | awk -F': ' '/^hostname:/ {print $2}')${CL}"
echo ""

description
msg_ok "Completed successfully!"
