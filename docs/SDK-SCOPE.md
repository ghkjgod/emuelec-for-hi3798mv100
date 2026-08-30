# SDK scope, provenance, and publication boundary

This workspace records the HiSTBLinux SDK as a Git submodule at commit
`fd20f78ab02934e71474dbb1d933c6ec911b01c9`. The SDK is fetched directly from
its public upstream repository. Its files are not copied into this project's
Git object database and are not relicensed under 0BSD.

The checkout is the complete upstream tree needed by the build, including the
vendor cross-toolchain, kernel/BSP sources, Mali userspace inputs, host tools,
and examples. A clean checkout does not include this project's generated
`out/`, rootfs, images, caches, logs, or device backups; those are built locally
and remain ignored.

The upstream SDK contains security-sensitive example areas and vendor tooling,
including CA/OTP/HDCP/DRM provisioning samples, sample certificates/keys, and
Windows flashing utilities. They are not used by this EmuELEC build. Do not
replace sample material with production credentials, do not commit generated
keys, and do not publish device-unique data. Review the SDK's own terms before
redistributing it or any vendor binaries.

The supported workflow changes only two SDK worktree files: `cfg.mak` is
regenerated from the pinned board config with a 6846 MiB rootfs, and
`rootbox.mak` receives `port/patches/SDK-rootbox-HiSTB.patch` to compose the
EmuELEC overlay. Bootstrap verifies the exact SDK commit and config SHA-256
first. Build scripts create ordinary files only and never access or flash a
device.
