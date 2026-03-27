# Proxmox Cluster Setup — chaseworkslab

Run this **after** all 3 nodes have been through `post-install.sh` and rebooted.

---

## Prerequisites

- All 3 nodes are up and reachable at their static IPs
- All 3 are on the same Proxmox VE version (`pveversion` to check)
- All 3 are connected via ethernet to the same switch

---

## Step 1 — Create the cluster (run on Node 1 only)

```bash
pvecm create chaseworkslab
```

Verify:

```bash
pvecm status
```

---

## Step 2 — Join Node 2 and Node 3 (run on each joining node)

SSH into Node 2, then run:

```bash
pvecm add 10.27.27.101
```

Repeat on Node 3:

```bash
pvecm add 10.27.27.101
```

You'll be prompted for Node 1's root password each time.

---

## Step 3 — Verify cluster health (run on any node)

```bash
pvecm status
pvecm nodes
```

All 3 nodes should show as online with no errors.

---

## Step 4 — Re-enable HA services now that cluster is formed

Run on **all 3 nodes**:

```bash
systemctl enable --now pve-ha-lrm pve-ha-crm corosync
```

---

## Step 5 — Register LittlePeggy + BigPeggy NFS storage

The NFS mounts were added to `/etc/fstab` by `post-install.sh` (Step 11) and should already be mounted. Verify first:

```bash
df -h | grep mnt
```

Then register each as Proxmox storage in the UI:

**Datacenter → Storage → Add → NFS** (repeat for each unit)

| Field | LittlePeggy | BigPeggy |
|---|---|---|
| ID | `littlepeggy` | `bigpeggy` |
| Server | `10.27.27.22` | `10.27.27.22` |
| Export | `/Volumes/LittlePeggy` | `/Volumes/BigPeggy` |
| Content | Disk image, ISO, Backup, Container | Disk image, ISO, Backup, Container |

Or via CLI on any node:

```bash
pvesm add nfs littlepeggy --server 10.27.27.22 --export /Volumes/LittlePeggy --content images,iso,backup,vztmpl
pvesm add nfs bigpeggy    --server 10.27.27.22 --export /Volumes/BigPeggy    --content images,iso,backup,vztmpl
```

See `storage-setup.md` for full NFS setup details including macOS export config.

---

## Node IP Reference

| Node | Hostname | IP |
|------|------------------------|---------------|
| 1 | pve1.chaseworkslab.com | 10.27.27.101 |
| 2 | pve2.chaseworkslab.com | 10.27.27.102 |
| 3 | pve3.chaseworkslab.com | 10.27.27.103 |
