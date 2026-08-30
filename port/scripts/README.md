# Offline complete-image assembly

`assemble_user_area.py` creates a regular file only. It does not contain a
flashing implementation and refuses to overwrite existing output.

The nine inputs must be raw, expanded images of the exact audited logical
sizes: 1, 1, 4, 4, 4, 20, 64, 512 and 6846 MiB. Android sparse ext4 inputs must
first be expanded with a compatible `simg2img`. Supply p1-p8 only from the same
board layout and a lawful backup; use the freshly built p9 rootfs for p9.

```sh
python3 scripts/assemble_user_area.py \
  --p1 p1.raw --p2 p2.raw --p3 p3.raw --p4 p4.raw --p5 p5.raw \
  --p6 p6.raw --p7 p7.raw --p8 p8.raw --p9 p9.raw \
  --output EC6108V9C-user-area.raw
```

The result is 7,818,182,656 bytes and is accompanied by a JSON manifest with
per-partition and whole-image SHA-256 values. The partition table, boot0,
boot1, and RPMB are not represented. Review the manifest and use a separately
qualified recovery/write process; this repository does not authorize a write.
