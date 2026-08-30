# EmuELEC for Hi3798MV100 / EC6108V9C

面向玩家和开发者的 HiSilicon Hi3798MV100 EmuELEC 移植工作区。仓库固定并
关联完整 HiSTBLinux SDK、EmuELEC 上游源码和本项目移植代码；克隆或下载后
运行引导脚本即可得到相同目录结构，不再需要手工找 SDK、猜提交或复制补丁。

> 默认开发体验：`eth0` DHCP、Dropbear SSH 开启，登录为
> `root` / `emuelec`。这是公开的开发密码，首次登录后请执行 `passwd`，或在
> 构建前注入自己的密码哈希/SSH 公钥。

## 一分钟开始

必须在 Linux ext4 文件系统中工作。Windows 用户推荐 WSL2，但不要放在
`/mnt/c`、`/mnt/e` 等 NTFS/DrvFs 目录；SDK 含大小写敏感文件、Unix 权限和
软链接。

```sh
sudo apt update
sudo apt install -y \
  build-essential git patch make ninja-build cmake pkg-config \
  python3 perl gawk bison flex gettext autoconf automake libtool \
  rsync file bc curl wget libncurses-dev \
  tar gzip bzip2 xz-utils unzip e2fsprogs zlib1g-dev libssl-dev openssl \
  libc6-i386 lib32z1

git clone --recurse-submodules --shallow-submodules \
  https://github.com/ghkjgod/emuelec-for-hi3798mv100.git
cd emuelec-for-hi3798mv100
./scripts/bootstrap-workspace.sh
./scripts/build-workspace.sh
```

`bootstrap-workspace.sh` 验证 ext4、检出固定版本、核对 SDK 板级配置哈希，
把 `port/` 同步到 `emuelec/tools/histb/`，并运行源码回归测试。
`build-workspace.sh` 先按 `SOURCES.lock` 下载并逐项校验第三方源码，再完整构建
SDK、8 个核心、RetroArch、SDL2、
EmulationStation、rootbox 和 6846 MiB p9 sparse ext4，再运行 ABI、依赖和
rootfs 门禁。旧 SDK 高并发不稳定，默认 2 jobs；可设置 `HISTB_JOBS=4`。

GitHub 的 “Download ZIP” 不含子模块，但也支持：将 ZIP 解压到 ext4 后运行
同一个 bootstrap，脚本会按 `WORKSPACE.lock` 自动克隆固定上游。建议至少预留
40 GiB 空间。

## 固定源码

| 组成 | 固定提交 | 获取方式 |
|---|---|---|
| HiSTBLinux SDK/BSP | `fd20f78ab02934e71474dbb1d933c6ec911b01c9` | `sdk/` 子模块，GitCode `master` |
| EmuELEC | `65b3db37ebdca93d543b7e7b3d5df4a2c9ceee79` | `emuelec/` 子模块，GitHub `master_32bit` |
| 本移植 | 当前仓库 `port/` | 0BSD 原创胶水；衍生补丁保留上游条款 |

精确 URL、commit 和板级配置 SHA-256 在 `WORKSPACE.lock`。`.gitmodules` 让
递归 clone 取得完整源码；SDK/EmuELEC 大文件由固定 gitlink 获取，不复制到
本仓库对象库，也不会把本地输出混进提交。

## 目录结构

```text
emuelec-for-hi3798mv100/
├── sdk/                 # 完整固定 HiSTBLinux SDK 子模块
├── emuelec/             # 完整固定 EmuELEC 子模块
│   └── tools/histb/     # bootstrap 从 port/ 生成的受管副本
├── port/                # 全部移植源码、补丁、运行时和测试
├── scripts/             # 初始化和一键构建入口
├── WORKSPACE.lock       # 上游 URL/commit/配置哈希
├── SOURCES.lock         # 第三方源码 URL/SHA-256 清单
├── artifacts/           # 构建产物，Git 忽略
├── build/               # 干净构建目录，Git 忽略
├── cache/sources/       # 固定源码缓存，Git 忽略
└── logs/                # 构建日志，Git 忽略
```

`port/` 包含：

- `build-*.sh`：Dropbear、SDL2、RetroArch、EmulationStation、8 核干净交叉构建；
- `prepare-sdk-integration.sh`：校验 cfg、扩展 p9、应用 rootbox 补丁；
- `env.sh` / `histb-toolchain.cmake`：ARMv7 softfp 交叉环境；
- `patches/`：Mali-fbdev、SDL2、RetroArch、ES、BSP 适配；
- `runtime/`：启动器、系统列表、手柄 profile、诊断菜单；
- `rootfs-overlay/`：SysV 启动、存储保护、DHCP/SSH、supervisor；
- `target/`、`tests/`：release 安装器与回归测试；
- `scripts/assemble_user_area.py`：只操作普通文件的 p1-p9 离线组装器；
- `*.c`：EGL/GLES1/GLES2/SDL2 Mali-fbdev smoke。

## 构建和输出

一键脚本先执行禁用 overlay 合成的 vendor SDK `make build`，生成工具链所需的
vendor include/lib/rootbox 基线；应用构建完成后再合成 EmuELEC overlay。随后
执行移植的 14 阶段门禁：SDK
集成、Dropbear、GLES2、GLES1、SDL2、RetroArch、QuickNES、其余核心、ES、
运行时暂存、rootbox、p9 sparse ext4、规范化、ABI/依赖/发布审计。任一阶段
失败即停止，不把部分输出当成功。

主要输出位于 `artifacts/` 和 `logs/histb-emuelec-build-all.log`。已有完整 SDK
输出时可跳过昂贵的 SDK 全构建，但仍会验证固定 checkout 和移植配置：

