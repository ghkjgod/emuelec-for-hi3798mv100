# 在 EC6108V9C 上运行 EmuELEC

这个项目把 EmuELEC 游戏前端移植到使用海思 Hi3798MV100 芯片的华为
EC6108V9C 机顶盒。它适合愿意折腾旧盒子的玩家，也保留了开发者继续修改
模拟器、系统和固件所需的完整构建入口。

先说最重要的几件事：

- **支持的盒子**：目前只针对已经实机验证的 EC6108V9C / Hi3798MV100、
  1 GiB 内存、既定九分区布局。外观相似、芯片或分区不同的盒子不能直接套用。
- **最后能生成什么**：一个可构建进 p9 的 EmuELEC `rootfs` 分区镜像、应用
  发布包、构建日志和校验文件。仓库本身不提供可盲刷任意盒子的完整固件。
- **普通玩家能做什么**：在电视上用 EmulationStation 浏览游戏，通过
  RetroArch 和 10 个已移植核心运行自己合法持有的游戏；游戏、BIOS 和经过
  校验的核心可以放在 TF 卡上。
- **大约需要多少资源**：最低预留 40 GiB，建议 50 GiB 以上；普通电脑完整
  构建大约 1–3 小时，首次下载速度和 CPU/磁盘性能会明显影响时间。
- **仓库不提供什么**：商业 ROM、版权不明的主机 BIOS、本机专用的 p1–p8
  分区数据、设备备份、HiBurn 工具、测试机密码或完整刷机包。

