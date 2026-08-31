# TF 卡使用说明

这份说明只涉及游戏、BIOS、配置和模拟器核心文件。系统不会格式化 TF 卡，
不会修改分区表，也不会向内置 eMMC 的其他分区写入这些内容。

## 支持范围

- 首选 ext4；FAT32 也支持；exFAT 只有在当前内核列出 exFAT 支持时才会挂载。
- 开机前插卡是正式支持路径。运行中插入后可执行
  `/usr/bin/histb-tf-storage rescan`，然后重启 EmulationStation 让它重新扫描。
- 稳定挂载点是 `/media/emuelec-tf`，但设备名不会永久写死为
  `/dev/mmcblk1`。
- 配置了 UUID 时按 UUID 选择；否则可按标签选择。两者都没有时，仅接受内核
  明确报告为 `SD` 的唯一外置分区。
- 内置 rootfs 所在的 eMMC 父设备会被明确排除。多个外置分区同时匹配时拒绝
  自动选择，并提示配置 UUID/标签。

## 准备目录

最省事的方式是把仓库中已经按目标目录组织好的 `tf-card/EmuELEC` 整个复制到
TF 卡根目录；完整构建也会在 `artifacts/tf-card/` 生成同结构、与本次核心
完全对应的包。随后自行创建 `bios/`、`roms/` 并加入自己合法持有的文件。

最终结构如下：

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

不要把商业 ROM 或版权不明 BIOS 提交到 Git。PSX 的 `.cue` 文件必须正确引用
同目录中的数据轨文件；`arcade`/`mame` 的 ROM 集要与 MAME 2003-Plus 兼容，
`fbneo`/`pgm2` 的 ROM 集要与本配方固定的 FinalBurn Neo 版本兼容。

建议把卷标设置为 `EMUELEC`。也可以在目标系统的
`/etc/default/histb-tf-storage` 中设置：

```sh
HISTB_TF_UUID='你的文件系统 UUID'
# 或
HISTB_TF_LABEL='EMUELEC'
```

UUID 的优先级高于标签。可以用 `blkid` 查看实际 UUID/标签。

## 游戏和 BIOS 怎样被使用

TF 卡挂载成功后，ES 中会出现名字以 `TF Card -` 开头的系统。启动游戏时日志
应包含：

```text
HiSTB launch ROM source=tf path=/media/emuelec-tf/EmuELEC/roms/...
```

从 TF 启动的游戏优先使用 `EmuELEC/bios/`。目录不存在时回退到内置
`/storage/roms/bios`。存档、即时存档、截图和播放列表始终写到内置 `/storage`，
减少意外拔卡对系统状态的影响。

## 手柄数据库与回退

rootfs 在 `/opt/emuelec/share/sdl/gamecontrollerdb.txt` 固化了一份固定提交、经过
校验的 SDL 手柄数据库，这是始终可用的回退版本。TF 成品目录另带：

```text
EmuELEC/config/gamecontrollerdb.txt
EmuELEC/config/gamecontrollerdb.sha256
```

启动 EmulationStation 和 RetroArch 前，选择器会限制文件大小、验证 SHA-256，
并检查数据库至少含合法 Linux 映射。TF 副本全部通过才会使用；文件缺失、清单
格式错误、哈希不符或内容损坏时只记录原因，并自动回退到 rootfs 固化版本。
因此可通过替换这两个 TF 文件升级，也可删除它们立即回退。

## 从 TF 使用模拟器核心

核心文件名必须是仓库支持的标准名字，例如：

```text
EmuELEC/cores/fceumm_libretro.so
EmuELEC/cores/snes9x2010_libretro.so
```

在 `EmuELEC/cores` 目录生成清单：

```bash
cd EmuELEC/cores
sha256sum *_libretro.so > cores.sha256
```

选择器会逐项检查：

1. 文件名属于 10 个支持核心之一；
2. `cores.sha256` 中恰好有一条对应记录且内容哈希相同；
3. 文件是 32 位 little-endian ARM ELF，且没有 hard-float ABI 标志；
4. 在目标机上用同一动态加载器执行 `dlopen(RTLD_NOW)`，依赖完整并含必要的
   libretro 入口函数。

任何检查失败都会显示原因并回退到内置核心，ES 仍可继续使用。

### ext4：直接加载

默认 `auto` 模式下，ext4 以 `nodev,nosuid,exec` 挂载。检查通过后 RetroArch
直接使用卡上的 `.so`，日志包含 `source=direct-tf`。验收时还应在游戏运行中
检查 `/proc/<RetroArch PID>/maps`，确认映射路径确实位于
`/media/emuelec-tf/EmuELEC/cores`。

### FAT32/exFAT：校验后导入缓存

FAT32/exFAT 默认使用 `nodev,nosuid,noexec`。核心检查通过后复制到：

```text
/storage/ee/core-cache/<核心名>/<SHA-256>.so
```

日志包含 `source=tf-cache`。这不是直接从 TF 执行。旧哈希文件不会被覆盖，
把 `cores.sha256` 和核心恢复成之前版本即可回滚。

可在 `/etc/default/histb-tf-storage` 把模式设为 `cache`、`direct` 或
`disabled`。即使要求 `direct`，FAT/exFAT 仍会为了可靠性转为缓存模式。

## 拔卡和故障

- 开机没有卡：记录提示后继续使用内置游戏/核心。
- 文件系统不受支持或损坏：只报告精确问题，不自动修复或格式化。
- 核心错误：回退内置核心，不让 ES 陷入重启循环。
- 缺少 BIOS：RetroArch/核心会报告 BIOS 问题；系统不会下载 BIOS。
- 游戏运行中拔卡：RetroArch 可能退出；启动器会说明卡已移除并返回 ES。
  内置系统和存档目录不在 TF 上，因此不会破坏 rootfs。
- 重新插卡：执行 `histb-tf-storage rescan`，确认 `status` 为 `mounted=1`，
  再重启 ES。不要在游戏进程仍占用卡时强制卸载。

诊断命令：

```sh
/usr/bin/histb-tf-storage status
cat /var/run/histb-tf-storage.env
cat /proc/filesystems
cat /proc/partitions
mount | grep /media/emuelec-tf
```
