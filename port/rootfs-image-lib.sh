#!/usr/bin/env bash

# Shared host-side helpers for Android sparse rootfs generation and audit.
# This file must be sourced after env.sh.

HISTB_LIBSPARSE_ARCHIVE_SHA256=f3a98dd4a94e38cfac46300a54479b8ca81491cbb6eedbc39c6e7141740f650f

histb_prepare_sparse_tools()
{
  local archive tool_parent tool_root incoming actual_sha host_zlib
  local compiler_id machine_id zlib_sha expected_stamp

  archive="${HISTB_SDK_ROOT}/third_party/open_source/libsparse.tar.bz2"
  tool_parent="${HISTB_WORK_ROOT}/cache/tools"
  tool_root="${tool_parent}/libsparse-host"
  incoming="${tool_parent}/.libsparse-host.incoming-$$"

  case "${tool_root}" in
    "${HISTB_WORK_ROOT}/cache/tools/"*) ;;
    *) echo "unsafe libsparse cache path: ${tool_root}" >&2; return 1 ;;
  esac
  for command_name in gcc make ar ranlib tar sha256sum file; do
    command -v "${command_name}" >/dev/null || {
      echo "missing host command for sparse tools: ${command_name}" >&2
      return 1
    }
  done

  actual_sha="$(sha256sum "${archive}" | awk '{print $1}')"
  if [[ "${actual_sha}" != "${HISTB_LIBSPARSE_ARCHIVE_SHA256}" ]]; then
    echo "vendor libsparse archive checksum mismatch: ${actual_sha}" >&2
    return 1
  fi
  host_zlib="$(gcc -print-file-name=libz.so)"
  case "${host_zlib}" in /*) ;; *)
    echo "host gcc cannot locate libz.so: ${host_zlib}" >&2
    return 1
    ;;
  esac
  [[ -f "${host_zlib}" ]] || {
    echo "host libz.so is missing: ${host_zlib}" >&2
    return 1
  }
  compiler_id="$(gcc --version | sed -n '1p')"
  machine_id="$(gcc -dumpmachine)"
  zlib_sha="$(sha256sum "${host_zlib}" | awk '{print $1}')"
  expected_stamp="archive_sha256=${actual_sha}
compiler=${compiler_id}
machine=${machine_id}
zlib_sha256=${zlib_sha}"

  if [[ ! -x "${tool_root}/simg2img" || ! -x "${tool_root}/img2simg" ||
        ! -f "${tool_root}/BUILD-STAMP" ||
        "$(cat "${tool_root}/BUILD-STAMP" 2>/dev/null || true)" != "${expected_stamp}" ]]; then
    rm -rf -- "${incoming}"
    mkdir -p "${incoming}"
    if ! tar -tjf "${archive}" | awk '
      index($0, "./libsparse/") != 1 || $0 ~ /(^|\/)\.\.($|\/)/ { bad=1 }
      END { exit bad ? 1 : 0 }
    '; then
      echo "vendor libsparse archive contains an unsafe path" >&2
      rm -rf -- "${incoming}"
      return 1
    fi
    tar -xjf "${archive}" -C "${incoming}"
    make -C "${incoming}/libsparse" -j1 \
      CC=gcc AR=ar RANLIB=ranlib CFLAGS= LDFLAGS= AM_LDFLAGS= \
      ZLIB="${host_zlib}" simg2img img2simg
    file "${incoming}/libsparse/simg2img" | grep -q 'ELF .* executable' || {
      echo "host simg2img build is not an ELF executable" >&2
      rm -rf -- "${incoming}"
      return 1
    }
    printf '%s\n' "${expected_stamp}" >"${incoming}/libsparse/BUILD-STAMP"
    rm -rf -- "${tool_root}"
    mv "${incoming}/libsparse" "${tool_root}"
    rmdir "${incoming}"
  fi

  export HISTB_SIMG2IMG="${tool_root}/simg2img"
  export HISTB_IMG2SIMG="${tool_root}/img2simg"
}
