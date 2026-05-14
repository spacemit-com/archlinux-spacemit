#!/bin/bash
# ArchLinux RISC-V Image Build Script (genimage method)

set -e

# ========== Checkpoint Infrastructure ==========
# Resolved after WORK_DIR is set; uses absolute path to avoid cwd issues
_CHECKPOINT_DIR=""
_checkpoint_init() {
  _CHECKPOINT_DIR="$WORK_DIR/.build_checkpoints"
  mkdir -p "$_CHECKPOINT_DIR"
}

checkpoint_done() {
  [ -f "$_CHECKPOINT_DIR/stage_$1" ]
}

checkpoint_mark() {
  touch "$_CHECKPOINT_DIR/stage_$1"
}

# ========== Install Dependencies ==========
read -r -p "Install/update dependencies (arch-install-scripts, genimage, etc.)? [y/N] " INSTALL_DEPS
if [[ ! "$INSTALL_DEPS" =~ ^[Yy]$ ]]; then
  echo "Skipped dependency installation."
else
  echo "=== Installing dependencies ==="
  sudo apt-get update
  sudo apt-get install -y \
  parted util-linux e2fsprogs dosfstools \
  arch-install-scripts rsync wget curl pigz \
  qemu-user-static binfmt-support uuid-runtime genimage
fi

# ========== Configuration ==========
WORK_DIR=${WORK_DIR:-$HOME/riscv-img-build}
PKG_DIR=${PKG_DIR:-$WORK_DIR/pkgs}
ROOTFS_TAR=${ROOTFS_TAR:-archriscv-latest.tar.zst}
IMG_NAME="archlinux-riscv"
BOOTFS_SIZE_MB=${BOOTFS_SIZE_MB:-256}
ROOTFS_SIZE_MB=${ROOTFS_SIZE_MB:-8192}
ROOT_PASSWORD="root"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ========== 1. Prepare Working Directory ==========
echo "=== Preparing working directory ==="
mkdir -p $WORK_DIR/{rootfs,mnt/{boot,root},pack_dir/factory,bootfs}
cd $WORK_DIR
_checkpoint_init

# ========== 2. Download & Extract rootfs ==========
if checkpoint_done 2; then
  echo "=== [SKIP] Stage 2: rootfs already downloaded & extracted ==="
else
  echo "=== Downloading ArchRISCV rootfs ==="
  if [ -f "$ROOTFS_TAR" ]; then
    read -r -p "rootfs tarball already exists, re-download and overwrite? [y/N] " REFETCH_ROOTFS
    if [[ "$REFETCH_ROOTFS" =~ ^[Yy]$ ]]; then
      wget -O "$ROOTFS_TAR" https://archriscv.felixc.at/images/archriscv-latest.tar.zst
    fi
  else
    wget -O "$ROOTFS_TAR" https://archriscv.felixc.at/images/archriscv-latest.tar.zst
  fi

  if [ -d mnt/root ] && [ -n "$(ls -A mnt/root 2>/dev/null)" ]; then
    read -r -p "mnt/root is not empty, extract and overwrite existing content? [y/N] " OVERWRITE_ROOTFS
    if [[ "$OVERWRITE_ROOTFS" =~ ^[Yy]$ ]]; then
      sudo tar -xf "$ROOTFS_TAR" -C mnt/root --strip-components=1
    else
      echo "Skipped extraction, using existing content."
    fi
  else
    sudo tar -xf "$ROOTFS_TAR" -C mnt/root --strip-components=1
  fi
  checkpoint_mark 2
fi

# ========== 3. Install Local Packages & Chroot ==========
if checkpoint_done 3; then
  echo "=== [SKIP] Stage 3: chroot package installation already done ==="
