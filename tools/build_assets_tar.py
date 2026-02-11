#!/usr/bin/env python3
"""Собирает детерминированный TAR-бандл из каталогов scripts/ и web/."""

from __future__ import annotations

import os
import stat
import sys
import tarfile
from pathlib import Path


def collect_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for path in root.rglob("*"):
        if path.is_file():
            files.append(path)
    files.sort(key=lambda p: p.as_posix())
    return files


def add_file(tf: tarfile.TarFile, path: Path, arcname: str) -> None:
    st = path.stat()
    info = tarfile.TarInfo(name=arcname)
    info.size = st.st_size
    info.mode = stat.S_IMODE(st.st_mode)
    info.uid = 0
    info.gid = 0
    info.uname = ""
    info.gname = ""
    info.mtime = 0
    with path.open("rb") as fh:
        tf.addfile(info, fh)


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: build_assets_tar.py <out.tar> <dir> [<dir> ...]", file=sys.stderr)
        return 2

    out_path = Path(argv[1]).resolve()
    src_dirs = [Path(arg).resolve() for arg in argv[2:]]

    files: list[tuple[Path, str]] = []
    for src in src_dirs:
        if not src.exists() or not src.is_dir():
            print(f"source directory not found: {src}", file=sys.stderr)
            return 1
        base_name = src.name
        for item in collect_files(src):
            rel = item.relative_to(src).as_posix()
            arcname = f"{base_name}/{rel}"
            files.append((item, arcname))

    files.sort(key=lambda item: item[1])

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(out_path, "w", format=tarfile.USTAR_FORMAT) as tf:
        for src, arcname in files:
            add_file(tf, src, arcname)

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
