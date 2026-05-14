# ArchLinux RISC-V for SpacemiT K3

Toolset for building ArchLinux RISC-V system images for the SpacemiT K3 platform.

[中文文档](README.zh-CN.md)

## Project Structure

```bash
.
├── build_archlinux_k3.sh          # Main build script
├── binutils-riscv64-unknown-elf/  # RISC-V cross binutils
├── gcc-riscv64-unknown-elf/       # RISC-V GCC compiler
├── newlib/                        # C standard library
├── opensbi-spacemit/              # OpenSBI firmware
├── u-boot-spacemit/               # U-Boot bootloader
├── esos-spacemit/                 # ESOS
├── mesa/                          # Mesa 3D graphics library
└── img-gpu-powervr/               # PowerVR GPU driver
```

## Quick Start

### Dependencies

The script will prompt to install the following dependencies:

- arch-install-scripts
- genimage
- parted, e2fsprogs, dosfstools
- qemu-user-static, binfmt-support

```bash
./build_archlinux_k3.sh
```

Select `y` on first run to install dependencies.

### Build Process

The script automatically performs:

1. Download ArchLinux RISC-V rootfs
2. Extract and configure the base system
3. Install SpacemiT-specific packages
4. Configure kernel and device trees
5. Generate bootfs and rootfs partitions
6. Package as a flashable SD card image (optional)
7. Package as a flashable tar.gz archive (flash via Titan tool)

### Checkpoint / Resume

The build script supports checkpoint-based resumption. If the script exits mid-way (e.g. `pacman -S` fails), simply re-run it — completed stages are skipped automatically. Checkpoints are stored in `$WORK_DIR/.build_checkpoints/` and cleaned up after a successful full build.

### Environment Variables

Customize the build via environment variables:

```bash
WORK_DIR=$HOME/build \
BOOTFS_SIZE_MB=512 \
ROOTFS_SIZE_MB=16384 \
./build_archlinux_k3.sh
```

- `WORK_DIR`: Working directory (default: `~/riscv-img-build`)
- `PKG_DIR`: Local packages directory (default: `$WORK_DIR/pkgs`)
- `BOOTFS_SIZE_MB`: Boot partition size (default: 256MB)
- `ROOTFS_SIZE_MB`: Root partition size (default: 8192MB)

## Building Packages (Optional)

To use custom packages, build them in advance and place them in `$PKG_DIR` (default: `$WORK_DIR/pkgs`). The script will install them into the image automatically.

Build workflow:

1. Enter the chroot environment: `arch-chroot $WORK_DIR/mnt/root`
2. Build the required packages.

### Kernel

```bash
pacman -Syu --needed \
    bc bison flex gettext kmod \
    libelf openssl pahole perl python rsync tar

cd $linux_kernel_dir
make defconfig
make pacman-pkg
```

### Cross Toolchain

```bash
cd binutils-riscv64-unknown-elf && makepkg -si
cd gcc-riscv64-unknown-elf && makepkg -si
cd newlib && makepkg -si
```

### Firmware and Bootloader

```bash
cd opensbi-spacemit && makepkg -si
cd u-boot-spacemit && makepkg -si
cd esos-spacemit && makepkg -si
```

### Graphics Driver

```bash
cd mesa && makepkg -si
cd img-gpu-powervr && makepkg -si
```

After building, copy the generated `.pkg.tar.zst` files to the `$PKG_DIR` directory.

## Output Image

After a successful build:

```bash
$WORK_DIR/archlinux-riscv.sdcard
```

Flash to SD card with `dd`:

```bash
sudo dd if=archlinux-riscv.sdcard of=/dev/sdX bs=4M status=progress
sync
```

## Default Configuration

- Username: `root`
- Password: `root`
- Network: NetworkManager (enabled)
- Kernel: linux-6.18
- Graphics: Mesa + PowerVR driver

## Notes

- Requires root privileges for chroot and image operations
- First build downloads ~1GB+ of data
- Ensure sufficient disk space (at least 15GB)
- Local packages must be pre-built and placed in `$PKG_DIR`
