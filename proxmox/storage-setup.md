# Pegasus Storage Setup — chaseworkslab

Mac Mini #1 (macOS) shares the Pegasus DAS over NFS to all 3 Proxmox nodes.

---

## Step 1 — Enable NFS on Mac Mini #1 (macOS)

macOS doesn't have a GUI for NFS exports. You configure it via `/etc/exports`.

1. Open Terminal on Mac Mini #1
2. Create or edit `/etc/exports`:

```
/Volumes/Pegasus -alldirs -mapall=nobody -network 10.27.27.0 -mask 255.255.255.0
```

> Replace `/Volumes/Pegasus` with the actual mount name of your Pegasus volume.

3. Start the NFS server:
```bash
sudo nfsd enable
sudo nfsd start
```

4. Verify exports are active:
```bash
sudo showmount -e localhost
```

---

## Step 2 — Mount the NFS share on each Proxmox node

Run on each node (or add to /etc/fstab for persistence):

```bash
# Test mount first
mkdir -p /mnt/pegasus
mount -t nfs 10.27.27.X:/Volumes/Pegasus /mnt/pegasus

# If that works, make it persistent
echo "10.27.27.X:/Volumes/Pegasus /mnt/pegasus nfs defaults,_netdev 0 0" >> /etc/fstab
```

> Replace `10.27.27.X` with Mac Mini #1's actual static IP.

---

## Step 3 — Add as Proxmox Datacenter Storage

In the Proxmox web UI:

1. Datacenter → Storage → Add → NFS
2. Fill in:
   - **ID:** `pegasus`
   - **Server:** `10.27.27.X` (Mac Mini #1 IP)
   - **Export:** `/Volumes/Pegasus`
   - **Content:** Disk image, Container, ISO, Backup — check all that apply
3. Click Add

The storage will now appear on all nodes in the cluster.

---

## Folder Structure on Pegasus (Recommended)

```
/Volumes/Pegasus/
├── proxmox/
│   ├── images/        ← VM disk images
│   ├── backup/        ← Proxmox backup jobs
│   └── iso/           ← ISO files for installs
├── media/
│   ├── movies/
│   ├── tv/
│   └── music/
└── containers/        ← LXC container data (appdata)
    ├── jellyfin/
    ├── arr-stack/
    └── ...
```

---

## Notes

- The Pegasus **must** remain Thunderbolt-connected to Mac Mini #1
- If Mac Mini #1 goes down, NFS shares will be unavailable and containers
  relying on Pegasus storage will pause — this is expected behavior
- For production resilience, consider Proxmox Backup Server on a separate node
