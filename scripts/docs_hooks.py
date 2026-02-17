#!/usr/bin/env python3
"""MkDocs hooks for docs post-processing."""

from __future__ import annotations

import gzip
from pathlib import Path
import xml.etree.ElementTree as ET


SITEMAP_NS = "http://www.sitemaps.org/schemas/sitemap/0.9"


def _remove_admin_urls_from_sitemap(sitemap_path: Path) -> int:
    tree = ET.parse(sitemap_path)
    root = tree.getroot()
    ns_loc = f"{{{SITEMAP_NS}}}loc"
    ns_url = f"{{{SITEMAP_NS}}}url"

    removed = 0
    for url_node in list(root.findall(ns_url)):
        loc = url_node.find(ns_loc)
        loc_value = (loc.text or "").strip() if loc is not None else ""
        if "/admin/" in loc_value:
            root.remove(url_node)
            removed += 1

    if removed:
        tree.write(sitemap_path, encoding="utf-8", xml_declaration=True)
    return removed


def _rewrite_gzip_copy(sitemap_path: Path, gzip_path: Path) -> None:
    payload = sitemap_path.read_bytes()
    with gzip.open(gzip_path, "wb") as fp:
        fp.write(payload)


def on_post_build(config) -> None:
    site_dir = Path(config["site_dir"])
    sitemap = site_dir / "sitemap.xml"
    sitemap_gz = site_dir / "sitemap.xml.gz"

    if not sitemap.exists():
        print("[docs-hooks] sitemap.xml not found; skipping")
        return

    removed = _remove_admin_urls_from_sitemap(sitemap)
    if removed:
        if sitemap_gz.exists():
            _rewrite_gzip_copy(sitemap, sitemap_gz)
        print(f"[docs-hooks] removed {removed} admin URL(s) from sitemap")
    else:
        print("[docs-hooks] no admin URLs found in sitemap")
