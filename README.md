# EmuELEC for Hi3798MV100 / EC6108V9C

面向玩家和开发者的 HiSilicon Hi3798MV100 EmuELEC 应用层移植。仓库包含可复现
的交叉编译脚本、Mali-fbdev 图形适配、EmulationStation、RetroArch、8 个
libretro 核心、rootfs overlay、诊断程序和测试。仓库不包含厂商 SDK、ROM、
BIOS、设备备份、HiBurn、rootfs 或整机镜像。

> This is a player-oriented source port. Network, DHCP and Dropbear SSH are on
> by default. The documented development login is `root` / `emuelec`; change it
> after first login or inject your own hash/key at build time.

## 当前状态

私有验收配方 `rb70c2c3ea465` 已在真实 EC6108V9C 上完成完整 p1-p9 写入、
eMMC 冷启动、Mali/EGL/GLES1/GLES2/SDL2、HDMI、ALSA 实际非静音 PCM、
EmulationStation、手柄启动/退出 QuickNES 及 8 核矩阵验证。公开仓库删除了
测试密码、固定网络、ROM 和本地部署资料，因此公开配方与该私有验收镜像
**不是逐字节相同**，需要在自己的 SDK/机器上重新构建和验收。

| 系统 | 核心 | 固定提交 | 真机状态 |
|---|---|---|---|
| NES | QuickNES | `31654810b9ebf8b07f9c4dc27197af7714364ea7` | ES→游戏→手柄退出→ES、Mali、ALSA PASS |
| SNES | Snes9x 2010 | `187e2b58fc09dfeb9fdb5a95bc26786219a111cf` | 启动、画面、Mali、ALSA、退出 PASS |
| GB/GBC | Gambatte | `dd1cf9fdbadbdceee50ff0600321251c823c3ca5` | 同上 PASS |
| GBA | VBA Next | `019132daf41e33a9529036b8728891a221a8ce2e` | 同上 PASS |
| Mega Drive | Genesis Plus GX | `7fa34f20de659004399f58a845291a4496cc9d8c` | 同上 PASS |
| PC Engine | Mednafen PCE Fast | `bdcb39400470cfc9457e170e223a2e70130fdd5c` | 同上 PASS |
| PlayStation | PCSX-ReARMed | `19b9695a71f15ef0bf61c7c3cfd6c98ec5ccb028` | HLE 测试盘、Mali、ALSA、画面 PASS；该路径忽略 SIGINT，受控 SIGTERM 正常结束，无 SIGKILL |
| Arcade | MAME 2003 | `e3d1dac4cfaa4d03f8da5a6d78149bfefe894302` | 启动、画面、Mali、ALSA、退出 PASS |

“核心通过”不代表所有游戏都兼容。PCSX 等核心可能需要玩家依法取得的 BIOS；
本仓库不会提供或推荐下载商业 BIOS/ROM。

## 已验证基线

- EmuELEC：`65b3db37ebdca93d543b7e7b3d5df4a2c9ceee79`
- HiSTBLinux BSP：`fd20f78ab02934e71474dbb1d933c6ec911b01c9`
- 目标：ARMv7 EABI5 softfp，VFPv3-D16，动态加载器 `/lib/ld-linux.so.3`
- 工具链：BSP 自带 GCC 4.9.2 `arm-histbv310-linux`
- EmulationStation：`2afe6efec4e09176882d98323bda5d3f664870a7`
- RetroArch：`ccbff758b46556407d1b9931a72cfcc46201276d`
- SDL2：2.0.9；Dropbear：2026.94

## 默认玩家体验

构建出的公开开发配置默认：

- `eth0` 启用并通过 DHCP 获取地址；
- Dropbear SSH 启用，监听 `0.0.0.0:22`；
- 用户名 `root`，默认密码 `emuelec`；
- 首次登录显示修改密码提醒。

刷入后可在路由器 DHCP 客户端列表查地址，然后：

```sh
ssh root@DEVICE_IP
# password: emuelec
passwd
```

默认密码是公开的开发便利配置，不适合直接暴露到互联网。编译时推荐注入
自己的密钥或密码哈希：

