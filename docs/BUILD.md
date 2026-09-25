# 从零开始编译（详细操作手册）

这份手册面向第一次编译本项目的人：不需要懂交叉编译、SDK 或 Linux 内核，
按顺序照做即可。每一步都写了"应该看到什么"和"出错了怎么办"。

如果只想知道最短路径，看 [第 0 节](#0-最短路径)；编译报错时直接跳到
[第 11 节 常见错误对照表](#11-常见错误对照表)。

## 目录

- [0. 最短路径](#0-最短路径)
- [1. 你真的需要编译吗](#1-你真的需要编译吗)
- [2. 电脑要求](#2-电脑要求)
- [3. Windows 用户：安装 WSL2 和 Ubuntu](#3-windows-用户安装-wsl2-和-ubuntu)
- [4. 安装编译依赖](#4-安装编译依赖)
- [5. 网络与代理（国内用户必看）](#5-网络与代理国内用户必看)
- [6. 获取源码](#6-获取源码)
- [7. 开始编译](#7-开始编译)
- [8. 编译产物在哪里](#8-编译产物在哪里)
- [9. 定制与二次开发](#9-定制与二次开发)
- [10. 更新、重编与清理](#10-更新重编与清理)
- [11. 常见错误对照表](#11-常见错误对照表)
- [12. 求助时请附带的信息](#12-求助时请附带的信息)

---

## 0. 最短路径

已经有 x86-64 的 Ubuntu 24.04（原生或 WSL2），磁盘剩余 50 GiB 以上，并且能
访问 GitHub 时，在 **Ubuntu 终端** 里依次执行：

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

./easy-build.sh --check          # 只检查电脑，几秒钟
./easy-build.sh --setup-only     # 准备固定版本源码，不编译
./build-flash-image.sh           # 完整编译 + 生成 p9 镜像和 TF 目录，约 1–3 小时
```

成功后最后几行是：

```text
Everything required for an almost ready-to-play installation is present.
  burnable p9/rootfs image: .../artifacts/flash/histb-emuelec-...-p9-rootfs.img
  copy-ready TF directory: .../artifacts/tf-card
```

任何一步失败，看终端最后一段的 `Build check failed:` / `Next step:` 提示，或者
查 [第 11 节](#11-常见错误对照表)。

---

## 1. 你真的需要编译吗

| 你的目的 | 是否需要编译 |
|---|---|
| 只想把模拟器核心、手柄数据库放到 TF 卡 | **不需要**。仓库里的 `tf-card/EmuELEC` 就是已验证的成品，直接复制到卡根目录，见 [TF-CARD.md](TF-CARD.md) |
| 需要 p9/rootfs 镜像（写入盒子的系统分区） | **需要**。仓库不提供成品镜像，只能自己编译 |
| 想改模拟器、前端、启动脚本、默认密码等 | **需要** |

编译得到的是 **只能写入 p9 分区的 rootfs 镜像**，不是整盘刷机包。写入范围和
风险见 [README 的完整 p1–p9 边界](../README.md#完整-p1p9-文件的边界)。编译
成功只说明源码和镜像通过了检查，不代表已经在你的盒子上验收。

---

## 2. 电脑要求

| 项目 | 要求 | 说明 |
|---|---|---|
| CPU 架构 | **x86-64**（Intel/AMD） | SDK 自带的交叉编译器只能在 x86 主机上运行；ARM 的 Mac、树莓派、ARM 版 Linux 不行 |
| 系统 | **Ubuntu 24.04 LTS**（已验证） | 原生安装、虚拟机或 Windows 的 WSL2 都可以。其他发行版未验证 |
| 文件系统 | 仓库必须在 **ext4** 上 | 不能放在 NTFS/FAT/exFAT、`/mnt/c`、`/mnt/d`、`/mnt/e`、虚拟机共享文件夹里 |
| 磁盘 | 最低 40 GiB 空闲，建议 50 GiB 以上 | 脚本会检查，不足 40 GiB 直接拒绝开始完整编译 |
| 内存 | 建议 8 GiB 以上 | 内存小时需要调低并行数，见 [7.3](#73-并行数与内存) |
| 网络 | 能访问 GitHub 和 gitcode.com | 国内一般需要代理，见 [第 5 节](#5-网络与代理国内用户必看) |
| 时间 | 约 1–3 小时 | 取决于 CPU、磁盘和首次下载速度 |
| 路径 | 不能含空格 | 例如 `~/emuelec-for-hi3798mv100` 可以，`~/my build/...` 不行 |

**为什么非要 ext4？** 厂商 SDK 里有只差大小写的同名文件、Unix 权限位和软链接。
Windows 的 NTFS 目录（包括 WSL 里的 `/mnt/c` 等）无法可靠保存它们，编译会
出现莫名其妙的错误。所以脚本在一开始就检查文件系统，不是 ext4 就拒绝继续。

使用 VMware/VirtualBox 虚拟机时：把仓库放在虚拟机自己的虚拟磁盘里（通常是
ext4），不要放在"共享文件夹"里；虚拟磁盘至少分 60 GiB。

---

## 3. Windows 用户：安装 WSL2 和 Ubuntu

Linux 用户跳到 [第 4 节](#4-安装编译依赖)。

### 3.1 安装

以 **管理员身份** 打开 PowerShell，执行：

```powershell
wsl --install -d Ubuntu-24.04
```

按提示重启电脑。重启后会自动弹出 Ubuntu 窗口，要求创建一个 Linux 用户名和
密码（输入密码时屏幕不显示字符，这是正常的）。这个密码之后 `sudo` 会用到。

### 3.2 确认是 WSL **2**

在 PowerShell 执行：

```powershell
wsl -l -v
```

`Ubuntu-24.04` 那一行的 `VERSION` 必须是 `2`。如果是 `1`：

```powershell
wsl --set-version Ubuntu-24.04 2
```

WSL1 的文件系统不是 ext4，脚本会拒绝编译。

### 3.3 以后怎么打开 Ubuntu 终端

开始菜单搜索 **Ubuntu 24.04** 打开即可。本手册中所有 `bash` 命令都在这个窗口
里执行，**不要** 在 PowerShell、CMD 或 Git Bash 里执行。

在 Ubuntu 终端里执行 `explorer.exe .` 可以用 Windows 资源管理器打开当前目录，
方便取出编译产物；也可以在资源管理器地址栏输入
`\\wsl$\Ubuntu-24.04\home\你的用户名`。

### 3.4（可选）调整内存和 CPU

WSL2 默认最多使用电脑一半的内存。电脑内存 16 GiB 以上一般不用改。内存较小
时，可以在 Windows 中创建或编辑 `C:\Users\你的用户名\.wslconfig`：

```ini
[wsl2]
memory=8GB
processors=4
swap=8GB
```

保存后在 PowerShell 执行 `wsl --shutdown`，再重新打开 Ubuntu 生效。

### 3.5（可选）C 盘空间不够

WSL 的 Linux 磁盘默认在 C 盘。C 盘剩余不足 50 GiB 时，**不要** 把仓库放到
`/mnt/d` 或 `/mnt/e` 来"借用"其他盘，那是 NTFS，一定会失败。正确做法是把整个
Ubuntu 搬到其他盘。在 PowerShell 中执行（以 D 盘为例）：

```powershell
wsl --shutdown
mkdir D:\wsl
wsl --export Ubuntu-24.04 D:\wsl\ubuntu-24.04.tar
# 确认上一步生成的 tar 文件确实存在且大小正常，再执行下面这行。
# 这一行会删除 C 盘上原来的 Ubuntu，里面的文件只保留在刚导出的 tar 中。
wsl --unregister Ubuntu-24.04
wsl --import Ubuntu-24.04 D:\wsl\Ubuntu-24.04 D:\wsl\ubuntu-24.04.tar --version 2
```

导入后默认以 root 登录。在 Ubuntu 中执行下面命令（把 `你的用户名` 换成 3.1 里
创建的用户名），然后 `wsl --shutdown` 再打开即可恢复原来的用户：

```bash
printf '[user]\ndefault=你的用户名\n' | sudo tee -a /etc/wsl.conf
```

确认一切正常后，可以删除 `D:\wsl\ubuntu-24.04.tar`。

---

## 4. 安装编译依赖

在 Ubuntu 终端执行（整段复制）：

```bash
sudo apt update
sudo apt install -y \
  build-essential git patch make ninja-build cmake pkg-config \
  python3 perl gawk bison flex gettext texinfo autoconf automake libtool \
  rsync file bc curl wget libncurses-dev \
  tar gzip bzip2 xz-utils unzip e2fsprogs zlib1g-dev libssl-dev openssl \
  libc6-i386 lib32z1
```

其中 `libc6-i386`、`lib32z1` 是 SDK 自带工具需要的 32 位兼容库，不能省略。
`easy-build.sh` 会逐个检查这些包，缺哪个会直接告诉你。

**不要** 运行 SDK 里的 `server_install.sh`：它会替换系统的 `/bin/sh` 并强制安装
过时的工具版本。本项目的脚本已经在需要的地方单独指定 `SHELL=/bin/bash`。

---

## 5. 网络与代理（国内用户必看）

编译过程会联网访问下面这些地址：

| 用途 | 地址 |
|---|---|
| 本仓库、EmuELEC、RetroArch、各模拟器核心 | `github.com`、`api.github.com`、`codeload.github.com` |
| 厂商 HiSTBLinux SDK | `gitcode.com` |
| SDL2、FreeImage、curl、Ogg/Vorbis、Dropbear 等源码包 | `libsdl.org`、`sourceforge.net`、`curl.se`、`xiph.org`、`matt.ucc.asn.au` |

GitHub 访问不稳定时，需要让 Ubuntu 终端走代理。`git` 和 `curl` 都会读取下面的
环境变量，只对当前终端窗口有效，关闭窗口就失效：

```bash
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
```

`7890` 只是示例，请换成你代理软件实际的 HTTP 代理端口。

### WSL2 使用 Windows 上的代理

WSL2 默认是 NAT 网络模式，Ubuntu 里的 `127.0.0.1` 指向的是 Linux 自己，**不是**
Windows，所以上面的写法直接用会连不上。打开 Ubuntu 时如果看到"检测到 localhost
代理配置，但未镜像到 WSL"之类的提示，就是这个原因。两种解决办法任选其一：

**办法 A：镜像网络模式（Windows 11 22H2 及以上推荐）**

在 `C:\Users\你的用户名\.wslconfig` 中加入：

```ini
[wsl2]
networkingMode=mirrored
```

PowerShell 执行 `wsl --shutdown` 后重新打开 Ubuntu，此后 Ubuntu 里的
`127.0.0.1` 就是 Windows，上面的 `export` 写法可以直接用。

**办法 B：使用 Windows 主机地址**

在代理软件里打开"允许局域网连接 / Allow LAN"，然后在 Ubuntu 中执行：

```bash
host_ip="$(ip route show default | awk '{print $3}')"
export http_proxy="http://${host_ip}:7890"
export https_proxy="http://${host_ip}:7890"
```

### 验证代理是否生效

```bash
curl -I https://github.com
```

能看到 `HTTP/2 200` 之类的响应就说明可以了。

`sudo apt` 默认不会继承你的代理变量；如果 apt 也需要代理，用 `sudo -E apt ...`。
apt 本身直连国内网络通常也能工作，只是可能较慢。

---

## 6. 获取源码

### 6.1 推荐：git clone（带子模块）

```bash
cd ~
git clone --recurse-submodules --shallow-submodules \
  https://github.com/ghkjgod/emuelec-for-hi3798mv100.git
cd emuelec-for-hi3798mv100
```

- `cd ~` 进入 Linux 自己的家目录（ext4），这一步不要省。
- 仓库包含两个子模块：`sdk/`（厂商 SDK，来自 gitcode.com，体积较大）和
  `emuelec/`（EmuELEC，来自 GitHub）。两者都被固定在精确的提交上。
- 克隆中途断网也没关系，进入目录后执行 `./easy-build.sh --setup-only`，它会
  自动补全子模块并校验版本。

### 6.2 备用：下载 ZIP

GitHub 页面 **Code → Download ZIP** 下载的压缩包 **不含子模块**。用法：

```bash
cd ~
# 把 ZIP 复制到家目录后在 Linux 里解压，不要在 Windows 里解压
unzip emuelec-for-hi3798mv100-main.zip
cd emuelec-for-hi3798mv100-main
./easy-build.sh --setup-only
```

引导脚本发现不是 Git 仓库时，会按 `WORKSPACE.lock` 自动克隆固定版本的 SDK 和
EmuELEC。**一定要在 Linux 里解压**：在 Windows 里解压再复制进来，会丢失脚本的
可执行权限，还可能把换行符变成 Windows 格式，导致脚本无法运行。

### 6.3 不要这样做

- 不要在 Windows 上用 Git for Windows 克隆，再复制到 WSL。
- 不要把仓库放在 `/mnt/c`、`/mnt/d`、`/mnt/e` 等 Windows 盘下。
- 不要用 `sudo` 克隆或编译；以后所有文件都会属于 root，普通用户无法修改。

---

## 7. 开始编译

以下命令都在仓库根目录（`~/emuelec-for-hi3798mv100`）执行。

### 7.1 第一步：检查电脑

```bash
./easy-build.sh --check
```

它只做检查，不下载、不编译，几秒钟完成。检查内容：是否在 Linux 中运行、路径
有无空格、是否在 ext4 上、依赖工具和 apt 包是否齐全、剩余空间、仓库文件是否
完整。通过时显示：

```text
Computer check passed.
  project:    /home/你的用户名/emuelec-for-hi3798mv100
  filesystem: ext2/ext3
  free space: 123 GiB
No files were downloaded or built (--check).
```

`filesystem: ext2/ext3` 是 `stat` 对 ext4 的正常显示，不用担心。

失败时会显示 `Build check failed:`（原因）和 `Next step:`（下一步该执行的命令），
照着做再重新检查即可。

### 7.2 第二步：准备源码

```bash
./easy-build.sh --setup-only
```

这一步会：

1. 拉取或补全 `sdk/`、`emuelec/` 两个子模块，并核对它们的提交号与
   `WORKSPACE.lock` 完全一致；
2. 核对 Hi3798MV100 板级配置文件的 SHA-256；
3. 把 `port/` 同步到 `emuelec/tools/histb/`（编译实际使用这份副本）；
4. 运行 7 组脚本回归测试，并校验仓库自带的 `tf-card/` 成品目录。

成功时显示 `Workspace ready.` 和两个固定提交号。子模块较大，首次可能需要十几
分钟到更久，取决于网速。

### 7.3 并行数与内存

用环境变量 `HISTB_JOBS` 控制同时编译的任务数。不设置时各阶段默认值不同：
SDK 为 2，SDL2/RetroArch/模拟器核心为 4，EmulationStation 为 8。设置后所有
阶段统一使用这个值。

建议取 **CPU 线程数** 和 **内存 GiB 数 ÷ 2** 中较小的那个，例如：

| 电脑（WSL 可用内存） | 建议 |
|---|---|
| 8 GiB 及以下 | `HISTB_JOBS=2` |
| 16 GiB | `HISTB_JOBS=4` |
| 32 GiB 及以上 | `HISTB_JOBS=8` |

编译中出现 `Killed`、`internal compiler error: Killed` 或
`Killed signal terminated program cc1plus`，基本就是内存不足，把 `HISTB_JOBS`
调小后重新运行即可。

### 7.4 第三步：完整编译

推荐用这条命令，它包含完整编译，并在最后再次核对 p9 镜像和 TF 目录的校验值：

```bash
HISTB_JOBS=4 ./build-flash-image.sh
```

`./easy-build.sh`（不带参数）执行的是同样的完整编译，只是最后不做那一步额外
核对。两者任选其一，不需要都跑。

**防止中途断掉**：编译要一两个小时，关闭终端窗口会让编译进程一起退出，电脑
睡眠也会让它暂停。建议用 `tmux`（Ubuntu 一般已自带，没有就
`sudo apt install -y tmux`）：

```bash
tmux new -s build
HISTB_JOBS=4 ./build-flash-image.sh
# 按 Ctrl+B 然后按 D，可以离开而不中断编译
# 之后重新打开终端，用下面命令回来查看进度：
tmux attach -t build
```

**保存完整日志**：`logs/histb-emuelec-build-all.log` 只记录移植层 13 个阶段，
不包含前面的下载和 SDK 编译。想保留从头到尾的完整输出，可以这样运行：

```bash
mkdir -p logs
HISTB_JOBS=4 ./build-flash-image.sh 2>&1 | tee "logs/full-build-$(date +%Y%m%d-%H%M).log"
```

### 7.5 编译过程中会发生什么

整个流程按顺序执行，任何一步失败都会立即停止，不会把半成品当作成功：

| 顺序 | 终端里看到的 | 做什么 | 备注 |
|---|---|---|---|
| 1 | `Computer check passed.` | 电脑检查 | 同 7.1 |
| 2 | `Workspace ready.` | 准备源码 | 同 7.2（会再运行一次，很快） |
| 3 | `Downloading ...`、`Pinned ...` | 下载 29 个源码包、2 个 Git 仓库和 CMake 3.20.6，逐个校验 SHA-256 | 保存在 `cache/sources/`，下次不再下载 |
| 4 | `SDK integration ready` | 生成 SDK 板级配置（p9 rootfs 6846 MiB），给 SDK 打补丁 | 可以重复执行 |
| 5 | `Building the pinned HiSTBLinux SDK ...` | 编译厂商 SDK：内核、驱动、BusyBox、厂商库 | **最耗时**，维护者机器上约 36 分钟；这期间屏幕输出很多是正常的 |
| 6 | `[1/13]` | 再次确认 SDK 集成 | |
| 7 | `[2/13]` | Dropbear SSH 服务端 | |
| 8 | `[3/13]` `[4/13]` | EGL/GLES2、EGL/GLES1 图形冒烟测试程序 | 验证 Mali-450 fbdev 图形库能正确链接 |
| 9 | `[5/13]` | SDL2（Mali-fbdev 后端） | |
| 10 | `[6/13]` | RetroArch | |
| 11 | `[7/13]` | 10 个 libretro 模拟器核心 | 较耗时 |
| 12 | `[8/13]` | EmulationStation 及其依赖 | 较耗时，内存占用高 |
| 13 | `[9/13]` | 运行时文件暂存、配置测试、生成 `artifacts/tf-card/` | |
| 14 | `[10/13]` | 合成 rootfs 目录（rootbox），装入 SSH、设置 root 账户 | |
| 15 | `[11/13]` | 生成 Android sparse 格式的 p9 rootfs | |
| 16 | `[12/13]` | 规范化镜像，`e2fsck` 检查，raw↔sparse 往返逐字节比较 | |
| 17 | `[13/13]` | 检查所有 ARM 程序的 ABI 和依赖库，打包发布包，生成 p9 烧录镜像 | 出现 `PASS: HiBurn p9/rootfs image is ready` |
| 18 | `Everything required ...` | `build-flash-image.sh` 最终核对 | 只有用 `build-flash-image.sh` 才有这一步 |

### 7.6 中断或失败后怎么继续

修好问题后，**重新运行同一条命令** 即可：

- 已下载并校验过的源码包会保留，不会重新下载；
- 子模块会自动补全；
- SDK 编译会重新执行一遍；
- 移植层的各个组件每次都会从空目录重新编译，这是有意为之，保证产物可复现。

如果 SDK 已经完整编译成功过一次，只是后面的移植阶段失败，可以跳过 SDK 编译
节省时间，见 [10.2](#102-只重编一部分)。

---

## 8. 编译产物在哪里

| 内容 | 路径 |
|---|---|
| **HiBurn 用 p9 烧录镜像** | `artifacts/flash/<版本ID>-p9-rootfs.img` |
| 该镜像的 SHA-256 | `artifacts/flash/<版本ID>-p9-rootfs.img.sha256` |
| 镜像信息与审计记录 | `artifacts/flash/<版本ID>-p9-rootfs.info.txt`、`.audit.txt` |
| 写入范围说明 | `artifacts/flash/FLASH-INSTRUCTIONS.txt` |
| **可直接复制到 TF 卡的目录** | `artifacts/tf-card/EmuELEC/` |
| 应用发布包 | `artifacts/releases/` |
| root 账户策略（默认密码还是自定义） | `artifacts/root-account-policy.txt` |
| SDK 原始 p9 sparse 镜像 | `sdk/out/hi3798mv100/hi3798mdmo1g/image/emmc_image/rootfs_6846M.ext4` |
| 移植层构建日志 | `logs/histb-emuelec-build-all.log` |

`<版本ID>` 形如 `histb-emuelec-20211020T162750Z-65b3db37ebdc-r1234567890ab`：
中间是 EmuELEC 固定提交，末尾 `r` 后面 12 位是根据 `port/` 全部文件内容计算的
配方 ID。只要源码没改，重复编译得到的文件名和内容都相同；改了任何一个文件，
配方 ID 就会变。

`artifacts/flash/` 里的 `.img` 与 SDK 原始 `rootfs_6846M.ext4` 内容相同，只是把
数据块切成不超过 4 MiB 的片段，以满足官方 HiBurn 的传输限制。**写入时用
`artifacts/flash/` 里的那个。**

### 8.1 校验

```bash
(cd artifacts/flash && sha256sum -c ./*.sha256)
(cd artifacts/tf-card && sha256sum -c MANIFEST.sha256)
```

每行都显示 `OK` 即为完好。

### 8.2 复制到 Windows

编译必须在 ext4 里进行，但编译 **完成后** 的成品可以随意复制到 Windows 盘：

```bash
mkdir -p /mnt/d/emuelec-output
cp -r artifacts/flash artifacts/tf-card /mnt/d/emuelec-output/
```

复制后在 Windows 上可以用 PowerShell 的 `Get-FileHash 文件名 -Algorithm SHA256`
再核对一次。

### 8.3 下一步

- **TF 卡**：把 `tf-card/EmuELEC` 整个文件夹复制到 TF 卡根目录，再放入自己
  合法持有的 BIOS 和游戏，详见 [TF-CARD.md](TF-CARD.md)。
- **p9 镜像**：只能写入 **EC6108V9C / Hi3798MV100、已确认九分区布局** 的 p9
  （rootfs）分区。写入前务必备份原机分区；**不能** 当作整盘镜像，也不能写入
  p1–p8、分区表、boot0、boot1 或 RPMB。详见 README 和
  `artifacts/flash/FLASH-INSTRUCTIONS.txt`。

---

## 9. 定制与二次开发

### 9.1 修改默认 SSH 密码或放入公钥

公开构建默认开启 DHCP 和 SSH，账号 `root`，密码 `emuelec`。这是所有人都知道的
密码，只适合可信的家庭内网。想在编译时就换掉它：

```bash
# 交互输入新密码，生成密码哈希（密码本身不会被保存）
export HISTB_ROOT_PASSWORD_HASH="$(openssl passwd -6)"
# 可选：放入自己的 SSH 公钥
export HISTB_ROOT_AUTHORIZED_KEYS_FILE="$HOME/.ssh/id_ed25519.pub"
# 可选：完全禁止密码登录，只允许密钥（需同时提供上面的公钥）
# export HISTB_ROOT_PASSWORD_HASH='!'

HISTB_JOBS=4 ./build-flash-image.sh
```

这些变量只在当前终端窗口有效，必须和编译命令在同一个窗口里执行。编译后查看
`artifacts/root-account-policy.txt`：`root_account=builder-supplied` 或 `locked`
表示已生效，`public-development-default` 表示仍是默认密码。

也可以不改编译，首次 SSH 登录盒子后执行 `passwd` 修改密码。

### 9.2 关闭网络 / SSH、设置静态 IP

这些是 **盒子上** 的运行时配置，不是编译参数，在编译前 `export` 它们没有作用。
在盒子上编辑：

- `/etc/default/histb-network`：`HISTB_ENABLE_NETWORK=0` 关闭网络；
  `HISTB_DUT_ADDRESS`、`HISTB_DUT_NETMASK` 设置静态 IP（留空为 DHCP）。
- `/etc/default/histb-ssh`：`HISTB_ENABLE_SSH=0` 关闭 SSH；
  `HISTB_SSH_ALLOW_PASSWORD=0` 只允许密钥登录。

不要为此修改源码里 `port/rootfs-overlay/etc/default/` 下的默认值：编译过程中的
测试会检查公开版默认值，改了会导致编译失败。

### 9.3 修改代码

- **只改 `port/` 目录。** 每次准备源码时，`port/` 会以覆盖方式同步到
  `emuelec/tools/histb/`，直接改 `emuelec/tools/histb/` 里的文件会被覆盖丢失。
- 改完后重新运行 `./build-flash-image.sh`，或按 [10.2](#102-只重编一部分)
  跳过 SDK 以加快速度。
- 改了任何文件，配方 ID 都会变，`artifacts/flash/` 中会多出一个新文件名的镜像。
  重编前请先把旧的挪走，否则 `build-flash-image.sh` 会因为发现两个镜像而报错：

  ```bash
  mv artifacts/flash "artifacts/flash-old-$(date +%Y%m%d-%H%M)"
  ```

- 目标平台是 ARMv7 EABI5 **softfp**（Cortex-A7，VFPv3-D16），动态加载器为
  `/lib/ld-linux.so.3`。不要改成 hard-float（`-mfloat-abi=hard`）：能编译通过，
  但在盒子上无法运行，编译最后的 ABI 检查也会拒绝。
- 图形走厂商 Mali-450 **fbdev** EGL/GLES，没有 X11、Wayland、DRM/KMS 或 Mesa。
- 不要在 `sdk/` 目录里手动执行 `make build`。厂商 SDK 自带的 `mksquashfs` 在新版
  Linux 上会崩溃，本项目脚本已经用 `IMAGES=extfs` 绕开；确实需要手动执行时，
  参考 `scripts/build-workspace.sh` 里的完整命令。

---

## 10. 更新、重编与清理

### 10.1 更新到仓库最新版本

```bash
cd ~/emuelec-for-hi3798mv100
git pull
./easy-build.sh --setup-only        # 自动把子模块切换到新的固定版本
mv artifacts/flash "artifacts/flash-old-$(date +%Y%m%d-%H%M)" 2>/dev/null || true
HISTB_JOBS=4 ./build-flash-image.sh
```

如果更新后 `WORKSPACE.lock` 里的 SDK 提交号变了，必须完整编译，不要用下面的
跳过 SDK 方式。

### 10.2 只重编一部分

**跳过 SDK，只重编移植层 13 个阶段**（前提：SDK 已经完整编译成功过一次）：

```bash
HISTB_SKIP_SDK_BUILD=1 HISTB_JOBS=4 ./scripts/build-workspace.sh
```

产物位置与完整编译相同，`artifacts/flash/` 中同样会生成 p9 镜像。

**只重编模拟器核心和 TF 目录**（前提：完整编译成功过一次）：

```bash
./easy-build.sh --setup-only        # 若改过 port/，先同步
HISTB_JOBS=4 ./emuelec/tools/histb/build-libretro-cores.sh
./emuelec/tools/histb/stage-runtime.sh
./emuelec/tools/histb/package-tf-card.sh
```

这只更新 `artifacts/tf-card/`，不会更新 p9 镜像。

### 10.3 清理

| 目的 | 命令 | 说明 |
|---|---|---|
| 清掉移植层产物，重新编译 | `rm -rf build artifacts logs` | 保留下载缓存和 SDK 编译结果 |
| 连 SDK 输出一起清掉 | `rm -rf build artifacts logs sdk/out` | 下次必须完整编译，不能用 `HISTB_SKIP_SDK_BUILD=1` |
| 彻底重来 | 先 `mv cache ~/histb-cache-backup`，删除整个仓库目录，重新克隆，再 `mv ~/histb-cache-backup cache` | 移回的下载缓存会重新校验哈希，校验通过就不再下载 |

---

## 11. 常见错误对照表

在终端输出中搜索下表左列的关键字：

| 报错关键字 | 原因 | 解决办法 |
|---|---|---|
| `this script is running outside Linux` | 在 PowerShell、CMD 或 Git Bash 里执行了脚本 | 打开 Ubuntu 终端执行，见 [3.3](#33-以后怎么打开-ubuntu-终端) |
| `not Linux ext4` / `is not the isolated ext filesystem` / `Setup cannot continue: this folder is on ...` | 仓库放在 `/mnt/c`、`/mnt/d` 等 Windows 盘，或 WSL1 | `cd ~` 后重新克隆；确认是 WSL2 |
| `the project path contains spaces` | 路径里有空格 | 移到没有空格的路径，如 `~/emuelec-for-hi3798mv100` |
| `required tools are missing` / `Ubuntu packages are missing` | 缺依赖 | 复制提示里的 `sudo apt install ...` 执行 |
| `only about N GiB is free` | 磁盘不够 | 清理空间；WSL 用户见 [3.5](#35可选c-盘空间不够) |
| `/usr/bin/env: 'bash\r'` 或 `$'\r': command not found` | 文件被转换成了 Windows 换行符（在 Windows 上克隆或解压后复制进来） | 在 Ubuntu 里 `cd ~` 重新 `git clone` |
| `./easy-build.sh: Permission denied` | 可执行权限丢失（同上原因） | 同上，在 Linux 里重新克隆或解压 |
| `Failed to connect to github.com`、`Could not resolve host`、`RPC failed`、`early EOF`、`Operation too slow` | 网络不通或太慢 | 配置代理（[第 5 节](#5-网络与代理国内用户必看)），然后重新运行同一条命令，已完成的部分会保留 |
| `download checksum mismatch` | 下载到的文件内容不对，常见于代理/网络返回了错误页面 | 检查代理后重新运行；文件未通过校验不会被保存 |
| `refusing to overwrite cache file with wrong hash: .../cache/sources/xxx` | 缓存里有一个损坏的文件 | `rm cache/sources/xxx`（用提示里的实际文件名），再重新运行 |
| `refusing to replace non-Git SDK directory` / `non-Git EmuELEC directory` | ZIP 方式下 `sdk/` 或 `emuelec/` 里有残缺内容 | 确认里面没有你自己的文件后，`rm -rf sdk`（或 `emuelec`）再重新运行 |
| `fatal: reference is not a tree` / `SDK checkout mismatch` / `EmuELEC checkout mismatch` | 子模块不在固定提交上（ZIP 方式下上游分支已更新时也会出现） | Git 克隆方式：`git submodule update --init --depth 1 -- sdk emuelec`。ZIP 方式：`git -C sdk fetch --depth 1 origin <WORKSPACE.lock 中的提交号> && git -C sdk checkout --detach <提交号>`（EmuELEC 同理，把 `sdk` 换成 `emuelec`） |
| `SDK board config mismatch` / `pinned SDK configuration checksum mismatch` | SDK 里的板级配置被改动 | `git -C sdk checkout -- configs/` 后重新运行 |
| `SDK rootbox.mak is neither the pinned base nor the expected HiSTB patch state` | 手动改过 `sdk/rootbox.mak` | `git -C sdk checkout -- rootbox.mak` 后重新运行 |
| `refusing to overwrite unmanaged EmuELEC tools/histb` | `emuelec/tools/histb/` 里有不是脚本放进去的文件 | 把该目录移到别处备份后重新运行 |
| `HiSTB cross compiler not found` | SDK 子模块不完整 | `git -C sdk status` 检查；执行 `git submodule update --init --depth 1 -- sdk`，仍不行就重新克隆 |
| 交叉编译器文件明明存在，执行时却提示 `No such file or directory` | 缺 32 位兼容库 | `sudo apt install -y libc6-i386 lib32z1` |
| `Killed`、`internal compiler error: Killed`、`Killed signal terminated program cc1plus` | 内存不足 | 调小 `HISTB_JOBS`（[7.3](#73-并行数与内存)），WSL 用户可加大内存/交换空间（[3.4](#34可选调整内存和-cpu)） |
| 用 `HISTB_SKIP_SDK_BUILD=1` 后在 `[3/13]`–`[5/13]` 找不到厂商头文件或库 | SDK 从未完整编译成功过 | 去掉 `HISTB_SKIP_SDK_BUILD=1`，完整编译一次 |
| `expected one gated p9/rootfs image, found 2` | `artifacts/flash/` 里留着旧版本镜像 | 按 [9.3](#93-修改代码) 把旧的 `artifacts/flash` 移走后重新运行 |
| `hard-float`、`Tag_ABI_VFP_args`、解释器不是 `/lib/ld-linux.so.3` | 编译选项被改成了不兼容的 ABI | 恢复 `port/env.sh` 中的 softfp 设置，不要自行覆盖 `CFLAGS` |
| `mksquashfs` 崩溃 | 手动在 `sdk/` 里执行了 `make build` | 用本项目脚本编译，见 [9.3](#93-修改代码) 最后一条 |

表里没有的错误：往上翻，找到第一个 `error`、`Error` 或 `failed`（而不是最后一行），
那通常才是真正的原因。

---

## 12. 求助时请附带的信息

在 GitHub Issues 提问时，请贴出下面命令的输出，能大幅减少来回询问：

```bash
cd ~/emuelec-for-hi3798mv100
uname -m; lsb_release -ds; stat -f -c %T .
git rev-parse HEAD; git submodule status
./easy-build.sh --check
tail -n 100 logs/histb-emuelec-build-all.log
```

另外请说明：

- 原生 Linux / 虚拟机 / WSL2 中的哪一种；
- 执行的具体命令（包括 `HISTB_JOBS` 等变量）；
- 停在哪个阶段（例如 `[7/13]`），以及报错前后约 50 行输出。

贴日志前请检查，**不要** 贴出密码、私钥或自己的密码哈希。
