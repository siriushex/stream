#!/usr/bin/env python3
"""Собирает детерминированный TAR-бандл из каталогов scripts/ и web/."""

import os
import stat
import sys
import tarfile
from pathlib import Path


def collect_files(root):
    # Python 3.5 compatible (Ubuntu 16.04 build image uses python3.5).
    files = []
    for dirpath, _, filenames in os.walk(str(root)):
        for name in filenames:
            files.append(Path(dirpath) / name)
    files.sort(key=lambda p: p.as_posix())
    return files


def add_file(tf, path, arcname):
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


def main(argv):
    if len(argv) < 3:
        print("usage: build_assets_tar.py <out.tar> <dir> [<dir> ...]", file=sys.stderr)
        return 2

    # Path.resolve() в Python 3.5 падает, если файл ещё не существует.
    # Нам нужен просто абсолютный путь.
    out_path = Path(os.path.abspath(argv[1]))
    src_dirs = [Path(os.path.abspath(arg)) for arg in argv[2:]]

    files = []
    for src in src_dirs:
        if not src.exists() or not src.is_dir():
            print("source directory not found: {}".format(src), file=sys.stderr)
            return 1
        base_name = src.name
        for item in collect_files(src):
            rel = item.relative_to(src).as_posix()
            arcname = "{}/{}".format(base_name, rel)
            files.append((item, arcname))

    files.sort(key=lambda item: item[1])

    out_path.parent.mkdir(parents=True, exist_ok=True)
    # Python 3.5 tarfile.open не принимает pathlib.Path.
    with tarfile.open(str(out_path), "w", format=tarfile.USTAR_FORMAT) as tf:
        for src, arcname in files:
            add_file(tf, src, arcname)

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
