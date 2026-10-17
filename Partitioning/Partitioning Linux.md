# Linux Storage, Partitioning, Filesystems, Mount Points, and LVM

## 1. Overview

Linux storage can be understood as several layers:

```text
Physical Disk
      ↓
Partitions
      ↓
Filesystem
      ↓
Mount Point
      ↓
Files and Directories
```

When LVM is used, there is an additional storage-management layer:

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
Mount Point
      ↓
Files and Directories
```

---

# 2. The Physical Disk

A disk is the actual storage device available to Linux.

For example:

```text
/dev/sda
```

If the server has a 60 GB disk:

```text
/dev/sda = 60 GB
```

We can see disks with:

```bash
lsblk
```

Example:

```text
NAME   SIZE TYPE
sda     60G disk
```

`/dev/sda` represents the whole disk.

---

# 3. Partitions

A physical disk can be divided into smaller sections called **partitions**.

For example:

```text
/dev/sda = 60 GB
│
├── /dev/sda1 = 1 GB
├── /dev/sda2 = 2 GB
└── /dev/sda3 = 21.9 GB
```

Each partition is a separate region of the disk.

A partition can be used for different purposes.

For example:

```text
/dev/sda1 → EFI
/dev/sda2 → /boot
/dev/sda3 → LVM
```

The important point is:

> A partition is a region of physical disk storage. It is not automatically a filesystem.

---

# 4. Filesystems

A **filesystem** is the structure Linux uses to organize files and directories on storage.

Common Linux filesystems include:

* `ext4`
* `xfs`
* `btrfs`

A filesystem allows Linux to store and manage things such as:

* files
* directories
* permissions
* ownership
* metadata
* free space

Conceptually:

```text
Storage
   ↓
Filesystem
   ↓
Files and Directories
```

A filesystem can be created directly on a partition.

For example:

```text
/dev/sda3
    ↓
ext4 filesystem
```

---

# 5. Mount Points

Linux uses a **single unified directory tree**.

The top of this tree is:

```text
/
```

This is called the **root directory**.

The Linux filesystem tree may look like:

```text
/
├── etc
├── usr
├── var
├── home
├── boot
├── opt
└── ...
```

A filesystem can be **mounted** at a directory in this tree.

That directory is called the **mount point**.

For example:

```text
/dev/sda2
    ↓
Filesystem
    ↓
/boot
```

Here:

```text
/boot = mount point
```

When Linux accesses:

```text
/boot
```

it is accessing the filesystem mounted there.

---

# 6. `/` and the Root Filesystem

The root directory is:

```text
/
```

The root filesystem is the filesystem mounted at `/`.

For example:

```text
Filesystem
    ↓
    /
```

Directories such as:

```text
/etc
/usr
/var
/home
```

are normally part of the root filesystem unless another filesystem is mounted at one of those directories.

For example:

```text
/
├── etc
├── usr
├── var
└── home
```

All of these can normally be stored on the filesystem mounted at `/`.

However, Linux can mount separate filesystems at these locations.

For example:

```text
/
├── etc
├── usr
├── var
└── home
        ↑
        └── separate filesystem mounted here
```

---

# 7. Example: `/boot`

Suppose:

```text
/dev/sda2
```

contains a filesystem and that filesystem is mounted at:

```text
/boot
```

Then:

```text
/dev/sda2
     ↓
Filesystem
     ↓
/boot
```

`/boot` is the **mount point**.

Accessing:

```text
/boot
```

means accessing the filesystem mounted there.

---

# 8. Linux Storage Without LVM

Without LVM, a simple storage layout can look like this:

```text
/dev/sda
│
├── /dev/sda1
│      ↓
│   Filesystem
│      ↓
│   /boot/efi
│
├── /dev/sda2
│      ↓
│   Filesystem
│      ↓
│   /boot
│
└── /dev/sda3
       ↓
    Filesystem
       ↓
       /
```

The relationship is:

```text
Partition
    ↓
Filesystem
    ↓
Mount Point
```

Here the filesystem is directly on the partition.

---

# 9. What Is LVM?

LVM stands for:

**Logical Volume Manager**

LVM is a storage-management layer that makes storage more flexible.

Instead of putting a filesystem directly on a partition:

```text
Partition
    ↓
