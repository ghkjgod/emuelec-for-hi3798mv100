#!/usr/bin/env python3
"""Split oversized Android sparse RAW chunks without changing logical bytes."""

from __future__ import annotations

import argparse
import os
import struct
import sys
from pathlib import Path


FILE_HEADER = struct.Struct("<IHHHHIIII")
CHUNK_HEADER = struct.Struct("<HHII")
SPARSE_MAGIC = 0xED26FF3A
RAW_CHUNK = 0xCAC1


def fail(message: str) -> "NoReturn":
    raise SystemExit(message)


def copy_exact(source, destination, size: int) -> None:
    remaining = size
    while remaining:
        data = source.read(min(1024 * 1024, remaining))
        if not data:
            fail("truncated sparse chunk payload")
        destination.write(data)
        remaining -= len(data)


def transform(source_path: Path, destination_path: Path, max_raw_bytes: int) -> None:
    if source_path.resolve() == destination_path.resolve():
        fail("input and output must be different files")
    if destination_path.exists():
        fail(f"refusing to overwrite output: {destination_path}")

    with source_path.open("rb") as source:
        fixed = source.read(FILE_HEADER.size)
        if len(fixed) != FILE_HEADER.size:
            fail("truncated Android sparse header")
        (
            magic,
            major,
            minor,
            file_header_size,
            chunk_header_size,
            block_size,
            total_blocks,
            total_chunks,
            image_checksum,
        ) = FILE_HEADER.unpack(fixed)
        if magic != SPARSE_MAGIC or major != 1:
            fail("input is not an Android sparse v1 image")
        if file_header_size < FILE_HEADER.size or chunk_header_size < CHUNK_HEADER.size:
            fail("invalid sparse header sizes")
        if block_size == 0 or max_raw_bytes < block_size:
            fail("max RAW size must be at least one sparse block")
        max_blocks = max_raw_bytes // block_size
        header_extension = source.read(file_header_size - FILE_HEADER.size)
        if len(header_extension) != file_header_size - FILE_HEADER.size:
            fail("truncated sparse file-header extension")

        temporary = destination_path.with_name(destination_path.name + ".new")
        if temporary.exists():
            fail(f"refusing to overwrite temporary output: {temporary}")
        output_chunks = 0
        logical_blocks = 0
        raw_chunks_split = 0
        largest_input_raw = 0
        try:
            with temporary.open("xb") as destination:
                destination.write(fixed)
                destination.write(header_extension)
                for _ in range(total_chunks):
                    chunk_fixed = source.read(CHUNK_HEADER.size)
                    if len(chunk_fixed) != CHUNK_HEADER.size:
                        fail("truncated sparse chunk header")
                    chunk_type, reserved, chunk_blocks, total_size = CHUNK_HEADER.unpack(chunk_fixed)
                    chunk_extension = source.read(chunk_header_size - CHUNK_HEADER.size)
                    if len(chunk_extension) != chunk_header_size - CHUNK_HEADER.size:
                        fail("truncated sparse chunk-header extension")
                    if total_size < chunk_header_size:
                        fail("invalid sparse chunk total size")
                    payload_size = total_size - chunk_header_size
                    logical_blocks += chunk_blocks

                    if chunk_type == RAW_CHUNK:
                        expected_size = chunk_blocks * block_size
                        if payload_size != expected_size:
                            fail("RAW sparse chunk payload size mismatch")
                        largest_input_raw = max(largest_input_raw, payload_size)
                        remaining_blocks = chunk_blocks
                        if remaining_blocks > max_blocks:
                            raw_chunks_split += 1
                        while remaining_blocks:
                            part_blocks = min(remaining_blocks, max_blocks)
                            part_bytes = part_blocks * block_size
                            destination.write(
                                CHUNK_HEADER.pack(
                                    chunk_type,
                                    reserved,
                                    part_blocks,
                                    chunk_header_size + part_bytes,
                                )
                            )
                            destination.write(chunk_extension)
                            copy_exact(source, destination, part_bytes)
                            output_chunks += 1
                            remaining_blocks -= part_blocks
                    else:
                        destination.write(chunk_fixed)
                        destination.write(chunk_extension)
                        copy_exact(source, destination, payload_size)
                        output_chunks += 1

                if source.read(1):
                    fail("trailing data after declared sparse chunks")
                if logical_blocks != total_blocks:
                    fail("declared and reconstructed sparse block counts differ")

                destination.seek(0)
                destination.write(
                    FILE_HEADER.pack(
                        magic,
                        major,
                        minor,
                        file_header_size,
                        chunk_header_size,
                        block_size,
                        total_blocks,
                        output_chunks,
                        image_checksum,
                    )
                )
                destination.flush()
                os.fsync(destination.fileno())
            os.replace(temporary, destination_path)
        finally:
            if temporary.exists():
                temporary.unlink()

    print("result=PASS")
    print(f"block_size={block_size}")
    print(f"logical_blocks={total_blocks}")
    print(f"input_chunks={total_chunks}")
    print(f"output_chunks={output_chunks}")
    print(f"raw_chunks_split={raw_chunks_split}")
    print(f"largest_input_raw_bytes={largest_input_raw}")
    print(f"max_output_raw_bytes={max_blocks * block_size}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--max-raw-bytes", type=int, default=4 * 1024 * 1024)
    args = parser.parse_args()
    transform(args.input, args.output, args.max_raw_bytes)


if __name__ == "__main__":
    main()
