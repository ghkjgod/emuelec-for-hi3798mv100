#!/usr/bin/env python3
"""Exercise ES's escaped %ROM% placeholder through a real POSIX shell.

FileData.cpp in pinned ES 2afe6efe substitutes getEscapedPath(getPath()).
FileSystemUtil.cpp escapes the characters below. Wrapping that placeholder
in additional quotes changes the argument received by the launcher.
No target processes, files, or hardware are used by this regression test.
"""

import argparse
import subprocess
import xml.etree.ElementTree as ET


def es_escape(path):
    # Match the pinned upstream getEscapedPath POSIX branch, including order.
    for character in "\\ '\"!$^&*(){}[]?;<>":
        start = 0
        while True:
            offset = path.find(character, start)
            if offset < 0:
                break
            start = offset + 1
            if offset == 0 or path[offset - 1] != "\\":
                path = path[:offset] + "\\" + path[offset:]
                start += 1
    return path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("config")
    args = parser.parse_args()
    systems = ET.parse(args.config).getroot().findall("system")
    expected = {
        "nes": "fceumm", "snes": "snes9x2010", "gb": "gambatte",
        "gba": "gpsp", "gba-mgba": "mgba", "megadrive": "picodrive",
        "pce": "mednafen_pce_fast", "psx": "pcsx_rearmed",
        "arcade": "mame2003_plus", "fbneo": "fbneo",
        "mame": "mame2003_plus", "pgm2": "fbneo", "diagnostics": None,
        "tf-nes": "fceumm", "tf-snes": "snes9x2010",
        "tf-gb": "gambatte", "tf-gba": "gpsp", "tf-gba-mgba": "mgba",
        "tf-megadrive": "picodrive",
        "tf-pce": "mednafen_pce_fast", "tf-psx": "pcsx_rearmed",
        "tf-arcade": "mame2003_plus", "tf-fbneo": "fbneo",
        "tf-mame": "mame2003_plus", "tf-pgm2": "fbneo",
        "tf-nesh": "fceumm", "tf-famicom": "fceumm",
    }
    if {node.findtext("name") for node in systems} != set(expected):
        raise AssertionError("unexpected ES systems")
    names = (
        "plain.nes", "240p Test Mini v0.23.nes", "测试游戏.nes",
        "Game (World) [v1].nes", "Player's Game.nes", 'Game "Deluxe".nes',
        "Price$10;part&two.nes", "braces{}!^star*question?<>.nes",
    )
    checks = 0
    for node in systems:
        name = node.findtext("name")
        core = expected[name]
        command = node.findtext("command") or ""
        if core is None:
            prefix = "/bin/sh"
            wanted_command = prefix + " %ROM%"
        else:
            prefix = "${HISTB_EE_ROOT}/bin/run-retroarch.sh"
            wanted_command = prefix + " " + core + " %ROM%"
        for filename in names:
            rom = (node.findtext("path") or "") + "/" + filename
            rendered = command.replace(prefix, "printf '%s\\0'", 1)
            rendered = rendered.replace("%ROM%", es_escape(rom))
            result = subprocess.run(
                ["/bin/sh", "-c", rendered], check=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            actual = result.stdout.split(b"\0")[:-1]
            wanted = ([core.encode()] if core else []) + [rom.encode()]
            if actual != wanted:
                raise AssertionError(f"{name}: {filename!r}: {actual!r} != {wanted!r}")
            checks += 1
        if command != wanted_command:
            raise AssertionError(f"{name}: incorrect escaped-ROM command {command!r}")
    print(f"PASS: {checks} real-shell argv checks across {len(systems)} ES systems")


if __name__ == "__main__":
    main()