Filesystem
    ↓
/
```

we can use:

```text
Partition
    ↓
LVM
    ↓
Logical Volume
    ↓
Filesystem
    ↓
/
```

LVM allows storage to be managed as a **storage pool**.

---

# 10. Giving a Partition to LVM

Suppose:

```text
/dev/sda3 = 56.95 GB
```

We can give that partition to LVM.

The partition becomes an LVM **Physical Volume (PV)**:

```text
/dev/sda3
    ↓
Physical Volume (PV)
```

The important idea is:

> The partition provides storage to LVM.

LVM does not automatically mean that the entire disk is controlled by LVM.

For example:

```text
/dev/sda
│
├── /dev/sda1 → normal filesystem
├── /dev/sda2 → normal filesystem
└── /dev/sda3 → LVM
```

Only `/dev/sda3` is being used by LVM in this example.

---

# 11. Physical Volume (PV)

A **Physical Volume (PV)** is storage that has been assigned to LVM.

For example:

```text
/dev/sda3
    ↓
PV
```

We can see Physical Volumes with:

```bash
pvs
```

For example:

```text
PV         VG        PSize   PFree
/dev/sda3  ubuntu-vg <56.95g 10.97g
```

This tells us that:

* `/dev/sda3` is being used by LVM.
* It belongs to `ubuntu-vg`.
* LVM has approximately 56.95 GB of storage from it.
* Approximately 10.97 GB is still free.

---

# 12. Volume Group (VG)

A **Volume Group (VG)** is the LVM **storage pool**.

For example:

```text
/dev/sda3
    ↓
PV
    ↓
ubuntu-vg
```

The Volume Group contains the storage that can be allocated to Logical Volumes.

For example:

```text
ubuntu-vg = ~56.95 GB

┌──────────────────────────────────────┐
│                                      │
│ ubuntu-lv = 45.97 GB                 │
│                                      │
├──────────────────────────────────────┤
│                                      │
│ Free = 10.97 GB                      │
│                                      │
└──────────────────────────────────────┘
```

We can see Volume Groups with:

```bash
vgs
```

Example:

```text
VG        #PV  #LV  VSize   VFree
ubuntu-vg   1    1  <56.95g 10.97g
```

This means:

* `ubuntu-vg` = Volume Group name
* `#PV = 1` = one Physical Volume
* `#LV = 1` = one Logical Volume
* `VSize = 56.95 GB` = total pool size
* `VFree = 10.97 GB` = free space in the pool

---

# 13. Logical Volume (LV)

A **Logical Volume (LV)** is a portion of the Volume Group that has been allocated for use.

For example:

```text
ubuntu-vg

│

├── ubuntu-lv = 45.97 GB

│

└── Free = 10.97 GB
```

The Logical Volume behaves like a **block-storage device**.

A filesystem can then be created on it:

```text
ubuntu-lv

    ↓

Filesystem

    ↓

/
```

We can see Logical Volumes with:

```bash
lvs
```

Example:

```text
LV          VG          LSize
ubuntu-lv   ubuntu-vg   45.97g
```

The `45.97 GB` is therefore the size of the **Logical Volume**, not the size of the entire LVM pool.

## 13.1 How the Logical Volume Appears to Linux

An LVM Logical Volume is presented to the operating system as a **block device** through the Linux **device-mapper** subsystem.

For example:

```text
ubuntu-vg

└── ubuntu-lv
```

is represented as:

```text
/dev/mapper/ubuntu--vg-ubuntu--lv
```

This is similar to how a partition such as:

```text
/dev/sda1
```

appears as a block device.

However, there is an important difference:

```text
/dev/sda1
```

is a block device representing a **physical disk partition**.

While:

```text
/dev/mapper/ubuntu--vg-ubuntu--lv
```

is a **virtual block device** created by LVM through the device-mapper subsystem.

The filesystem is created on the Logical Volume, and that filesystem is then mounted at a directory.

For example:

```text
/dev/sda3
    ↓
Physical Volume (PV)
    ↓
ubuntu-vg
    ↓
ubuntu-lv
    ↓
/dev/mapper/ubuntu--vg-ubuntu--lv
    ↓
Filesystem
    ↓
/
```