else
  read -r -p "Install local .pkg.tar.zst packages from $PKG_DIR? [y/N] " INSTALL_PKGS
  if [[ ! "$INSTALL_PKGS" =~ ^[Yy]$ ]]; then
    echo "Skipped local package installation."
  else
    echo "=== Copying local packages ==="
    sudo mkdir -p mnt/root/pkgs
    sudo cp -a $PKG_DIR/*.pkg.tar.zst mnt/root/pkgs/
  fi

  # Avoid duplicate [spacemit] section
  if ! grep -q '^\[spacemit\]' mnt/root/etc/pacman.conf; then
  sudo tee -a mnt/root/etc/pacman.conf << 'EOF'

[spacemit]
SigLevel = Optional TrustAll
Server = http://159.27.188.198/archlinux/spacemit/
EOF
  fi

  # Bind mount rootfs for chroot
  mountpoint -q mnt/root      || sudo mount --bind mnt/root mnt/root
  mountpoint -q mnt/root/proc || sudo mount -t proc /proc mnt/root/proc
  mountpoint -q mnt/root/sys  || sudo mount -t sysfs /sys mnt/root/sys
  mountpoint -q mnt/root/dev  || sudo mount -o bind /dev mnt/root/dev
  mountpoint -q mnt/root/dev/pts || sudo mount -o bind /dev/pts mnt/root/dev/pts


  sudo ROOT_PASSWORD="$ROOT_PASSWORD" chroot mnt/root /bin/bash << CHROOT_EOF
set -e
if [ -n "${ROOT_PASSWORD:-}" ]; then
  echo "root:${ROOT_PASSWORD}" | chpasswd
else
  passwd root
fi
pacman-key --init
pacman-key --populate archlinux

cat > /etc/resolv.conf << 'RESOLV_EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
options timeout:2 attempts:1
RESOLV_EOF

update-ca-trust
pacman -Syy

pacman -S --noconfirm --overwrite "*" networkmanager systemd-sysvcompat systemd

# Remove packages conflicting with linux-spacemit series
pacman -Rdd --noconfirm linux-api-headers 2>/dev/null || true

if [ -d /pkgs ] && [ -n "\$(ls -A /pkgs 2>/dev/null)" ]; then
pacman -U --noconfirm /pkgs/*.pkg.tar.zst
rm -rf /pkgs
fi

pacman -S --noconfirm \
  esos-spacemit \
  linux-firmware-spacemit \
  linux-spacemit \
  linux-spacemit-api-headers \
  linux-spacemit-headers \
  opensbi-spacemit \
  u-boot-spacemit \
  u-boot-tools \
  mesa=1:24.0.1-1 vulkan-mesa-layers=1:24.0.1-1 \
  img-gpu-powervr

if [ -f /usr/share/factory/etc/vconsole.conf ]; then
  cp /usr/share/factory/etc/vconsole.conf /etc/vconsole.conf
fi

if [ -f /usr/lib/modules/*/vmlinuz* ]; then
  cp -rf /usr/lib/modules/*/vmlinuz* /boot/
fi

systemctl enable NetworkManager
CHROOT_EOF

  sleep 1
  sudo umount -lf mnt/root/proc || true
  sudo umount -lf mnt/root/sys || true
  sudo umount -lf mnt/root/dev/pts || true
  sudo umount -lf mnt/root/dev || true
  sudo umount -lf mnt/root
  sleep 2
  checkpoint_mark 3
fi

# ========== 4. Install Reference initramfs ==========
if checkpoint_done 4; then
  echo "=== [SKIP] Stage 4: initramfs & kernel copy already done ==="
else
  echo "=== Installing reference initramfs ==="
  REF_INITRAMFS="$SCRIPT_DIR/initramfs-linux-spacemit.img"
  if [ ! -f "$REF_INITRAMFS" ]; then
    echo "ERROR: Reference initramfs not found: $REF_INITRAMFS"
    echo "Please place the verified initramfs in the same directory as this script."
    exit 1
  fi
  sudo cp "$REF_INITRAMFS" mnt/root/boot/initramfs-linux-spacemit.img
  # Create generic symlink (u-boot env may reference this name)
  sudo ln -sf initramfs-linux-spacemit.img mnt/root/boot/initramfs-generic.img

  # ========== 5. Copy Kernel and Device Trees ==========
  echo "=== Copying kernel and device trees ==="
  sudo cp -a mnt/root/boot/* mnt/boot/
  sudo cp -rf mnt/root/usr/lib/modules/*/dtb/spacemit mnt/root/boot/ 2>/dev/null || true
  checkpoint_mark 4
