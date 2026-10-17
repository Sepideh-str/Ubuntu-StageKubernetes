# Ubuntu Root Filesystem Expansion Using LVM

## Overview

The goal was to expand the root (`/`) filesystem on `Stage-WorkerF2` by using the unused space on the 60 GiB `/dev/sda` disk.

The server was already using LVM, so the storage structure consisted of several layers:

```text
Physical Disk
    ↓
Partition
    ↓
LVM Physical Volume (PV)
    ↓
Volume Group (VG)
    ↓
Logical Volume (LV)
    ↓
Filesystem
    ↓
Mount Point (/)
```

The important concept is that increasing one layer does not automatically increase the next layer. Therefore, we expanded the storage layer by layer.

---

## 1. Initial Storage Layout

We first checked the disks and filesystems:

```bash
lsblk -f
```

The initial layout was:

```text
sda                         60G
├─sda1                       1G   /boot/efi
├─sda2                       2G   /boot
└─sda3                      21.9G
  └─ubuntu--vg-ubuntu--lv   11G   /
```

This showed:

* `/dev/sda` was a 60 GiB disk.
* `/dev/sda1` was the EFI system partition.
* `/dev/sda2` was the `/boot` partition.
* `/dev/sda3` was the partition used by LVM.
* The root filesystem `/` was provided by the LVM logical volume `ubuntu-lv`.
* `/dev/sda3` was approximately 21.9 GiB.
* The root logical volume was approximately 11 GiB.

We then checked the LVM Physical Volume:

```bash
pvs
```

Initial result:

```text
PV         VG        Fmt  Attr PSize   PFree
/dev/sda3  ubuntu-vg lvm2 a--  <21.95g 10.97g
```

This meant that `/dev/sda3` was an LVM Physical Volume belonging to the Volume Group `ubuntu-vg`.

The PV was approximately 21.95 GiB, but approximately 10.97 GiB was already free inside the Volume Group.

We also checked the Volume Group:

```bash
vgs
```

Result:

```text
VG        #PV #LV #SN Attr   VSize   VFree
ubuntu-vg   1   1   0 wz--n- <21.95g 10.97g
```

So the Volume Group had:

```text
Total: ~21.95 GiB
Free:  ~10.97 GiB
```

Finally, we checked the Logical Volume:

```bash
lvs
```

Result:

```text
LV        VG        Attr       LSize
ubuntu-lv ubuntu-vg -wi-ao---- 10.97g
```

Therefore:

```text
Physical Volume:  ~21.95 GiB
Volume Group:     ~21.95 GiB
LV:               ~10.97 GiB
VG Free:          ~10.97 GiB
```

---

## 2. Checking the Partition Table

We inspected the disk:

```bash
fdisk -l /dev/sda
```

The original partition table showed:

```text
Device       Start      End  Sectors  Size Type
/dev/sda1     2048  2203647  2201600    1G EFI System
/dev/sda2  2203648  6397951  4194304    2G Linux filesystem
/dev/sda3  6397952 52426751 46028800 21.9G Linux filesystem
```

The important observation was:

```text
Disk size:    60 GiB
/dev/sda3:    21.9 GiB
```

Therefore, a large amount of disk space existed after `/dev/sda3` but was not part of the partition.

`fdisk` also showed:

```text
GPT PMBR size mismatch
```

This indicated that the partition table metadata still reflected the previous disk size.

---

## 3. Expanding `/dev/sda3`

We opened the disk using:

```bash
fdisk /dev/sda
```

Inside `fdisk`, we first printed the partition table:

```text
p
```

We then deleted partition 3:

```text
d
3
```

This did not immediately delete the actual LVM data. At this point, the change existed only in `fdisk`'s in-memory partition table.

We recreated partition 3:

```text
n
3
```

When `fdisk` asked for the first sector, we kept the original value:

```text
6397952
```

This was very important.

The original partition started at:

```text
6397952
```

and the new partition also started at:

```text
6397952
```

We must preserve the original starting sector because the existing LVM data begins from this location.

For the last sector, we accepted the default value so that `/dev/sda3` could use the remaining disk space.

The new partition became approximately 56.9 GiB:

```text
Device       Start       End   Sectors  Size Type
/dev/sda3  6397952 125827071 119429120 56.9G Linux filesystem
```

At this point, `fdisk` detected the existing LVM signature:

```text
Partition #3 contains a LVM2_member signature.
Do you want to remove the signature? [Y]es/[N]o:
```

We selected:

```text
N
```

This preserved the existing LVM metadata.