```sh
# 推荐：密钥登录；文件本身不要提交
export HISTB_ROOT_AUTHORIZED_KEYS_FILE="$HOME/.ssh/id_ed25519.pub"

# 可选：让 openssl 交互生成 SHA-512 crypt，不把明文写进脚本或历史
export HISTB_ROOT_PASSWORD_HASH="$(openssl passwd -6)"

# 如需彻底锁定密码，只允许密钥登录
export HISTB_ROOT_PASSWORD_HASH='!'
```

运行时默认值位于 `rootfs-overlay/etc/default/histb-network` 和
`rootfs-overlay/etc/default/histb-ssh`。设置 `HISTB_DUT_ADDRESS` 可改为静态
地址；设置 `HISTB_ENABLE_NETWORK=0` 或 `HISTB_ENABLE_SSH=0` 可关闭服务。

## 构建环境

推荐 Windows 10/11 + WSL2 Ubuntu 24.04，或原生 x86-64 Linux。源码、缓存和
输出必须位于 Linux ext4 文件系统，避免在 NTFS/DrvFs 或 WSL `/home` 里构建。
BSP 含大小写敏感文件、软链接和 Unix 权限，普通 Windows 目录会造成隐蔽错误。

Ubuntu 依赖示例：

```sh
sudo apt update
sudo apt install -y \
  build-essential git patch make ninja-build cmake pkg-config \
  python3 perl gawk bison flex rsync file bc curl wget \
  tar gzip bzip2 xz-utils e2fsprogs zlib1g-dev libssl-dev openssl
```

还需要：

1. 合法取得且固定到上述提交的 HiSTBLinux BSP；
2. BSP 内的 `arm-histbv310-linux` 工具链和已经构建的 vendor include/lib；
3. 固定的 EmuELEC checkout；
4. 各组件源码缓存。脚本遇到缺失缓存会给出所需文件/提交；带 SHA-256 的
   源码包会在解包前校验。

不要执行 BSP 的全局 `server_install.sh`：它会修改主机 `/bin/sh` 并假设过时
的发行版。这里所有 SDK make 调用只对当前命令传入 `SHELL=/bin/bash`。

## 快速开始

将本仓库内容放到 EmuELEC checkout 的 `tools/histb/`：

```text
WORK_ROOT/
├── sdk/                 # HiSTBLinux BSP（不在本仓库）
├── emuelec/             # EmuELEC checkout
│   └── tools/histb/     # 本仓库内容
├── cache/sources/       # 固定源码包/缓存仓库
├── build/               # 可丢弃的干净构建目录
├── artifacts/           # release、rootfs、manifest
└── logs/
```

确保 `WORK_ROOT` 本身位于 ext4，然后：

```sh
cd WORK_ROOT/emuelec
export HISTB_WORK_ROOT="$(cd .. && pwd)"
export HISTB_SDK_ROOT="$HISTB_WORK_ROOT/sdk"

source tools/histb/env.sh
tools/histb/prepare-sdk-integration.sh
tools/histb/build-all.sh
```

`build-all.sh` 有 14 个门禁阶段：SDK 集成、Dropbear、GLES2、GLES1、SDL2、
RetroArch、QuickNES、其余核心、EmulationStation、运行时测试/暂存、rootbox
合成、6846 MiB p9 sparse ext4、规范化、ABI/依赖/打包审计。失败即停止，
不会把部分产物当成成功。

常用独立测试：

```sh
tools/histb/tests/test-es-command-argv.py
tools/histb/tests/test-multicore-config.sh
tools/histb/tests/test-fullflash-config.sh
tools/histb/tests/test-runtime-exec.sh
tools/histb/check-runtime-deps.sh
```

最终 release 及 p9 sparse rootfs 位于 `$HISTB_WORK_ROOT/artifacts/`。配方 ID
由 `tools/histb` 排序文件清单的 SHA-256 派生；修改配方后应清空 build/output，
连续构建两次并比较 manifest、rootfs 和 release 哈希。

## 完整 p1-p9 ROM

公开源码能构建新的 p9 rootfs，但不会分发设备的 p1-p8、bootloader、厂商
kernel、恢复分区或完整镜像。要生成完整 user-area ROM，必须从**同一硬件布局**
的合法备份取得并展开 p1-p8，再将新 p9 sparse ext4 用 `simg2img` 展开。