fi

# ========== 6. Generate fstab & bootfs/rootfs Images ==========
if checkpoint_done 6; then
  echo "=== [SKIP] Stage 6: bootfs/rootfs images already generated ==="
else
  echo "=== Generating bootfs/rootfs images ==="
  UUID_BOOTFS=$(uuidgen)
  UUID_ROOTFS=$(uuidgen)

  cat > mnt/root/etc/fstab <<EOF
# <file system>     <dir>    <type>  <options>                          <dump> <pass>
UUID=$UUID_ROOTFS   /        ext4    defaults,noatime,errors=remount-ro 0      1
UUID=$UUID_BOOTFS   /boot    ext4    defaults                           0      2
EOF

  sudo rsync -aHAX mnt/root/boot/ $WORK_DIR/bootfs/

  KERNEL_IMG=$(ls $WORK_DIR/bootfs/vmlinuz* | head -n1 | xargs -n1 basename)
  RAMDISK_IMG=$(ls $WORK_DIR/bootfs/initramfs-*.img | head -n1 | xargs -n1 basename)
  DTB_DIR=$(ls -d $WORK_DIR/bootfs/spacemit 2>/dev/null | xargs -n1 basename)

  cat > $WORK_DIR/bootfs/env_k3.txt <<EOF
knl_name=${KERNEL_IMG}
ramdisk_name=${RAMDISK_IMG}
dtb_dir=${DTB_DIR}
ramdisk_addr=0x130000000
loglevel=8
commonargs=setenv bootargs clk_ignore_unused nohlt plymouth.prefer-fbcon plymouth.ignore-serial-consoles splash
EOF

  sudo mke2fs -d $WORK_DIR/bootfs -L bootfs -t ext4 -U $UUID_BOOTFS $WORK_DIR/bootfs.ext4 "${BOOTFS_SIZE_MB}M"
  sudo mke2fs -d mnt/root -L rootfs -t ext4 -N 524288 -U $UUID_ROOTFS $WORK_DIR/rootfs.ext4 "${ROOTFS_SIZE_MB}M"
  checkpoint_mark 6
fi

# ========== 7. Prepare Firmware Files ==========
if checkpoint_done 7; then
  echo "=== [SKIP] Stage 7: firmware files already prepared ==="
