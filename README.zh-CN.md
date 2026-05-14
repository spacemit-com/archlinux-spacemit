# ArchLinux RISC-V for SpacemiT K3

为 SpacemiT K3 平台构建 ArchLinux RISC-V 系统镜像的工具集。

[English](README.md)

## 项目结构

```bash
.
├── build_archlinux_k3.sh          # 主构建脚本
├── binutils-riscv64-unknown-elf/  # RISC-V 交叉编译工具链
├── gcc-riscv64-unknown-elf/       # RISC-V GCC 编译器
├── newlib/                        # C 标准库
├── opensbi-spacemit/              # OpenSBI 固件
├── u-boot-spacemit/               # U-Boot 引导加载器
├── esos-spacemit/                 # ESOS
├── mesa/                          # Mesa 3D 图形库
└── img-gpu-powervr/               # PowerVR GPU 驱动
```

## 快速开始

### 依赖安装

脚本会提示安装以下依赖：

- arch-install-scripts
- genimage
- parted, e2fsprogs, dosfstools
- qemu-user-static, binfmt-support

```bash
./build_archlinux_k3.sh
```

首次运行时选择 `y` 安装依赖。

### 构建流程

脚本自动完成：

1. 下载 ArchLinux RISC-V rootfs
2. 解压并配置基础系统
3. 安装 SpacemiT 专用软件包
4. 配置内核和设备树
5. 生成 bootfs 和 rootfs 分区
6. 打包为可烧录的 SD 卡镜像（可选）
7. 打包为可烧录的 tar.gz 镜像（使用 Titan 工具烧录）

### 断点续执

构建脚本支持断点续执。如果脚本中途退出（如 `pacman -S` 失败），重新运行即可——已完成的阶段会自动跳过。断点文件存储在 `$WORK_DIR/.build_checkpoints/`，构建全部成功后自动清理。

### 环境变量

可通过环境变量自定义构建：

```bash
WORK_DIR=$HOME/build \
BOOTFS_SIZE_MB=512 \
ROOTFS_SIZE_MB=16384 \
./build_archlinux_k3.sh
```

- `WORK_DIR`: 工作目录（默认 `~/riscv-img-build`）
- `PKG_DIR`: 本地包目录（默认 `$WORK_DIR/pkgs`）
- `BOOTFS_SIZE_MB`: boot 分区大小（默认 256MB）
- `ROOTFS_SIZE_MB`: root 分区大小（默认 8192MB）

## 软件包构建（可选）

如需自定义软件包，可提前构建并放入 `$PKG_DIR`（默认 `$WORK_DIR/pkgs`），脚本会自动安装到镜像中。

构建流程：

1. 进入 chroot 环境：`arch-chroot $WORK_DIR/mnt/root`
2. 编译所需的 pkg 包。

### 内核

```bash
pacman -Syu --needed \
    bc bison flex gettext kmod \
    libelf openssl pahole perl python rsync tar

cd $linux_kernel_dir
make defconfig
make pacman-pkg
```

### 交叉编译工具链

```bash
cd binutils-riscv64-unknown-elf && makepkg -si
cd gcc-riscv64-unknown-elf && makepkg -si
cd newlib && makepkg -si
```

### 固件和引导

```bash
cd opensbi-spacemit && makepkg -si
cd u-boot-spacemit && makepkg -si
cd esos-spacemit && makepkg -si
```

### 图形驱动

```bash
cd mesa && makepkg -si
cd img-gpu-powervr && makepkg -si
```

构建完成后将生成的 `.pkg.tar.zst` 文件复制到 `$PKG_DIR` 目录。

## 输出镜像

构建完成后生成：

```bash
$WORK_DIR/archlinux-riscv.sdcard
```

使用 `dd` 烧录到 SD 卡：

```bash
sudo dd if=archlinux-riscv.sdcard of=/dev/sdX bs=4M status=progress
sync
```

## 默认配置

- 用户名: `root`
- 密码: `root`
- 网络: NetworkManager（已启用）
- 内核: linux-6.18
- 图形: Mesa + PowerVR 驱动

## 注意事项

- 需要 root 权限执行 chroot 和镜像操作
- 首次构建约需下载 1GB+ 数据
- 确保磁盘空间充足（至少 15GB）
- 本地包需提前构建并放入 `$PKG_DIR`
