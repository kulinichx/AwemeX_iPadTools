#!/usr/bin/env python3
from __future__ import annotations
import argparse
import io
import os
from pathlib import Path
import tarfile
import time

AR_MAGIC = b"!<arch>\n"

def tar_gz_single(files: list[tuple[str, bytes, int]]) -> bytes:
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz", format=tarfile.GNU_FORMAT) as tf:
        for name, data, mode in files:
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = mode
            info.mtime = 0
            info.uid = 0
            info.gid = 0
            info.uname = "root"
            info.gname = "root"
            tf.addfile(info, io.BytesIO(data))
    return buf.getvalue()

def ar_member(name: str, data: bytes) -> bytes:
    # SysV/GNU ar short-name header, sufficient for Debian's three canonical members.
    nm = (name + "/").encode("ascii")
    if len(nm) > 16:
        raise ValueError(f"ar member name too long: {name}")
    header = (
        nm.ljust(16, b" ") +
        b"0".ljust(12, b" ") +
        b"0".ljust(6, b" ") +
        b"0".ljust(6, b" ") +
        b"100644".ljust(8, b" ") +
        str(len(data)).encode("ascii").ljust(10, b" ") +
        b"`\n"
    )
    out = header + data
    if len(data) & 1:
        out += b"\n"
    return out

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dylib", required=True)
    ap.add_argument("--plist", required=True)
    ap.add_argument("--control", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    dylib = Path(args.dylib).read_bytes()
    plist = Path(args.plist).read_bytes()
    control = Path(args.control).read_bytes()

    control_tar = tar_gz_single([("./control", control, 0o644)])
    data_tar = tar_gz_single([
        ("./Library/MobileSubstrate/DynamicLibraries/AwemeX_iPadCompat.dylib", dylib, 0o755),
        ("./Library/MobileSubstrate/DynamicLibraries/AwemeX_iPadCompat.plist", plist, 0o644),
    ])

    out = bytearray(AR_MAGIC)
    out += ar_member("debian-binary", b"2.0\n")
    out += ar_member("control.tar.gz", control_tar)
    out += ar_member("data.tar.gz", data_tar)
    Path(args.output).write_bytes(out)
    print(f"WROTE {args.output} ({len(out)} bytes)")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
