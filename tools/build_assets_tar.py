#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Собирает детерминированный TAR-бандл из каталогов scripts/ и web/.

Важно:
- Совместим с Python 2.7 (CentOS 7) и Python 3.x.
- Детерминированность достигается сортировкой файлов и фиксацией mtime/uid/gid.
"""

from __future__ import print_function

import os
import stat
import sys
import tarfile


def collect_files(root_dir):
    files = []
    for dirpath, dirnames, filenames in os.walk(root_dir):
        # Упорядочиваем обход, чтобы получался стабильный результат.
        dirnames.sort()
        filenames.sort()
        for name in filenames:
            files.append(os.path.join(dirpath, name))
    return files


def add_file(tf, path, arcname):
    st = os.stat(path)
    info = tarfile.TarInfo(name=arcname)
    info.size = st.st_size
    info.mode = stat.S_IMODE(st.st_mode)
    info.uid = 0
    info.gid = 0
    info.uname = ""
    info.gname = ""
    info.mtime = 0
    fh = open(path, "rb")
    try:
        tf.addfile(info, fh)
    finally:
        fh.close()


def mkdir_p(path):
    if not path:
        return
    try:
        os.makedirs(path)
    except OSError:
        if not os.path.isdir(path):
            raise


def main(argv):
    if len(argv) < 3:
        print("usage: build_assets_tar.py <out.tar> <dir> [<dir> ...]", file=sys.stderr)
        return 2

    out_path = os.path.abspath(argv[1])
    src_dirs = [os.path.abspath(arg) for arg in argv[2:]]

    files = []
    for src in src_dirs:
        if not os.path.isdir(src):
            print("source directory not found: {}".format(src), file=sys.stderr)
            return 1

        base_name = os.path.basename(src.rstrip(os.sep))
        for item in collect_files(src):
            rel = os.path.relpath(item, src)
            rel = rel.replace(os.sep, "/")
            arcname = "{}/{}".format(base_name, rel)
            files.append((item, arcname))

    files.sort(key=lambda it: it[1])

    mkdir_p(os.path.dirname(out_path))

    tf = tarfile.open(out_path, "w", format=tarfile.USTAR_FORMAT)
    try:
        for src, arcname in files:
            add_file(tf, src, arcname)
    finally:
        tf.close()

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