```sh
HISTB_SKIP_SDK_BUILD=1 ./scripts/build-workspace.sh
```

只运行移植层：

```sh
export HISTB_WORK_ROOT="$PWD"
export HISTB_SDK_ROOT="$PWD/sdk"
export HISTB_EMUELEC_ROOT="$PWD/emuelec"
source emuelec/tools/histb/env.sh
emuelec/tools/histb/build-all.sh
```

## 目标 ABI 与图形栈

- Hi3798MV100、ARMv7 EABI5 softfp、Cortex-A7、VFPv3-D16；
- 动态加载器 `/lib/ld-linux.so.3`；
- SDK 自带 GCC 4.9.2 `arm-histbv310-linux`；
- vendor Mali-450 fbdev EGL/GLES，不是 X11/Wayland/DRM/Mesa；
- ALSA → HDMI；EmulationStation + RetroArch。

## 已移植核心

| 系统 | 核心 | 固定提交 | 真机状态 |
|---|---|---|---|
| NES | QuickNES | `31654810b9ebf8b07f9c4dc27197af7714364ea7` | ES→游戏→手柄退出→ES、Mali、ALSA PASS |
| SNES | Snes9x 2010 | `187e2b58fc09dfeb9fdb5a95bc26786219a111cf` | 画面、声音、退出 PASS |
| GB/GBC | Gambatte | `dd1cf9fdbadbdceee50ff0600321251c823c3ca5` | 同上 PASS |
| GBA | VBA Next | `019132daf41e33a9529036b8728891a221a8ce2e` | 同上 PASS |
| Mega Drive | Genesis Plus GX | `7fa34f20de659004399f58a845291a4496cc9d8c` | 同上 PASS |
| PC Engine | Mednafen PCE Fast | `bdcb39400470cfc9457e170e223a2e70130fdd5c` | 同上 PASS |
| PlayStation | PCSX-ReARMed | `19b9695a71f15ef0bf61c7c3cfd6c98ec5ccb028` | HLE、画面、声音 PASS；受控 SIGTERM 退出 |
| Arcade | MAME 2003 | `e3d1dac4cfaa4d03f8da5a6d78149bfefe894302` | 画面、声音、退出 PASS |

核心通过不代表所有游戏兼容。PCSX 等系统可能需要玩家依法取得的 BIOS；仓库
不提供 ROM、商业 BIOS 或下载链接。

## 网络、SSH 与密码

默认启动 `eth0` DHCP 和 Dropbear SSH，监听 `0.0.0.0:22`：

```sh
ssh root@DEVICE_IP
# password: emuelec
passwd
```

推荐构建时注入自己的凭据：

```sh
export HISTB_ROOT_AUTHORIZED_KEYS_FILE="$HOME/.ssh/id_ed25519.pub"
export HISTB_ROOT_PASSWORD_HASH="$(openssl passwd -6)"
# 或锁定密码，只允许密钥
export HISTB_ROOT_PASSWORD_HASH='!'
```

可用 `HISTB_ENABLE_NETWORK=0` / `HISTB_ENABLE_SSH=0` 关闭服务，或用
`HISTB_DUT_ADDRESS` 配静态地址。测试机的私有密码未进入源码或 Git 历史。

## 完整 p1-p9 ROM

源码构建产生新的 p9 rootfs。p1-p8 含板级 boot/kernel/恢复内容，不能从
EmuELEC 源码生成；必须从同型号、同布局、合法持有且校验过的备份取得。将 p9
sparse ext4 用 `simg2img` 展开后，可离线组装完整 user-area 文件：

```sh
python3 port/scripts/assemble_user_area.py \
  --p1 p1.raw --p2 p2.raw --p3 p3.raw --p4 p4.raw --p5 p5.raw \
  --p6 p6.raw --p7 p7.raw --p8 p8.raw --p9 p9.raw \
  --output EC6108V9C-user-area.raw
```

组装器严格要求 1/1/4/4/4/20/64/512/6846 MiB，输出 7,818,182,656 字节，
生成逐分区和全文件 SHA-256 manifest。它不访问块设备、不修改分区表，也不
包含烧录器；不同板型/布局不能套用这些尺寸。

## 更新核心与常见坑

一次只升级一个核心：更新 `*_COMMIT` 和 archive/hash，核对许可证，清理该核心
build 目录，重跑 ABI/依赖、8 核、rootfs、双构建可复现性，再做真机画面、声音、
输入、退出/返回验证。

常见坑：不能在 NTFS 构建；ABI 不是 hard-float；图形不是 Mesa；不要运行会
修改主机 `/bin/sh` 的 SDK `server_install.sh`；ES `%ROM%` 不要重复加引号；
p9 sparse 不是整盘 ROM；默认开发密码不能暴露到不可信网络。

## 验收边界与待办

私有验收候选已在真实 EC6108V9C 上通过完整 p1-p9 启动、Mali/EGL/GLES/SDL、
HDMI、ALSA 非静音音频、ES、手柄启动/退出 QuickNES 和 8 核矩阵。公开构建因
默认凭据和已移除的本地资料会得到新配方/哈希，不能冒充私有验收镜像；每个新
构建都应重新做目标板验收。

以下项目由项目所有者取消，状态为 `WAIVED / NOT RUN`，不是 PASS：100 次
ES→游戏→ES、10 次冷启动、运行中断电恢复、配置/存档持久化、A/B 回滚、
8 小时长稳。

厂商 SDK 范围、不可提交内容和许可边界见
[docs/SDK-SCOPE.md](docs/SDK-SCOPE.md)。

## 许可证

原创胶水代码、测试和文档采用 [0BSD](LICENSE)。SDK、EmuELEC、libretro
核心、衍生补丁等继续受各自条款约束；0BSD 不覆盖子模块。详见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