Therefore:

```text
/dev/mapper/ubuntu--vg-ubuntu--lv = device
/                                   = mount point
```

The `/` directory is **not the Logical Volume itself**.

It is the **mount point** where the filesystem stored on the Logical Volume is made accessible.

For example, when we see this in `df -h`:

```text
Filesystem                         Size  Used  Avail  Use%  Mounted on
/dev/mapper/ubuntu--vg-ubuntu--lv  11G   8.1G  2.1G   80%   /
```

it means:

```text
Device:
    /dev/mapper/ubuntu--vg-ubuntu--lv

        ↓

Filesystem:
    filesystem created on the LV

        ↓

Mount Point:
    /
```

So the complete relationship is:

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
Device-mapper block device
    ↓
Filesystem
    ↓
Mount Point
    ↓
Files and Directories
```

---

# 14. PV → VG → LV

The three main LVM concepts can be remembered like this:

```text
PV → The physical storage given to LVM

VG → The storage pool

LV → A portion of that pool allocated for use
```

For example:

```text
/dev/sda3

    ↓

PV

    ↓

ubuntu-vg

    ↓

VG / Storage Pool

    │

    ├── ubuntu-lv = 45.97 GB

    │       ↓

    │   /dev/mapper/ubuntu--vg-ubuntu--lv

    │       ↓

    │   Filesystem

    │       ↓

    │       /

    │

    └── Free = 10.97 GB
```

This shows the important difference between the layers:

* `/dev/sda3` is the **partition**.
* The same storage is assigned to LVM as a **PV**.
* `ubuntu-vg` is the **LVM storage pool**.
* `ubuntu-lv` is storage allocated from that pool.
* `/dev/mapper/ubuntu--vg-ubuntu--lv` is the **block-device representation of the LV**.
* A **filesystem** exists on that LV.
* `/` is the **mount point** for that filesystem.

---
# 14. PV → VG → LV

The three main LVM concepts can be remembered like this:

```text
PV → The physical storage given to LVM

VG → The storage pool

LV → A portion of that pool allocated for use
```

For example:

```text
/dev/sda3
    ↓
PV
    ↓
ubuntu-vg
    ↓
VG / Storage Pool
    │
    ├── ubuntu-lv = 45.97 GB
    │
    └── Free = 10.97 GB
```

---

# 15. Our Ubuntu Server

Our Ubuntu server has this structure:

```text
/dev/sda = 60 GB
│
├── /dev/sda1 = 1 GB
│      ↓
│   /boot/efi
│
├── /dev/sda2 = 2 GB
│      ↓
│   /boot
│
└── /dev/sda3 = 56.95 GB
       ↓
      LVM
       ↓
    ubuntu-vg
       │
       ├── ubuntu-lv = 45.97 GB
       │       ↓
       │    Filesystem
       │       ↓
       │       /
       │
       └── Free = 10.97 GB
```

This means:

### `/dev/sda1`

A partition used for:

```text
/boot/efi
```

It is not part of our LVM.

### `/dev/sda2`

A partition used for:

```text
/boot
```

It is not part of our LVM.

### `/dev/sda3`

A partition used as an LVM Physical Volume.

It provides approximately:

```text
56.95 GB
```

to the LVM Volume Group.

### `ubuntu-vg`

The LVM storage pool.

It contains approximately:

```text
56.95 GB
```

of total storage.

### `ubuntu-lv`

A Logical Volume created from the pool.

It has:

```text
45.97 GB
```

allocated to it.

### Free LVM space

The Volume Group still has:

```text
10.97 GB
```

that has not been allocated to a Logical Volume.

---

# 16. Complete Storage Chain

Our server can therefore be represented as:

```text
Physical Disk
/dev/sda
     │
     ├── /dev/sda1
     │       ↓
     │   Filesystem
     │       ↓
     │   /boot/efi
     │
     ├── /dev/sda2
     │       ↓
     │   Filesystem
     │       ↓
     │   /boot
     │
     └── /dev/sda3
             ↓
       Physical Volume
             ↓
        Volume Group
        ubuntu-vg
             │
             ├── Logical Volume
             │   ubuntu-lv
             │       ↓
             │   Filesystem
             │       ↓
             │       /
             │
             └── Free LVM space
