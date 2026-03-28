# chaseworkslab-proxmox

Proxmox VE configuration, post-install scripts, and cluster documentation for the chaseworkslab homelab.

---

## Hardware

| Device | Role | IP |
|---|---|---|
| Mac Mini #2 (A1347) | pve1 | 10.27.27.31 |
| Mac Mini #3 (A1347) | pve2 | 10.27.27.32 |
| Mac Mini #4 (A1347) | pve3 | 10.27.27.33 |

Internal domain: `chaseworkslab.com`

---

## Repo Structure

```
chaseworkslab-proxmox/
├── README.md
├── post-install.sh        ← Run on each node after fresh Proxmox install
├── cluster-setup.md       ← How to form the 3-node cluster
└── storage-setup.md       ← How to mount Pegasus NFS on all nodes
```

---

## Standing Up a New Proxmox Node

1. Install Proxmox VE from USB (hold Option on boot to select USB on Mac Mini)
2. SSH into the new node
3. Run the post-install script:

```bash
bash <(curl -s https://raw.githubusercontent.com/chaserbot/chaseworkslab-proxmox/main/proxmox/post-install.sh) <node-number>
```

4. Reboot
5. Verify fan control: `systemctl status mbpfan`
6. Verify auto-boot service: `systemctl status mac-autoboot`
7. See `cluster-setup.md` to join the cluster