We then wrote the new partition table:

```text
w
```

After that, we verified the partition:

```bash
fdisk -l /dev/sda
```

The result showed:

```text
/dev/sda3  6397952 125827071 119429120 56.9G Linux filesystem
```

So `/dev/sda3` had successfully grown from approximately 21.9 GiB to approximately 56.9 GiB.

---

## 4. Expanding the LVM Physical Volume

Although the partition was now larger, LVM did not automatically know that the partition had additional space.

We therefore ran:

```bash
pvresize /dev/sda3
```

Then we checked:

```bash
pvs
```

Result:

```text
PV         VG        Fmt  Attr PSize   PFree
/dev/sda3  ubuntu-vg lvm2 a--  <56.95g 45.97g
```

The Physical Volume had now grown from:

```text
~21.95 GiB
```

to:

```text
~56.95 GiB
```

The Volume Group also gained additional free space.

We verified this using:

```bash
vgs
```

Result:

```text
VG        #PV #LV #SN Attr   VSize   VFree
ubuntu-vg   1   1   0 wz--n- <56.95g 45.97g
```

At this point:

```text
/dev/sda3
     ↓
PV = ~56.95 GiB
     ↓
ubuntu-vg
     ↓
Free = ~45.97 GiB
```

However, the root logical volume was still only approximately 10.97 GiB.

---

## 5. Understanding `/dev/mapper/ubuntu--vg-ubuntu--lv`

The root logical volume was represented by:

```text
/dev/mapper/ubuntu--vg-ubuntu--lv
```

This is **not another physical partition**.

It is a virtual block device created by the Linux device-mapper subsystem and used by LVM.

The LVM names were:

```text
Volume Group:
ubuntu-vg

Logical Volume:
ubuntu-lv
```

LVM exposes this logical volume through:

```text
/dev/mapper/ubuntu--vg-ubuntu--lv
```

The complete relationship is:

```text
/dev/sda3
    ↓
LVM Physical Volume
    ↓
ubuntu-vg
    ↓
ubuntu-lv
    ↓
/dev/mapper/ubuntu--vg-ubuntu--lv
    ↓
/
```

The double hyphens are LVM's escaping mechanism for hyphens in the original names.

For example:

```text
ubuntu-vg
```

becomes part of the device-mapper name as:

```text
ubuntu--vg
```

So:

```text
/dev/mapper/ubuntu--vg-ubuntu--lv
```

represents:

```text
Volume Group:  ubuntu-vg
Logical Volume: ubuntu-lv
```

---

## 6. First Logical Volume Resize

We initially ran:

```bash
lvresize -l 100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv
```

The command changed the logical volume from:

```text
10.97 GiB
```

to:

```text
45.97 GiB
```

The output was:

```text
Size of logical volume ubuntu-vg/ubuntu-lv changed from 10.97 GiB
(2809 extents) to 45.97 GiB (11769 extents).
Logical volume ubuntu-vg/ubuntu-lv successfully resized.
```

We then checked:

```bash
pvs
vgs
lvs
```

and saw:

```text
PFree: 10.97g
```

and:

```text
LSize: 45.97g
```

This was an important point.

The command:

```bash
lvresize -l 100%FREE
```

did not mean:

> Add all currently free space to the existing logical volume.

Instead, in our situation it resulted in the LV becoming approximately 45.97 GiB, leaving approximately 10.97 GiB still free in the Volume Group.

---

## 7. Using `+100%FREE`

Because approximately 10.97 GiB was still available in the Volume Group, we used:

```bash
lvresize -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv
```

The `+` is important.

It means to **add** the available free extents to the existing logical volume.

The command changed the LV from:

```text
45.97 GiB
```

to:

```text
<56.95 GiB
```

The output was:

```text
Size of logical volume ubuntu-vg/ubuntu-lv changed from 45.97 GiB
(11769 extents) to <56.95 GiB (14578 extents).
Logical volume ubuntu-vg/ubuntu-lv successfully resized.
```

We verified the result:

```bash
pvs
```

```text
PV         VG        Fmt  Attr PSize   PFree
/dev/sda3  ubuntu-vg lvm2 a--  <56.95g 0
```

Then:

```bash
vgs
```

```text
VG        #PV #LV #SN Attr   VSize   VFree
ubuntu-vg   1   1   0 wz--n- <56.95g 0
```

This confirmed that all available space in the Volume Group had been assigned to the logical volume.

The logical volume was now approximately:

```text
56.95 GiB
```

---

## 8. Checking the Filesystem

