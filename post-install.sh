#!/bin/bash
# =============================================================================
# ChaseWorksLab — Proxmox VE Post-Install Script
#
# Repo:   https://github.com/chaserbot/chaseworkslab-proxmox
# Path:   post-install.sh   (repo root — no subfolders)
# Run:    bash post-install.sh
#
# Supports: Proxmox VE 7, 8, 9+ (auto-detects Debian codename)
#
# Steps:
#  1.  Set hostname
#  2.  Fix Proxmox repos (disable enterprise, enable no-subscription)
#  3.  Disable subscription nag in web UI
#  4.  Update all packages
#  5.  Configure auto power-on after outage (Mac Mini — setpci)
#  6.  Load applesmc + coretemp modules at boot
#  7.  Install + configure mbpfan (fan control)
#  8.  Install QEMU guest agent
#  9.  Enable NTP time sync
# 10.  Disable HA services (re-enable after clustering)
# 11.  Mount NFS storage (LittlePeggy + BigPeggy via MM1)
# =============================================================================
set -euo pipefail

# ── Colors (only when stdout is a terminal) ───────────────────────────────────
if [[ -t 1 ]]; then
  BOLD='\033[1m';   DIM='\033[2m';    RESET='\033[0m'
  BCYAN='\033[1;36m'; WHITE='\033[1;37m'
  BGREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
else
  BOLD=''; DIM=''; RESET=''
  BCYAN=''; WHITE=''; BGREEN=''; YELLOW=''; RED=''
fi

TOTAL_STEPS=11

