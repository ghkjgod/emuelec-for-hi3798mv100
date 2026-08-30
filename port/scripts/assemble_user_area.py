#!/usr/bin/env python3
"""Assemble an offline EC6108V9C p1-p9 user-area image.

Inputs must already be raw, expanded partition images with the exact audited
logical sizes. This tool never opens a block device and never flashes hardware.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path


MIB = 1024 * 1024
PARTITIONS = (
    ("p1", 0, 1),
    ("p2", 1, 1),
    ("p3", 2, 4),
    ("p4", 6, 4),
    ("p5", 10, 4),
    ("p6", 14, 20),
    ("p7", 34, 64),
    ("p8", 98, 512),
    ("p9", 610, 6846),
)
TOTAL_BYTES = 7456 * MIB
CHUNK_BYTES = 8 * MIB


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(CHUNK_BYTES), b""):
            digest.update(chunk)
    return digest.hexdigest()


def copy_exact(source: Path, destination, expected_bytes: int) -> str:
    digest = hashlib.sha256()
    copied = 0
    with source.open("rb") as stream:
        while copied < expected_bytes:
            chunk = stream.read(min(CHUNK_BYTES, expected_bytes - copied))
            if not chunk:
                raise RuntimeError(f"short input: {source}")
            destination.write(chunk)
            digest.update(chunk)
            copied += len(chunk)
        if stream.read(1):
            raise RuntimeError(f"oversized input: {source}")
    return digest.hexdigest()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="assemble a raw p1-p9 user-area file; no device writes"
    )
    for name, _, _ in PARTITIONS:
        parser.add_argument(f"--{name}", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--manifest",
        type=Path,
        help="JSON result path (default: OUTPUT.manifest.json)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output = args.output.resolve()
    manifest = (args.manifest or Path(f"{output}.manifest.json")).resolve()
    if output.exists() or manifest.exists():
        raise RuntimeError("refusing to overwrite output or manifest")

    inputs = {}
    for name, offset_mib, size_mib in PARTITIONS:
        path = getattr(args, name).resolve()
        expected = size_mib * MIB
        actual = path.stat().st_size
        if actual != expected:
            raise RuntimeError(
                f"{name} size mismatch: expected {expected}, got {actual}: {path}"
            )
        inputs[name] = (path, offset_mib * MIB, expected)

    output.parent.mkdir(parents=True, exist_ok=True)
    records = []
    try:
        with output.open("xb") as destination:
            destination.truncate(TOTAL_BYTES)
            for name, _, _ in PARTITIONS:
                path, offset, size = inputs[name]
                destination.seek(offset)
                digest = copy_exact(path, destination, size)
                records.append(
                    {
                        "partition": name,
                        "offset": offset,
                        "size": size,
                        "source": str(path),
                        "source_sha256": digest,
                    }
                )
            destination.flush()
            os.fsync(destination.fileno())

        result = {
            "schema_version": 1,
            "target": "EC6108V9C/Hi3798MV100 audited p1-p9 user area",
            "output": str(output),
            "output_bytes": output.stat().st_size,
            "output_sha256": sha256_file(output),
            "partition_table_included": False,
            "boot0_boot1_rpmb_included": False,
            "partitions": records,
        }
        manifest.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(result, indent=2))
    except BaseException:
        output.unlink(missing_ok=True)
        manifest.unlink(missing_ok=True)
        raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