At this point, the Logical Volume was larger, but the filesystem inside it still needed to be expanded.

First, we checked the filesystem type:

```bash
findmnt -no FSTYPE /
```

The result was:

```text
ext4
```

Therefore, the appropriate command was:

```bash
resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
```

`resize2fs` expands an ext4 filesystem so that it can use the additional space provided by the larger logical volume.

Because the filesystem was `ext4`, it can be expanded while mounted, so `/` did not need to be unmounted.

We did **not** use:

```bash
mkfs.ext4
```

because `mkfs` creates a new filesystem and could destroy the existing data.

---

## 9. Complete Storage Architecture

After the expansion, the storage structure is conceptually:

```text
/dev/sda                         60 GiB
│
├── /dev/sda1                    1 GiB
│      └── /boot/efi
│
├── /dev/sda2                    2 GiB
│      └── /boot
│
└── /dev/sda3                  ~56.95 GiB
       │
       └── LVM Physical Volume
              │
              └── Volume Group: ubuntu-vg
                     │
                     └── Logical Volume: ubuntu-lv
                            │
                            └── /dev/mapper/ubuntu--vg-ubuntu--lv
                                   │
                                   └── ext4 filesystem
                                          │
                                          └── /
```

The complete expansion process was:

```text
Disk
 ↓
Partition
 ↓
Physical Volume
 ↓
Volume Group
 ↓
Logical Volume
 ↓
Filesystem
 ↓
/
```

Each layer had to be expanded in the correct order.

---

## 10. Commands Used

The main commands used were:

```bash
lsblk -f

pvs
vgs
lvs

fdisk -l /dev/sda

fdisk /dev/sda

pvresize /dev/sda3

pvs
vgs

lvresize -l 100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv

pvs
vgs
lvs

lvresize -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv

pvs
vgs

findmnt -no FSTYPE /

resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
```

For future LVM storage expansion, the general sequence is:

```text
1. Check the disk and current partition layout.
2. Expand the required partition.
3. Run pvresize.
4. Check the Volume Group with vgs.
5. Expand the Logical Volume with lvresize.
6. Expand the filesystem.
7. Verify the final filesystem size with df -h.
```

---

## 11. Important Safety Points

### Preserve the partition start sector

When recreating an existing LVM partition, the original start sector must remain unchanged.

In our case:

```text
Original start: 6397952
New start:      6397952
```

Changing the starting sector could make the existing LVM data inaccessible.

### Preserve the LVM signature

When `fdisk` displayed:

```text
Partition #3 contains a LVM2_member signature.
Do you want to remove the signature? [Y]es/[N]o:
```

we selected:

```text
N
```

This preserved the existing LVM metadata.

### Do not run `mkfs`

We did not run:

```bash
mkfs.ext4
```

because the filesystem already existed.

Running `mkfs` on the root logical volume could destroy the existing filesystem and its data.

### Verify each storage layer

Each layer should be checked separately:

```text
Partition       → fdisk -l
Physical Volume → pvs
Volume Group    → vgs
Logical Volume  → lvs
Filesystem      → df -h
```

This makes it much easier to identify where a storage expansion has stopped.

---

## 12. Before and After

### Before

```text
Disk:          60 GiB

/dev/sda1:      1 GiB   /boot/efi
/dev/sda2:      2 GiB   /boot
/dev/sda3:     21.9 GiB

LVM PV:        21.95 GiB
VG Free:       10.97 GiB

Root LV:       10.97 GiB
Filesystem:    ext4
Mount Point:   /
```

### After

```text
Disk:          60 GiB

/dev/sda1:      1 GiB   /boot/efi
/dev/sda2:      2 GiB   /boot
/dev/sda3:     ~56.9 GiB

LVM PV:        ~56.95 GiB
VG Free:        0 GiB

Root LV:       ~56.95 GiB
Filesystem:    ext4
Mount Point:   /
```

---

## 13. Key Concept to Remember

The most important thing to remember is:

> Expanding the disk does not automatically expand the filesystem.

With LVM, the expansion happens through several layers:

```text
Physical Disk
     ↓
Partition
     ↓
PV
     ↓
VG
     ↓
LV
     ↓
Filesystem
     ↓
Mount Point
```

In our case:

```text
/dev/sda
   ↓
/dev/sda3
   ↓
pvresize
   ↓
ubuntu-vg
   ↓
lvresize
   ↓
ubuntu-lv
   ↓
resize2fs
   ↓
/
```

The operation therefore expanded the storage from the physical disk all the way up to the filesystem that Linux uses for `/`.
