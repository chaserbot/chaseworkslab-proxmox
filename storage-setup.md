# DAS Storage Setup — chaseworkslab

Mac Mini #1 (`10.27.27.22`, macOS) hosts two Promise Pegasus DAS units via Thunderbolt daisy-chain and shares both over NFS to all 3 Proxmox nodes.

---

## Devices

| Name | Model | Interface | TB Gen | Host |
|---|---|---|---|---|
| LittlePeggy | Promise Pegasus 2 R8 | Thunderbolt 2 | TB2 (20Gbps) | Mac Mini 10.27.27.22 |
| BigPeggy | Promise Pegasus 3 R8 | Thunderbolt 3 | TB3 (40Gbps) | Mac Mini 10.27.27.22 |

---

## Physical Chain

```
Mac Mini A1347 (TB2, 10.27.27.22)
    └── LittlePeggy (Pegasus 2 R8, TB2)
            └── BigPeggy (Pegasus 3 R8, TB3)
```

> **Note:** The Mac Mini A1347 is TB2-only, so the entire chain is capped at 20Gbps regardless of BigPeggy's TB3 capability. Order does not meaningfully impact performance in this setup.

---

## Bandwidth Reality

| Segment | Theoretical | Real-World Estimate |
|---|---|---|
| Mac Mini → LittlePeggy | 20Gbps (~2,500 MB/s) | 800–1,200 MB/s |
| Mac Mini → BigPeggy (through chain) | 20Gbps shared | 800–1,200 MB/s (shared pipe) |
| Network to Proxmox nodes (1GbE) | 1Gbps (~125 MB/s) | ~110–115 MB/s |
| Network to Proxmox nodes (10GbE) | 10Gbps (~1,250 MB/s) | ~900–1,100 MB/s |

**The network is the bottleneck, not Thunderbolt.**

---

## Step 1 — Configure RAID on Each Unit (macOS)

Use **Promise Utility** (macOS app) to configure RAID independently on each unit:
- Open Promise Utility on Mac Mini #1
- Configure LittlePeggy's RAID level (confirm: RAID 5 or RAID 6?)
- Configure BigPeggy's RAID level independently
- Both units will appear as individual volumes in Disk Utility after RAID is set

---

## Step 2 — Enable NFS on Mac Mini #1 (macOS)

macOS NFS is configured via `/etc/exports`. There is no GUI for this.

1. Open Terminal on Mac Mini #1
2. Create or edit `/etc/exports`:

```
/Volumes/LittlePeggy -alldirs -mapall=nobody -network 10.27.27.0 -mask 255.255.255.0
/Volumes/BigPeggy    -alldirs -mapall=nobody -network 10.27.27.0 -mask 255.255.255.0

#Acutal
/Volumes/BigPeggy -alldirs -mapall=501:20 -network 10.27.27.0 -mask 255.255.255.0
/Volumes/BigPeggy -alldirs -mapall=501:20 -network 10.27.27.0 -mask 255.255.255.0
```

> **Important:** Confirm the exact volume names in Disk Utility — they may differ from the device names above.

3. Start (or restart) the NFS server:

```bash
sudo nfsd enable
sudo nfsd start
# If already running:
sudo nfsd restart
```

4. Verify exports are active:

```bash
sudo showmount -e localhost
```

You should see both `/Volumes/LittlePeggy` and `/Volumes/BigPeggy` listed.

---

## Step 3 — Mount NFS Shares on Each Proxmox Node

The post-install script (`proxmox/post-install.sh`) handles this automatically (Step 11). For manual setup or verification:

```bash
# Install NFS client
apt install nfs-common -y

# Create mount points
mkdir -p /mnt/littlepeggy /mnt/bigpeggy

# Test mounts
mount -t nfs 10.27.27.22:/Volumes/LittlePeggy /mnt/littlepeggy
mount -t nfs 10.27.27.22:/Volumes/BigPeggy /mnt/bigpeggy

# Verify
df -h | grep mnt
```

### /etc/fstab entries (persistent across reboots)

```bash
# LittlePeggy
10.27.27.22:/Volumes/LittlePeggy  /mnt/littlepeggy  nfs  defaults,_netdev,nofail  0  0

# BigPeggy
10.27.27.22:/Volumes/BigPeggy  /mnt/bigpeggy  nfs  defaults,_netdev,nofail  0  0
```

The `nofail` flag means the node will still boot normally if MM1 is offline.

---

## Step 4 — Register as Proxmox Datacenter Storage

In the Proxmox web UI (do this once per storage, applies to all nodes in cluster):

**Datacenter → Storage → Add → NFS**

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

---

## Recommended Folder Structure

```
/Volumes/LittlePeggy/          (or BigPeggy — assign based on capacity/use)
├── proxmox/
│   ├── images/                ← VM disk images
│   ├── backup/                ← Proxmox backup jobs
│   └── iso/                   ← ISO files for installs
├── media/
│   ├── movies/
│   ├── tv/
│   └── music/
└── containers/                ← LXC container appdata
    ├── jellyfin/
    ├── arr-stack/
    └── ...
```

---

## Notes

- Both DAS units **must** remain Thunderbolt-connected to Mac Mini #1 (`10.27.27.22`)
- If MM1 goes down, NFS shares go offline and containers depending on them will pause — this is expected
- NFS is strongly preferred over SMB for Proxmox/Linux nodes
- The `_netdev` fstab flag ensures mounts happen after networking is up at boot

---

## Open TODOs

- [ ] Confirm exact volume names after mounting (may differ from device names)
- [ ] Confirm RAID level on each unit (RAID 5 or RAID 6?)
- [ ] Verify `/etc/exports` config works on this version of macOS
- [ ] Update IP Address Map in PKM vault