# ── Helpers ───────────────────────────────────────────────────────────────────
bar()  { echo -e "\n${BCYAN}${BOLD}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }
step() { bar; echo -e "  ${BCYAN}${BOLD}[${1}/${TOTAL_STEPS}]${RESET} ${WHITE}${BOLD}${2}${RESET}"; bar; }
ok()   { echo -e "  ${BGREEN}✓${RESET}  ${1}"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  ${1}"; }
info() { echo -e "  ${DIM}→${RESET}  ${1}"; }

# ── Root check ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo -e "\n  ${RED}${BOLD}Error: this script must be run as root.${RESET}\n"
  exit 1
fi

# ── Detect system ─────────────────────────────────────────────────────────────
DEBIAN_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
DEBIAN_VERSION_ID=$(. /etc/os-release && echo "$VERSION_ID")
PVE_VERSION=$(pveversion 2>/dev/null | grep -oP 'pve-manager/\K[0-9.]+' || echo "unknown")

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo ""
echo -e "${BCYAN}${BOLD}"
echo "  ╔════════════════════════════════════════════════════════════╗"
echo "  ║                                                            ║"
echo "  ║   C H A S E W O R K S L A B                               ║"
echo "  ║   Proxmox VE  ·  Post-Install Script                      ║"
echo "  ║                                                            ║"
echo -e "  ╚════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${DIM}Proxmox:${RESET}  ${WHITE}${PVE_VERSION}${RESET}"
echo -e "  ${DIM}Debian:${RESET}   ${WHITE}${DEBIAN_CODENAME} (${DEBIAN_VERSION_ID})${RESET}"
echo ""

# ── Node number ───────────────────────────────────────────────────────────────
# Accept as CLI arg (for scripted use) or prompt interactively
if [[ $# -ge 1 ]]; then
  NODE_NUM="$1"
else
  echo -e "  ${WHITE}${BOLD}Which node is this?${RESET}  ${DIM}(1 = pve1.chaseworkslab.com, 2 = pve2, etc.)${RESET}"
  echo ""
  read -rp "  Node number: " NODE_NUM
fi

# Validate: positive integer 1–99
if [[ ! "$NODE_NUM" =~ ^[1-9][0-9]?$ ]]; then
  echo -e "\n  ${RED}${BOLD}Error: node number must be between 1 and 99.${RESET}\n"
  exit 1
fi

HOSTNAME="pve${NODE_NUM}.chaseworkslab.com"
STATIC_IP="10.27.27.$((100 + NODE_NUM))"  # Node 1→.101, 2→.102, … 9→.109, 10→.110

# ── Confirm ───────────────────────────────────────────────────────────────────
echo ""
bar
echo -e "  ${WHITE}${BOLD}Node:${RESET}  ${HOSTNAME}"
echo -e "  ${WHITE}${BOLD}IP:${RESET}    ${STATIC_IP}  ${DIM}(confirm this matches your static assignment)${RESET}"
bar
echo ""
read -rp "  Press ENTER to start, or Ctrl+C to abort... "

# ── Helper: disable a DEB822 .sources file ────────────────────────────────────
# Adds "Enabled: no" to the first stanza if not already present.
disable_deb822() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  if grep -q "^Enabled: no" "$file"; then
    info "Already disabled: $(basename "$file")"
  elif grep -q "^Enabled:" "$file"; then
    sed -i 's/^Enabled:.*/Enabled: no/' "$file"
    ok "Disabled: $(basename "$file")"
  else
    # No Enabled: field present — insert before first Types: line
    sed -i '0,/^Types:/s/^Types:/Enabled: no\nTypes:/' "$file"
    ok "Disabled: $(basename "$file")"
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# 1. Hostname
# ──────────────────────────────────────────────────────────────────────────────
step 1 "Setting hostname"

hostnamectl set-hostname "$HOSTNAME"

# Update or add the 127.0.1.1 entry in /etc/hosts
if grep -q "^127\.0\.1\.1" /etc/hosts; then
  sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $HOSTNAME/" /etc/hosts
else
  echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
fi

ok "Hostname set to ${HOSTNAME}"

# ──────────────────────────────────────────────────────────────────────────────
# 2. Fix Proxmox repositories
# ──────────────────────────────────────────────────────────────────────────────
step 2 "Fixing Proxmox repositories"
info "Detected codename: ${DEBIAN_CODENAME}"

# -- Disable enterprise PVE repo --
# PVE 9+ uses DEB822 .sources format; PVE 7/8 used .list format.
if [[ -f /etc/apt/sources.list.d/pve-enterprise.sources ]]; then
  disable_deb822 /etc/apt/sources.list.d/pve-enterprise.sources
elif [[ -f /etc/apt/sources.list.d/pve-enterprise.list ]]; then
  sed -i 's/^deb /# deb /' /etc/apt/sources.list.d/pve-enterprise.list
  ok "Enterprise PVE repo disabled (pve-enterprise.list)"
else
  warn "No enterprise PVE repo file found — may already be removed"
fi

# -- Disable Ceph enterprise repo --
if [[ -f /etc/apt/sources.list.d/ceph.sources ]]; then
  disable_deb822 /etc/apt/sources.list.d/ceph.sources
elif [[ -f /etc/apt/sources.list.d/ceph.list ]]; then
  sed -i 's/^deb /# deb /' /etc/apt/sources.list.d/ceph.list
  ok "Ceph enterprise repo disabled (ceph.list)"
else
  info "No Ceph enterprise repo found — skipping"
fi

# -- Enable no-subscription repo using auto-detected codename --
cat > /etc/apt/sources.list.d/pve-no-subscription.list <<EOF
deb http://download.proxmox.com/debian/pve ${DEBIAN_CODENAME} pve-no-subscription
EOF
ok "No-subscription repo enabled (${DEBIAN_CODENAME})"

# -- Suppress non-free firmware warnings (codename-agnostic filename) --
echo 'APT::Get::Update::SourceListWarnings::NonFreeFirmware "false";' \
  > /etc/apt/apt.conf.d/no-firmware-nag.conf
ok "Firmware nag suppressed"

# ──────────────────────────────────────────────────────────────────────────────
# 3. Disable subscription nag
# ──────────────────────────────────────────────────────────────────────────────
step 3 "Disabling subscription nag"

JSFILE="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
if [[ -f "$JSFILE" ]]; then
  if grep -q "No valid subscription" "$JSFILE"; then
    sed -i "s/res === null || res === undefined ||/false || false ||/" "$JSFILE"
    ok "Subscription nag disabled"
  else
    info "Pattern not found — already patched or PVE version changed"
  fi
else
  warn "proxmoxlib.js not found — skipping nag patch"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 4. Update packages
# ──────────────────────────────────────────────────────────────────────────────
step 4 "Updating packages"

apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y -q
ok "Packages updated"

# ──────────────────────────────────────────────────────────────────────────────
# 5. Auto power-on after outage (Mac Mini specific)
# ──────────────────────────────────────────────────────────────────────────────
step 5 "Configuring auto power-on after outage"
info "Mac Mini specific: setpci tells the PCIe bridge to wake on power restore"

cat > /etc/systemd/system/mac-autoboot.service <<EOF
[Unit]
Description=Mac Mini Auto Power-On After Outage
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/setpci -s 0:3.0 0x7b.b=0x20
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mac-autoboot.service
systemctl start mac-autoboot.service
ok "mac-autoboot service enabled and running"

# ──────────────────────────────────────────────────────────────────────────────
# 6. Kernel modules: applesmc + coretemp
# ──────────────────────────────────────────────────────────────────────────────
step 6 "Loading applesmc + coretemp kernel modules"

for mod in applesmc coretemp; do
  if ! grep -q "^${mod}$" /etc/modules; then
    echo "$mod" >> /etc/modules
    info "Added ${mod} to /etc/modules"
  fi
  modprobe "$mod" 2>/dev/null \
    && ok "${mod} loaded" \
    || warn "${mod} failed to load now — will load after reboot"
done

# ──────────────────────────────────────────────────────────────────────────────
# 7. mbpfan (fan control)
# ──────────────────────────────────────────────────────────────────────────────
step 7 "Installing mbpfan (fan control)"

DEBIAN_FRONTEND=noninteractive apt-get install -y -q mbpfan

cat > /etc/mbpfan.conf <<EOF
[general]
# Temperatures in Celsius
# low_temp  — fans run at min speed below this
# high_temp — fans ramp toward max speed above this
# max_temp  — fans run at full speed
min_fan_speed    = 2000
max_fan_speed    = 6200
low_temp         = 55
high_temp        = 65
max_temp         = 80
polling_interval = 7
EOF

systemctl enable mbpfan
systemctl start mbpfan
ok "mbpfan installed and running (min 2000 RPM, max 6200 RPM)"

# ──────────────────────────────────────────────────────────────────────────────
# 8. QEMU guest agent (skipped — bare metal host)
# ──────────────────────────────────────────────────────────────────────────────
step 8 "QEMU guest agent (skipped)"
info "qemu-guest-agent is for VMs talking to a hypervisor — not needed on bare metal"
info "Install it inside your VMs/containers, not on the Proxmox host itself"

# ──────────────────────────────────────────────────────────────────────────────
# 9. NTP time sync
# ──────────────────────────────────────────────────────────────────────────────
step 9 "Enabling NTP time sync"

systemctl enable systemd-timesyncd
systemctl start systemd-timesyncd
timedatectl set-ntp true
ok "NTP enabled via systemd-timesyncd"

# ──────────────────────────────────────────────────────────────────────────────
# 10. Disable HA services (single-node until cluster is formed)
# ──────────────────────────────────────────────────────────────────────────────
step 10 "Disabling HA services (single-node mode)"
info "Re-enable after cluster is formed:"
info "  systemctl enable --now pve-ha-lrm pve-ha-crm corosync"

for svc in pve-ha-lrm pve-ha-crm; do
  systemctl disable --now "$svc" 2>/dev/null \
    && ok "${svc} disabled" \
    || info "${svc} was not running — skipping"
done

# ──────────────────────────────────────────────────────────────────────────────
# 11. NFS storage mounts (LittlePeggy + BigPeggy from MM1)
# ──────────────────────────────────────────────────────────────────────────────
step 11 "Mounting NFS storage from MM1 (10.27.27.22)"
info "LittlePeggy = Promise Pegasus 2 R8 (TB2) → /mnt/littlepeggy"
info "BigPeggy    = Promise Pegasus 3 R8 (TB3, capped at TB2) → /mnt/bigpeggy"
info "NOTE: Confirm exact volume names in Disk Utility on MM1 if mounts fail"

DEBIAN_FRONTEND=noninteractive apt-get install -y -q nfs-common
mkdir -p /mnt/littlepeggy /mnt/bigpeggy

if ! grep -q "littlepeggy" /etc/fstab; then
  echo "10.27.27.22:/Volumes/LittlePeggy  /mnt/littlepeggy  nfs  defaults,_netdev,nofail  0  0" >> /etc/fstab
  ok "LittlePeggy added to fstab"
else
  info "LittlePeggy already in fstab — skipping"
fi

if ! grep -q "bigpeggy" /etc/fstab; then
  echo "10.27.27.22:/Volumes/BigPeggy  /mnt/bigpeggy  nfs  defaults,_netdev,nofail  0  0" >> /etc/fstab
  ok "BigPeggy added to fstab"
else
  info "BigPeggy already in fstab — skipping"
fi

mount -a 2>/dev/null \
  && ok "NFS mounts active — verify with: df -h | grep mnt" \
  || warn "mount -a failed — MM1 may be offline. Mounts activate on next boot once MM1 is up."

# ── Done ──────────────────────────────────────────────────────────────────────
bar
echo ""
echo -e "  ${BGREEN}${BOLD}✓ All ${TOTAL_STEPS} steps complete for ${HOSTNAME}${RESET}"
echo ""
bar
echo ""
echo -e "  ${WHITE}${BOLD}Immediate next steps:${RESET}"
echo -e "  ${DIM}1.${RESET}  Reboot this node              ${WHITE}reboot${RESET}"
echo -e "  ${DIM}2.${RESET}  After reboot, check fans      ${WHITE}systemctl status mbpfan${RESET}"
echo -e "  ${DIM}3.${RESET}  Check auto-boot service       ${WHITE}systemctl status mac-autoboot${RESET}"
echo -e "  ${DIM}4.${RESET}  Check NFS mounts              ${WHITE}df -h | grep mnt${RESET}"
echo -e "  ${DIM}5.${RESET}  Repeat on next node before forming cluster"
echo ""
echo -e "  ${WHITE}${BOLD}After all nodes are ready:${RESET}"
echo -e "  ${DIM}→${RESET}  Form cluster from Node 1      ${WHITE}see cluster-setup.md${RESET}"
echo -e "  ${DIM}→${RESET}  Register NFS in Proxmox UI    ${WHITE}see storage-setup.md${RESET}"
echo -e "  ${DIM}→${RESET}  Re-enable HA after clustering ${DIM}(currently disabled)${RESET}"
echo ""