如果你第一次接触这些名词，不必先学会它们。按下一节构建即可，遇到术语再看
[名词解释](#名词解释)。

需要从源码一键得到官方 HiBurn 可写入的 p9/rootfs 镜像时，在 Linux ext4
工作区运行：

```bash
./build-flash-image.sh
```

脚本会完成固定源码准备、完整构建、ABI/依赖/文件系统/发布内容审计，并把
最终 `.img`、SHA-256 和写入边界放到 `artifacts/flash/`，同时生成可复制的
`artifacts/tf-card/`。该文件只用于合格的
EC6108V9C 九分区布局中 **p9/rootfs-only** 写入，不是整盘镜像，也不能写入
p1–p8、分区表、boot0、boot1 或 RPMB。

## 第一层：普通玩家

### 已经有别人为你的同型号盒子制作好的合格镜像

1. 确认镜像明确写着适用于 **EC6108V9C / Hi3798MV100 和相同分区布局**。
2. 保存盒子原有分区的可恢复备份。
3. 不要把本仓库生成的 p9 文件当作整盘镜像，也不要猜测写入地址。
4. 把仓库的 `tf-card/EmuELEC` 复制到卡根目录，再按
   [TF 卡使用说明](docs/TF-CARD.md) 添加自己合法持有的游戏和 BIOS。

本仓库故意不包含通用“一键刷机”。p1–p8 中有启动、内核、恢复和板级数据，
它们必须来自用户自己合法持有、同型号同布局并校验过的备份。

### TF 卡目录

推荐把卡标记为 `EMUELEC`，并使用下面的结构：

```text
EmuELEC/
├── roms/
│   ├── nes/
│   ├── snes/
│   ├── gb/
│   ├── gba/
│   ├── megadrive/
│   ├── pce/
│   ├── psx/
│   ├── arcade/
│   ├── fbneo/
│   ├── mame/
│   ├── pgm2/
│   ├── nesh/
│   └── famicom/
├── bios/
├── cores/
│   └── cores.sha256
├── config/
│   ├── gamecontrollerdb.txt
│   └── gamecontrollerdb.sha256
└── licenses/
```

系统不会格式化卡，也不会修改分区表。它优先按配置的 UUID 或标签找到卡；未
配置时，只接受内核明确识别为外置 SD 的唯一分区，绝不会把内置 eMMC 当作
TF 卡。卡不存在或损坏时，盒子仍能使用 rootfs 内置的前端、核心和手柄数据库
正常启动；仓库本身不承诺附带任何游戏。

ext4 卡上的兼容核心可以在 SHA-256、ARM softfp 和目标机动态加载检查通过后
直接加载。FAT32/exFAT 卡使用 `noexec` 挂载，核心会复制到内置的内容寻址缓存
后再加载；日志会明确写 `direct-tf`、`tf-cache` 或 `builtin`，不会把缓存加载
说成直接从 TF 执行。完整规则、拔卡保护和故障提示见
[docs/TF-CARD.md](docs/TF-CARD.md)。

## 第二层：想自己编译

### Linux：整段复制

下面以 Ubuntu/Debian 为例。仓库必须放在 Linux 的 ext4 文件系统中。

```bash
sudo apt update
sudo apt install -y \
  build-essential git patch make ninja-build cmake pkg-config \
  python3 perl gawk bison flex gettext texinfo autoconf automake libtool \
  rsync file bc curl wget libncurses-dev \
  tar gzip bzip2 xz-utils unzip e2fsprogs zlib1g-dev libssl-dev openssl \
  libc6-i386 lib32z1

cd ~
git clone --recurse-submodules --shallow-submodules \
  https://github.com/ghkjgod/emuelec-for-hi3798mv100.git
cd emuelec-for-hi3798mv100
./easy-build.sh
```

`easy-build.sh` 会先检查依赖、文件系统、剩余空间、锁定文件和仓库完整性，再
准备固定版本的 SDK/EmuELEC、校验下载缓存并执行完整构建。检查失败时会同时
告诉你失败原因和下一条该运行的命令。

只检查电脑而不下载或构建：

```bash
./easy-build.sh --check
```

只准备源码，暂不开始长时间构建：

```bash
./easy-build.sh --setup-only
```

### Windows：打开 WSL 的 Ubuntu 终端，然后粘贴

先从 Microsoft Store 安装 Ubuntu/WSL2。打开开始菜单里的 **Ubuntu**，不要
在 PowerShell 或 CMD 中运行下面命令，也不要把仓库放进 `/mnt/c`、`/mnt/d`
或 `/mnt/e`。

```bash
sudo apt update
sudo apt install -y \
  build-essential git patch make ninja-build cmake pkg-config \
  python3 perl gawk bison flex gettext texinfo autoconf automake libtool \
  rsync file bc curl wget libncurses-dev \
  tar gzip bzip2 xz-utils unzip e2fsprogs zlib1g-dev libssl-dev openssl \
  libc6-i386 lib32z1

cd ~
git clone --recurse-submodules --shallow-submodules \
  https://github.com/ghkjgod/emuelec-for-hi3798mv100.git
cd emuelec-for-hi3798mv100
./easy-build.sh
```

`cd ~` 会进入 WSL 自己的 Linux 磁盘，脚本会确认它确实是 ext4。SDK 包含只差
大小写的文件、Unix 权限和软链接，Windows 的普通 NTFS 目录无法可靠保存它们。

### 不能使用 Git 时：Download ZIP

GitHub 页面上的 **Code → Download ZIP** 不包含两个子模块。把 ZIP 完整解压到
ext4 后运行 `./easy-build.sh`；引导脚本会根据 `WORKSPACE.lock` 自动克隆固定
版本。ZIP 是备用方式，首选仍是 `git clone --recurse-submodules`，因为更容易
检查源码身份和更新。

### 核心构建与 TF 成品目录

首次构建直接运行 `./easy-build.sh` 或 `./build-flash-image.sh`。完整流程会从
`SOURCES.lock` 下载并校验固定源码，使用 Hi3798MV100 BSP 工具链重新构建 10 个
ARMv7 EABI5 softfp 核心；不会把 S905 镜像中的 AArch64/hard-float 核心混入。
SNES 只构建 Snes9x 2010，不构建 Snes9x 2005。

已经成功完成过一次完整 SDK 构建后，可以只重建核心和 TF 包：

```bash
HISTB_JOBS=4 ./emuelec/tools/histb/build-libretro-cores.sh
./emuelec/tools/histb/stage-runtime.sh
./emuelec/tools/histb/package-tf-card.sh
```

每个核心在进入包前都必须通过 32 位 ARM、EABI5、softfp、GLIBC 版本、动态依赖
和 libretro 入口符号检查。构建生成的可复制目录是 `artifacts/tf-card/`；仓库
还提交了一份同结构的已验证快照 `tf-card/`。二者都只含核心、校验清单、手柄
数据库和许可证，不含 BIOS 或 ROM。复制 `EmuELEC` 文件夹到卡根目录，再补充
自己合法持有的 `EmuELEC/bios/` 与 `EmuELEC/roms/` 即可。

### 构建成功后去哪里找

| 内容 | 路径 |
|---|---|
| p9 sparse rootfs | `sdk/out/hi3798mv100/hi3798mdmo1g/image/emmc_image/rootfs_6846M.ext4` |
| HiBurn 用带版本 p9 镜像 | `artifacts/flash/*-p9-rootfs.img` |
| 可直接复制到 TF 的核心/手柄资源 | `artifacts/tf-card/` |
| 应用发布包、哈希和审计 | `artifacts/` |
| 完整构建日志 | `logs/histb-emuelec-build-all.log` |
| 下载缓存 | `cache/sources/` |

`rootfs_6846M.ext4` 是 Android sparse 格式的 **单个 p9 分区镜像**，不是整盘
ROM。构建成功只证明源码和镜像门禁通过，不等于你的盒子已经完成真机验收。

## 第三层：开发者

### 固定源码

| 组成 | 固定提交 | 说明 |
|---|---|---|
| HiSTBLinux SDK/BSP | `fd20f78ab02934e71474dbb1d933c6ec911b01c9` | `sdk/` 子模块 |
| EmuELEC | `65b3db37ebdca93d543b7e7b3d5df4a2c9ceee79` | `emuelec/` 子模块 |
| 本移植 | 当前仓库 `port/` | 原创胶水为 0BSD；衍生补丁保留上游许可 |

精确 URL、commit 和板级配置哈希在 `WORKSPACE.lock`，29 个第三方源码归档的
URL/SHA-256 在 `SOURCES.lock`。`bootstrap-workspace.sh` 把 `port/` 同步为
`emuelec/tools/histb/` 的受管副本，普通用户无需手工复制或猜 SDK 版本。

### 目录

```text
emuelec-for-hi3798mv100/
├── easy-build.sh        # 玩家入口
├── build-flash-image.sh # 一键生成经审计的 p9/rootfs 烧录镜像
├── tf-card/             # 已验证 TF 成品树；明确不含 BIOS/ROM
├── sdk/                 # 固定 HiSTBLinux SDK 子模块
├── emuelec/             # 固定 EmuELEC 子模块
├── port/                # 移植源码、补丁、目标脚本和测试
├── scripts/             # bootstrap、下载和完整构建
├── docs/                # TF 卡、SDK 和边界说明
├── WORKSPACE.lock
├── SOURCES.lock
├── artifacts/           # 构建生成，Git 忽略
├── build/               # 构建中间目录，Git 忽略
├── cache/sources/       # 固定下载缓存，Git 忽略
└── logs/                # 构建日志，Git 忽略
```

### 构建过程和目标平台

完整入口先构建厂商 SDK，再执行移植层 13 个阶段：SDK 集成、Dropbear、
GLES2、GLES1、SDL2、RetroArch、10 个核心、EmulationStation、运行时
暂存与 TF 成品打包、rootbox 合成、p9 ext4、镜像规范化，以及 ABI/依赖/发布
内容审计。任一
阶段失败都会停止，不会把半成品报告为成功。

目标是 ARMv7 EABI5 softfp、Cortex-A7、VFPv3-D16，动态加载器为
`/lib/ld-linux.so.3`。图形使用厂商 Mali-450 fbdev EGL/GLES，不是
X11、Wayland、DRM 或 Mesa；声音走 ALSA → HDMI。

已有完整 SDK 输出时可跳过最耗时的 SDK 重建，但仍会验证固定版本：

```bash
HISTB_SKIP_SDK_BUILD=1 ./scripts/build-workspace.sh
```

### 已移植核心

| 系统 | 核心 | 固定提交 | rc177 真机状态 |
|---|---|---|---|
| NES | FCEUmm | `236ccdfc911e84c60fea6b9d0699c2d440a8de14` | 装载/ABI 与 S905 来源真实 ROM 运行 PASS |
| SNES | Snes9x 2010 | `7db129b1ecdccb38cb4d7184bcbed39beed79656` | 唯一 SNES 核心；不构建 Snes9x 2005；装载/ABI 与 S905 来源真实 ROM 运行 PASS |
| GB/GBC | Gambatte | `d9d6cd06382d1ced30de34d56d3609452323dab1` | 装载/ABI 与无 TF 内置回退 PASS；S905 参考镜像没有对应 ROM，游戏运行 NOT RUN |
| GBA | gpSP / mGBA | `8d268a6bb2cd799f8f2791ebb544a7ef550cfc6f` / `c65e8a3d4666b0ea68a01578232452f31b185332` | 两者装载/ABI 与无 TF 内置回退 PASS；S905 参考镜像没有对应 ROM，游戏运行 NOT RUN |
| Mega Drive / SMS / CD / 32X | PicoDrive | `733c711a477a642fd2006d5a7a581b2790ec36b4` | 装载/ABI 与 S905 来源真实 ROM 运行 PASS |
| PC Engine | Beetle PCE Fast | `2f623abd033257b969370b73d9da982dcb0c3fdd` | 装载/ABI 与无 TF 内置回退 PASS；S905 参考镜像没有对应 ROM，游戏运行 NOT RUN |
| PlayStation | PCSX-ReARMed | `ba61a4fdee1f789e8012f205f1b63826667644fa` | 装载/ABI 与无 TF 内置回退 PASS；S905 参考镜像没有对应 ROM，游戏运行 NOT RUN |
| Arcade | FinalBurn Neo / MAME 2003-Plus | `26f11fa9e43227a04953e20e8c7e4bf322cd53cb` / `21256d24120b04916c5197d95b757635ca880fd9` | 两者装载/ABI 与 S905 来源真实 ROM 运行 PASS；FBNeo 实际读取 S905 BIOS 树中的 NeoGeo BIOS |

2026-08-31 已通过各项目的官方 Git 仓库实时核对上述 10 个提交；它们当时均与
各自默认分支 `HEAD` 完全一致。构建仍按 `SOURCES.lock` 固定提交和归档哈希，
不会因为上游以后移动而悄悄改变输出。

上述结论只绑定 recipe
`c177549bce127f3200d3bc9e0ec8b1701d04023c32c240b3177bfaa9a1938eac`。
核心更新后必须重新做源码哈希、ARM softfp ABI、依赖、rootfs、可复现构建和
真机画面/声音/输入/退出验证；没有对应测试 ROM 的平台不能从装载测试推断游戏兼容性。

### 网络与开发登录

公开构建默认启用 `eth0` DHCP 和 Dropbear SSH，开发账号为
`root` / `emuelec`。这是公开密码，只能用于可信隔离网络；首次登录后运行
`passwd`，或在构建前提供自己的密码哈希/SSH 公钥：

```bash
export HISTB_ROOT_AUTHORIZED_KEYS_FILE="$HOME/.ssh/id_ed25519.pub"
export HISTB_ROOT_PASSWORD_HASH="$(openssl passwd -6)"
# 或锁定密码，只允许密钥：
export HISTB_ROOT_PASSWORD_HASH='!'
```

可用 `HISTB_ENABLE_NETWORK=0`、`HISTB_ENABLE_SSH=0` 关闭对应服务。

### 完整 p1–p9 文件的边界

离线组装器只把九个已经准备好的普通文件按固定大小拼成一个普通文件，不读取
块设备，也不刷机：

```bash
python3 port/scripts/assemble_user_area.py \
  --p1 p1.raw --p2 p2.raw --p3 p3.raw --p4 p4.raw --p5 p5.raw \
  --p6 p6.raw --p7 p7.raw --p8 p8.raw --p9 p9.raw \
  --output EC6108V9C-user-area.raw
```

p1–p8 必须来自用户自己同型号、同布局、合法持有并验证过的备份；不同盒子不能
混用。本仓库不授权写入分区表、boot0、boot1、RPMB 或设备唯一数据。SDK 范围
与不可发布内容见 [docs/SDK-SCOPE.md](docs/SDK-SCOPE.md)。

## 当前验收边界

2026-09-01，recipe
`c177549bce127f3200d3bc9e0ec8b1701d04023c32c240b3177bfaa9a1938eac`
完成两次干净构建且发布包、p9、rootfs、构建信息和 TF 包逐字节一致；对应 p9
烧录镜像 SHA-256 为
`ce7566f34efd1e3a740913e356618c0f38bb77d158ad067f3f01abfddd50c4ec`。
官方 HiBurn 已完成只写 p9 的实机更新，独立审计覆盖全部 142 个连续写段。

同一配方在 EC6108V9C / Hi3798MV100 上完成只读 UART 冷启动、TF CID/UUID 与
12,242 项完整清单复核、10/10 核心动态装载/ABI 探测、TF 手柄数据库优先与
ROM 内置副本回退。S905 参考镜像中存在对应游戏的 FCEUmm、Snes9x 2010、
PicoDrive、FBNeo、MAME 2003-Plus 共 5 个核心完成真实 ROM 运行、Mali-450、
ALSA、逐例帧缓冲和受控退出验证；FBNeo 实际从 TF 的 S905 BIOS 树读取 NeoGeo
BIOS 并报告文件齐全。HDMI-UVC 捕获到 MAME 游戏可见画面，逻辑无 TF 时 ES、
10 个 ROM 内置核心、内置手柄库和实际 FCEUmm 启动均通过，随后 TF/ES 原样恢复。

Gambatte、gpSP、mGBA、Beetle PCE Fast、PCSX-ReARMed 因该 S905 镜像没有对应
游戏，只能报告目标机装载/ABI 和无 TF 回退 PASS，不能报告真实游戏运行 PASS。

项目所有者取消的六项压力测试继续是 `WAIVED / NOT RUN`，不是 PASS：100 次
ES→游戏→ES、10 次冷启动、运行中断电恢复、配置/存档持久化、A/B 回滚、
连续 8 小时长稳。

## 名词解释

| 名词 | 大白话解释 |
|---|---|
| SDK | 厂商给开发者的一整套源码、工具链、头文件和构建脚本。这里指 HiSTBLinux SDK。 |
| BSP | SDK 中专门让 Linux 适配某块板子的部分，包含芯片、启动和驱动配置。 |
| EmuELEC | 面向电视盒子的复古游戏系统。本项目借用它的前端和软件组织方式。 |
| EmulationStation / ES | 开机后看到的游戏封面和系统菜单；它负责找游戏并启动模拟器。 |
| RetroArch | 统一运行各种模拟器核心的程序；ES 通常把游戏路径交给它。 |
| libretro | RetroArch 与模拟器之间的通用接口标准。 |
| 模拟器核心 / core | 实际模拟某台主机的 `.so` 动态库，例如 FCEUmm；它不是游戏文件。 |
| ROM | 从游戏卡带、光盘等介质取得的游戏数据文件。请只使用自己有权使用的内容。 |
| BIOS | 某些主机启动所需的系统程序，例如部分 PlayStation 游戏需要；仓库不提供商业 BIOS。 |
| rootfs | Linux 的根文件系统，里面是程序、库和配置；本项目把它放在 p9。 |
| p1–p9 | 这台盒子用户区的九个分区。p9 是 rootfs；p1–p8 含启动、内核和板级数据。 |
| sparse 镜像 | 省略大片空白块的镜像格式，文件较小，但写入前必须由兼容工具按逻辑位置还原。 |
| ext4 | Linux 常用文件系统，支持大小写、权限和软链接；本项目构建必须放在它上面。 |
| WSL | Windows Subsystem for Linux，让 Windows 用户运行 Ubuntu 终端。 |
| Git submodule | 主仓库记录另一个仓库的固定提交；这里用来固定 SDK 和 EmuELEC。记录这个固定提交的 Git 条目也叫 **gitlink**。 |
| bootstrap | 第一次准备工作区：下载/检出固定源码、校验版本并复制移植文件，不等于完成编译。 |
| ABI | 二进制程序彼此怎样传参数、找库和调用函数的约定；不匹配时程序无法运行。 |
| ARM softfp | ARM 浮点 ABI：可以使用硬件浮点计算，但函数参数仍按软浮点约定传递。它与 hard-float 不兼容。 |
| framebuffer / fbdev | Linux 直接操作屏幕像素的老式显示接口；本项目不用桌面窗口系统。 |
| EGL | 在 framebuffer 和 OpenGL ES 之间创建绘图表面/上下文的接口。 |
| GLES1 / GLES2 | OpenGL ES 1.x 和 2.x 两代嵌入式 3D 图形接口；ES 和 RetroArch 会用到。 |
| ALSA | Linux 的声音接口；这里把模拟器声音送到 HDMI。 |
| HiBurn | 海思的设备烧录工具。它不在仓库中，也不能只凭“工具显示成功”判断刷写完成。 |
| recipe ID | 根据本次移植源码内容计算的版本 ID。源码变化必须产生新 ID，避免把新旧镜像混为一谈。 |
| rootbox | SDK 在制作 rootfs 前准备的目录树，可以理解为“尚未打包的系统文件夹”。 |
| 依赖闭包 | 一个程序运行时需要的所有动态库集合；审计会确认没有缺库。 |
| payload audit | 对最终镜像实际装入内容的检查；不是只看构建命令返回 0。 |

## 许可证

项目原创脚本、测试和文档采用 [0BSD](LICENSE)。SDK、EmuELEC、RetroArch、
libretro 核心和衍生补丁继续受各自上游许可约束；根目录的 0BSD 不会覆盖它们。
详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
