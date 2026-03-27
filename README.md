# 🏠 chaseworkslab-homelab

Personal homelab infrastructure — configs, scripts, and documentation.

The goal: if the house burned down and new hardware showed up, this repo is everything needed to get back to a running state.

---

## 🖥️ Hardware

| Device | Role | OS |
|---|---|---|
| Mac Mini #1 (A1347) | NAS Brain / Pegasus DAS host | macOS |
| Mac Mini #2 (A1347) | Proxmox Node 1 — pve1 | Proxmox VE |
| Mac Mini #3 (A1347) | Proxmox Node 2 — pve2 | Proxmox VE |
| Mac Mini #4 (A1347) | Proxmox Node 3 — pve3 | Proxmox VE |
| Ace Magician CK10 | Jellyfin (media server) | — |
| Intel NUC5i5RYK x2 | Spare / Batocera gaming | — |
| Pegasus DAS | Shared storage (Thunderbolt → MM1) | — |
| Luxul ABR-5000 | Router | — |
| Ubiquiti USW PoE 8 Lite | Switch | — |
| Archer AX1800 | Access point | — |
| TP-Link EAP225 Outdoor | Outdoor access point | — |

---

## 🌐 Network

| Device | IP |
|---|---|
| Mac Mini #1 (macOS) | 10.27.27.22 |
| Mac Mini #2 (pve1) | 10.27.27.101 |
| Mac Mini #3 (pve2) | 10.27.27.102 |
| Mac Mini #4 (pve3) | 10.27.27.103 |

Internal domain: `chaseworkslab.com`

---

## 📁 Repo Structure

```
chaseworkslab-homelab/
├── README.md ← You are here
├── .gitignore ← Secrets and .env files excluded
├── proxmox/
│ ├── post-install.sh ← Run on each node after fresh Proxmox install
│ ├── cluster-setup.md ← How to form the 3-node cluster
│ └── storage-setup.md ← How to mount Pegasus NFS on all nodes
├── services/ ← One folder per self-hosted service
│ ├── jellyfin/
│ │ ├── docker-compose.yml
│ │ └── README.md
│ ├── arr-stack/
│ │ ├── docker-compose.yml
│ │ └── README.md
│ └── ...
├── network/
│ ├── dns-records.md ← All internal DNS entries
│ └── tailscale-setup.md ← Remote access setup
└── scripts/
└── ...
```

---

## 🚀 Standing Up a New Proxmox Node

1. Install Proxmox VE from USB (hold Option on boot to select USB on Mac Mini)
2. SSH into the new node
3. Run the post-install script:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/chaserbot/chaseworkslab-proxmox/main/proxmox/post-install.sh) <node-number>
```

4. Reboot
5. Verify fan control: `systemctl status mbpfan`
6. Verify auto-boot service: `systemctl status mac-autoboot`
7. See `proxmox/cluster-setup.md` to join the cluster

---

## 📦 Services

| Service | Port | Host | Status |
|---|---|---|---|
| Jellyfin | 8096 | CK10 | ✅ Active |
| Audiobookshelf | 13378 | MM1 | 🔄 To migrate |
| Radarr | 7878 | MM1 | 🔄 To migrate |
| Sonarr | 8989 | MM1 | 🔄 To migrate |
| Prowlarr | — | MM1 | 🔄 To migrate |
| Overseerr | 5055 | MM1 | 🔄 To migrate |
| qBittorrent | — | MM1 | 🔄 To migrate |
| Paperless-ngx | — | MM1 | 🔄 To migrate |
| Uptime Kuma | 3001 | MM1 | 🔄 To migrate |
| AdGuard Home | 53/80 | pve (planned) | ⬜ Pending |
| Nginx Proxy Manager | 80/443 | pve (planned) | ⬜ Pending |
| n8n | 5678 | pve (planned) | ⬜ Pending |

---

## 🔒 Secrets

Secrets are **never** committed to this repo.

`.env` files, API keys, and passwords are excluded via `.gitignore`.

Each service folder contains a `.env.example` file documenting which secrets
are needed — fill in your own values and save as `.env` locally.

---

## 📋 Project Tracks

| Track | Description | Status |
|---|---|---|
| T1 | Physical & Cable Management | ✅ Done |
| T2 | Proxmox Cluster Setup | 🔧 Active |
| T3 | Network, DNS & Remote Access | ⬜ Pending |
| T4 | Service Migration & Distribution | ⬜ Pending |
| T5 | n8n Automation | ⬜ Pending |
| T6 | FATFISH AI Assistant | 🧪 Design Phase |
| T7 | Reproducibility & GitHub | ♻️ Ongoing |