离线组装器只写普通文件，不访问块设备：

```sh
python3 scripts/assemble_user_area.py \
  --p1 p1.raw --p2 p2.raw --p3 p3.raw --p4 p4.raw --p5 p5.raw \
  --p6 p6.raw --p7 p7.raw --p8 p8.raw --p9 p9.raw \
  --output EC6108V9C-user-area.raw
```

它严格要求 1/1/4/4/4/20/64/512/6846 MiB，输出 7,818,182,656 字节，并生成
包含每分区和全镜像 SHA-256 的 JSON manifest。它不包含分区表、boot0、
boot1 或 RPMB，也不实现刷写。未知板型、不同分区尺寸或没有可验证恢复路径时
不要使用该布局。

## 目录说明

- `build-*.sh`：每个组件的干净交叉构建；
- `prepare-sdk-integration.sh`：校验 BSP 配置并应用 rootbox 集成补丁；
- `env.sh` / `histb-toolchain.cmake`：ARMv7 softfp 交叉环境；
- `patches/`：Mali-fbdev、SDL2、RetroArch、ES、BSP 适配；
- `runtime/`：ES/RetroArch 启动器、系统列表、手柄配置、诊断菜单；
- `rootfs-overlay/`：启动服务、存储保护、网络/SSH 和 supervisor；
- `target/`：release 安装器；
- `tests/`：命令参数、8 核配置、状态机和 rootfs 配置测试；
- `scripts/`：不接触设备的完整镜像离线组装工具；
- `*.c`：EGL/GLES1/GLES2/SDL2 Mali-fbdev smoke 程序。

## 更新模拟器核心

一次只升级一个核心：修改对应 `*_COMMIT` 和 archive/hash，检查上游许可证，
删除该核心 build 目录，重新构建，然后运行 ABI/依赖、8 核配置、rootfs 和双构建
可复现性检查。核心文件可以升级，但不要把“编译通过”当作游戏兼容性通过；
至少在真机检查画面、声音、输入、退出和返回 ES。

## 常见坑

1. **ABI**：厂商 userspace 是 ARM EABI5 softfp，不是 hard-float。
2. **图形栈**：使用 vendor Mali-fbdev EGL，不是 X11/Wayland/DRM/Mesa。
3. **文件系统**：NTFS/DrvFs 会破坏大小写、软链接或权限；必须使用 ext4。
4. **旧 shell**：SDK make 显式使用 Bash；不要全局替换系统 `/bin/sh`。
5. **重复引号**：ES 已对 `%ROM%` 做 shell escaping，`es_systems.cfg` 不要再给
   `%ROM%` 套一层引号，否则带空格 ROM 会变成字面反斜杠路径。
6. **PCSX 退出**：当前 HLE 测试路径忽略 SIGINT；supervisor 应允许升级到
   SIGTERM，只有 SIGKILL 才应作为失败/异常记录。
7. **Sparse 不是整盘**：p9 Android sparse ext4 不能直接当完整 user-area ROM。
8. **网络安全**：默认开发密码公开；连接不可信网络前先 `passwd` 或注入密钥。
9. **ROM/BIOS**：模拟器开源不等于游戏和主机固件可再分发。

## 待完成/欢迎贡献

- 在更多 EC6108V9C 批次和 Hi3798MV100 设备上验证布局差异；
- 对公开玩家默认配方做更多干净主机 A/B 构建；
- 增加合法测试内容的兼容性结果和手柄 profile；
- 在不分发厂商材料的前提下改善 SDK 获取/校验说明；
- 只有理清全部厂商和第三方再分发条款后，才发布完整 firmware asset。

原验收中的 100 次循环、10 次继电器冷启动、运行中断电恢复、配置/存档持久化、
A/B 回滚和 8 小时长稳由项目所有者明确取消，状态是 `WAIVED / NOT RUN`，
不是 PASS。

## 许可证

项目原创胶水代码、测试和文档采用 [0BSD](LICENSE)，尽可能方便玩家修改、
复制和再发布。第三方代码和衍生补丁继续受各自上游许可证约束，0BSD 不覆盖
它们。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