```

This is the most important diagram to understand.

---

# 17. Why LVM Is Useful

Suppose the Volume Group contains:

```text
56.95 GB
```

and we have:

```text
ubuntu-lv = 45.97 GB
Free      = 10.97 GB
```

We can later allocate some of the free LVM space to `ubuntu-lv`.

For example:

```text
Before:

ubuntu-vg
├── ubuntu-lv = 45.97 GB
└── Free = 10.97 GB
```

After allocating some of the free space:

```text
ubuntu-vg
├── ubuntu-lv = larger
└── Free = smaller
```

We can also create another Logical Volume from the free space.

For example:

```text
ubuntu-vg
├── ubuntu-lv = 45.97 GB
├── data-lv   = 5 GB
└── Free      = ~5.97 GB
```

This is the flexibility provided by LVM.

---

# 18. Adding More Physical Storage to LVM

LVM can use more than one Physical Volume.

For example:

```text
/dev/sda3 = 56.95 GB
        ↓
       PV
        │
        ├──────────────┐
                       │
/dev/sdb1 = 100 GB     │
        ↓              │
       PV              │
        └──────────────┤
                       ↓
                 Volume Group
                 ~156.95 GB
```

Both Physical Volumes can contribute storage to the same Volume Group.

The Volume Group then acts as one storage pool for allocating Logical Volumes.

---

# 19. Increasing Storage

There are several different layers that can be resized.

For example:

```text
Virtual Disk
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
Mount Point
```

Increasing the virtual disk does **not** automatically increase `/`.

Each relevant layer may need to be expanded.

For example:

```text
Increase VM disk
      ↓
Expand partition
      ↓
Expand LVM Physical Volume
      ↓
Volume Group has more free space
      ↓
Expand Logical Volume
      ↓
Expand filesystem
      ↓
/ can use the additional space
```

LVM makes the storage-management part more flexible because the Volume Group acts as a storage pool.

---

# 20. Useful Commands

### Show disks and partitions

```bash
lsblk
```

### Show disks, filesystems, and mount points

```bash
lsblk -f
```

### Show filesystem usage

```bash
df -h
```

### Show LVM Physical Volumes

```bash
pvs
```

### Show LVM Volume Groups

```bash
vgs
```

### Show LVM Logical Volumes

```bash
lvs
```

A useful sequence for understanding an Ubuntu server is:

```bash
lsblk -f
pvs
vgs
lvs
df -h
```

---

# 21. Simple Mental Model

The easiest way to remember everything is:

```text
DISK
  ↓
PARTITION
  ↓
  ├── Filesystem → Mount Point
  │
  └── LVM
       ↓
       PV
       ↓
       VG = Storage Pool
       ↓
       LV = Allocated Part
       ↓
       Filesystem
       ↓
       Mount Point
```

For the current server:

```text
/dev/sda
   │
   ├── sda1 → /boot/efi
   │
   ├── sda2 → /boot
   │
   └── sda3
        ↓
       PV
        ↓
    ubuntu-vg
        ↓
    ┌───────────────┐
    │               │
 ubuntu-lv       Free
 45.97 GB       10.97 GB
    │
    ↓
Filesystem
    │
    ↓
    /
```

## Key Definitions

| Term        | Meaning                                                   |
| ----------- | --------------------------------------------------------- |
| Disk        | Physical or virtual storage device, such as `/dev/sda`    |
| Partition   | A section of a disk, such as `/dev/sda3`                  |
| Filesystem  | Structure used to organize files and directories          |
| Mount Point | Directory where a filesystem is made accessible           |
| `/`         | Root of the Linux directory tree                          |
| PV          | Physical storage assigned to LVM                          |
| VG          | LVM storage pool                                          |
| LV          | Storage allocated from the VG                             |
| LVM         | Storage-management layer used to manage PVs, VGs, and LVs |

## Final Mental Model

> **A disk can be divided into partitions. A partition can contain a filesystem that is mounted at a directory. Alternatively, a partition can be given to LVM as a Physical Volume. LVM puts that storage into a Volume Group (storage pool), from which Logical Volumes are allocated. A filesystem is then created on the Logical Volume and mounted at a directory such as `/`.**
