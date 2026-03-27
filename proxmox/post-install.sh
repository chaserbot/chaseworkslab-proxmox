#!/bin/bash
# =============================================================================
# chaseworkslab — Proxmox Mac Mini Post-Install Script
# Run this on each node immediately after a fresh Proxmox VE install.
#
# Usage: bash post-install.sh <node-number>
# Example: bash post-install.sh 1
#
# What this script does:
#  1. Sets hostname
#  2. Fixes Proxmox repos (removes enterprise nag, enables no-subscription)
#  3. Disables subscription nag in the web UI
#  4. Updates all packages
#  5. Enables auto power-on after outage (Mac Mini specific setpci fix)
#  6. Ensures applesmc + coretemp kernel modules load at boot
#  7. Installs and enables mbpfan for fan control
#  8. Installs QEMU guest agent (best practice)
#  9. Enables NTP time sync
# 10. Disables HA services (single-node until cluster is formed)
# =============================================================================

set -e

# --- Validate input -----------------------------------------------------------
NODE_NUM=${1:?"Usage: $0 <node-number> (e.g. $0 1)"}
if [[ ! "$NODE_NUM" =~ ^[1-3]$ ]]; then
  echo "ERROR: Node number must be 1, 2, or 3."
  exit 1
fi

HOSTNAME="pve${NODE_NUM}.chaseworkslab.com"
STATIC_IP="10.27.27.10${NODE_NUM}"  # Results in .101, .102, .103

echo ""
echo "=============================================="
echo " chaseworkslab Proxmox Post-Install Script"
echo " Node: $HOSTNAME"
echo " IP:   $STATIC_IP (verify this is correct)"
echo "=============================================="
echo ""
read -rp "Press ENTER to continue or Ctrl+C to abort..."

# --- 1. Hostname --------------------------------------------------------------
echo ""
echo "[1/10] Setting hostname..."
hostnamectl set-hostname "$HOSTNAME"
sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $HOSTNAME/" /etc/hosts
echo "  Done: hostname set to $HOSTNAME"

# --- 2. Fix Proxmox repositories ----------------------------------------------
echo ""
echo "[2/10] Fixing Proxmox repositories..."

# Disable enterprise repo (requires paid subscription)
if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
  sed -i 's/^deb/# deb/' /etc/apt/sources.list.d/pve-enterprise.list
fi

# Disable Ceph enterprise repo if present
if [ -f /etc/apt/sources.list.d/ceph.list ]; then
  sed -i 's/^deb/# deb/' /etc/apt/sources.list.d/ceph.list
fi

# Enable no-subscription repo
cat > /etc/apt/sources.list.d/pve-no-subscription.list <<EOF
deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription
EOF

# Suppress non-free firmware warning (Debian bookworm)
echo 'APT::Get::Update::SourceListWarnings::NonFreeFirmware "false";' \
  > /etc/apt/apt.conf.d/no-bookworm-firmware.conf

echo "  Done: repos configured"

# --- 3. Disable subscription nag ----------------------------------------------
echo ""
echo "[3/10] Disabling subscription nag..."
JSFILE="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
if [ -f "$JSFILE" ]; then
  if grep -q "No valid subscription" "$JSFILE"; then
    sed -i "s/res === null || res === undefined ||/false || false ||/" "$JSFILE"
    echo "  Done: subscription nag disabled"
  else
    echo "  Already patched or pattern not found — skipping"
  fi
else
  echo "  WARNING: proxmoxlib.js not found — skipping nag patch"
fi

# --- 4. Update packages -------------------------------------------------------
echo ""
echo "[4/10] Updating packages..."
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y -q
echo "  Done: packages updated"

# --- 5. Auto power-on after power outage (Mac Mini specific) ------------------
echo ""
echo "[5/10] Configuring auto power-on after outage..."
# The setpci command enables the Mac Mini to power on automatically when
# power is restored after an outage. Without this the Mac Mini stays off.
# Persisted via a systemd service so it survives reboots.
cat > /etc/systemd/system/mac-autoboot.service <<EOF
[Unit]
Description=Mac Mini Auto Power-On After Outage
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/setpci -s 0:3.0 0x7b.b=0x20
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mac-autoboot.service
systemctl start mac-autoboot.service
echo "  Done: mac-autoboot service enabled"

# --- 6. Load applesmc + coretemp kernel modules at boot -----------------------
echo ""
echo "[6/10] Configuring kernel modules for applesmc and coretemp..."
if ! grep -q "applesmc" /etc/modules; then
  echo "applesmc" >> /etc/modules
fi
if ! grep -q "coretemp" /etc/modules; then
  echo "coretemp" >> /etc/modules
fi
modprobe applesmc 2>/dev/null || echo "  WARNING: applesmc failed to load now (will load after reboot)"
modprobe coretemp 2>/dev/null || echo "  WARNING: coretemp failed to load now (will load after reboot)"
echo "  Done: kernel modules configured"

# --- 7. Install and enable mbpfan (fan control) -------------------------------
echo ""
echo "[7/10] Installing mbpfan..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -q mbpfan

# Sensible config for a headless Mac Mini server
cat > /etc/mbpfan.conf <<EOF
[general]
# Temperatures in Celsius
# low_temp  = fans run at min speed below this
# high_temp = fans ramp up toward max speed
# max_temp  = fans run at full speed
min_fan_speed = 2000
max_fan_speed = 6200
low_temp = 55
high_temp = 65
max_temp = 80
polling_interval = 7
EOF

systemctl enable mbpfan
systemctl start mbpfan
echo "  Done: mbpfan installed and running"

# --- 8. QEMU Guest Agent ------------------------------------------------------
echo ""
echo "[8/10] Installing QEMU guest agent..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -q qemu-guest-agent
systemctl enable qemu-guest-agent
systemctl start qemu-guest-agent
echo "  Done: qemu-guest-agent installed"

# --- 9. NTP time sync ---------------------------------------------------------
echo ""
echo "[9/10] Ensuring NTP time sync is active..."
systemctl enable systemd-timesyncd
systemctl start systemd-timesyncd
timedatectl set-ntp true
echo "  Done: NTP enabled"

# --- 10. Disable HA services (re-enable after cluster is formed) --------------
echo ""
echo "[10/10] Disabling HA services (single-node mode)..."
# HA services cause log spam and resource waste on standalone nodes.
# Re-enable with: systemctl enable --now pve-ha-lrm pve-ha-crm corosync
systemctl disable --now pve-ha-lrm 2>/dev/null || true
systemctl disable --now pve-ha-crm 2>/dev/null || true
echo "  Done: HA services disabled (re-enable after cluster formation)"

# --- Done ---------------------------------------------------------------------
echo ""
echo "=============================================="
echo " Post-install complete for $HOSTNAME"
echo "=============================================="
echo ""
echo "  NEXT STEPS:"
echo "  1. Reboot this node:               reboot"
echo "  2. After reboot, verify fans:      systemctl status mbpfan"
echo "  3. Verify auto-boot service:       systemctl status mac-autoboot"
echo "  4. Repeat on the next node before forming the cluster"
echo ""
echo "  AFTER ALL 3 NODES ARE READY:"
echo "  - Form the cluster from Node 1 (see proxmox/cluster-setup.md)"
echo "  - Mount Pegasus NFS storage (see proxmox/storage-setup.md)"
echo "  - Re-enable HA if desired after clustering"
echo ""