else
  echo "=== Preparing firmware files ==="
  TMP=pack_dir
  sudo cp mnt/root/usr/lib/u-boot/spacemit/*.bin $TMP/factory/ 2>/dev/null || true
  sudo cp mnt/root/usr/lib/u-boot/spacemit/{u-boot.itb,env.bin} $TMP/ 2>/dev/null || true
  sudo cp mnt/root/usr/lib/esos/esos.itb $TMP/ 2>/dev/null || true
  sudo cp mnt/root/usr/lib/opensbi/spacemit/fw_dynamic.itb $TMP/ 2>/dev/null \
    || sudo cp mnt/root/usr/lib/riscv64-linux-gnu/opensbi/generic/fw_dynamic.itb $TMP/
  sudo cp $WORK_DIR/bootfs.ext4 $WORK_DIR/rootfs.ext4 $TMP/
  checkpoint_mark 7
fi

# ========== 8. Copy Partition Tables & Generate genimage Config ==========
if checkpoint_done 8; then
  echo "=== [SKIP] Stage 8: partition tables already set up ==="
else
  echo "=== Setting up partition tables ==="
  TMP=pack_dir
  cp "$SCRIPT_DIR/templates/partition_4M.json" "$TMP/"
  cp "$SCRIPT_DIR/templates/partition_flash.json" "$TMP/"
  cp "$SCRIPT_DIR/templates/partition_universal.json" "$TMP/"
  cp "$SCRIPT_DIR/templates/gen_imgcfg.py" "$TMP/"

  python3 $TMP/gen_imgcfg.py -i $TMP/partition_universal.json -n $IMG_NAME.sdcard -o $TMP/genimage.cfg
  checkpoint_mark 8
fi

# ========== 9. Generate SD Card Image (Optional) ==========
if checkpoint_done 9; then
  echo "=== [SKIP] Stage 9: SD card image already generated ==="
else
  TMP=pack_dir
  read -r -p "Generate SD card image (.sdcard)? [y/N] " BUILD_SDCARD
  if [[ "$BUILD_SDCARD" =~ ^[Yy]$ ]]; then
    echo "=== Generating SD card image ==="
    ROOTPATH_TMP=$(mktemp -d)
    GENIMAGE_TMP=$(mktemp -d)
    genimage --config "$TMP/genimage.cfg" \
      --rootpath "$ROOTPATH_TMP" \
      --tmppath "$GENIMAGE_TMP" \
      --inputpath "$TMP" \
      --outputpath "."

    rm -rf $ROOTPATH_TMP $GENIMAGE_TMP

    echo "=== SD card image generated ==="
    ls -lh $IMG_NAME.sdcard
    echo "Image path: $WORK_DIR/$IMG_NAME.sdcard"
  else
    echo "Skipped SD card image generation."
  fi
  checkpoint_mark 9
fi

# ========== 10. Generate tar.gz Fastboot Package ==========
if checkpoint_done 10; then
  echo "=== [SKIP] Stage 10: tar.gz fastboot package already generated ==="
else
  TMP=pack_dir
  echo "=== Generating tar.gz fastboot package ==="
  TIMESTAMP=$(date +%Y%m%d%H%M%S)
  TARBALL_DIR="ArchLinux-K3-${TIMESTAMP}"
  TARBALL_PATH="$WORK_DIR/$TARBALL_DIR"

  mkdir -p "$TARBALL_PATH/factory"

  # Copy firmware files
  cp -a $TMP/factory/* "$TARBALL_PATH/factory/"
  cp -a $TMP/env.bin "$TARBALL_PATH/" 2>/dev/null || true
  cp -a $TMP/esos.itb "$TARBALL_PATH/"
  cp -a $TMP/fw_dynamic.itb "$TARBALL_PATH/"
  cp -a $TMP/u-boot.itb "$TARBALL_PATH/"

  # Copy partition images
  cp -a $TMP/bootfs.ext4 "$TARBALL_PATH/"
  cp -a $TMP/rootfs.ext4 "$TARBALL_PATH/"

  # Copy partition table JSONs
  cp -a $TMP/partition_*.json "$TARBALL_PATH/"

  # Copy genimage.cfg
  cp -a $TMP/genimage.cfg "$TARBALL_PATH/" 2>/dev/null || true

  # Copy fastboot.yaml from templates
  cp "$SCRIPT_DIR/templates/fastboot.yaml" "$TARBALL_PATH/"

  # Create tarball
  cd "$WORK_DIR"
  tar -I pigz -cf "${TARBALL_DIR}.tar.gz" "$TARBALL_DIR"
  rm -rf "$TARBALL_PATH"

  echo "=== tar.gz fastboot package generated ==="
  ls -lh "$WORK_DIR/${TARBALL_DIR}.tar.gz"
  echo "Package path: $WORK_DIR/${TARBALL_DIR}.tar.gz"
  checkpoint_mark 10
fi

# ========== All Done — Clean Checkpoints ==========
echo ""
echo "=== Build completed successfully! Cleaning checkpoints... ==="
rm -rf "$_CHECKPOINT_DIR"
echo "Done."
