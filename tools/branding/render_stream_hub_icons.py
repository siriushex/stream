#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Генерация PNG/ICO иконок Stream Hub из SVG без внешних сервисов.

Поддерживает базовые SVG-примитивы:
- rect
- line
- circle

Использование:
  python3 tools/branding/render_stream_hub_icons.py \
      --svg web/assets/icons/stream-hub.svg \
      --out web/assets/icons
"""

from __future__ import annotations

import argparse
import pathlib
import re
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw

SIZES = [16, 32, 48, 64, 96, 128, 180, 192, 256, 512]


def _hex_to_rgba(value: str | None) -> tuple[int, int, int, int]:
    if value is None:
        return (0, 0, 0, 0)
    color = value.strip()
    if color.lower() == "none":
        return (0, 0, 0, 0)
    if not color.startswith("#"):
        raise ValueError(f"Unsupported color format: {value}")
    raw = color[1:]
    if len(raw) == 3:
        raw = "".join(ch * 2 for ch in raw)
    if len(raw) == 6:
        raw += "ff"
    if len(raw) != 8:
        raise ValueError(f"Unsupported color format: {value}")
    return tuple(int(raw[i : i + 2], 16) for i in range(0, 8, 2))  # type: ignore[return-value]


def _parse_viewbox(svg: ET.Element) -> tuple[float, float, float, float]:
    view_box = svg.attrib.get("viewBox")
    if not view_box:
        raise ValueError("SVG viewBox is required")
    parts = re.split(r"[\s,]+", view_box.strip())
    if len(parts) != 4:
        raise ValueError(f"Invalid viewBox: {view_box}")
    return tuple(float(p) for p in parts)  # type: ignore[return-value]


def _scale(value: float, offset: float, factor: float) -> float:
    return (value - offset) * factor


def render(svg_path: pathlib.Path, out_dir: pathlib.Path) -> None:
    tree = ET.parse(svg_path)
    root = tree.getroot()
    _, _, vw, vh = _parse_viewbox(root)
    if vw <= 0 or vh <= 0:
        raise ValueError("Invalid viewBox dimensions")

    out_dir.mkdir(parents=True, exist_ok=True)

    ns_suffix = "}"

    for size in SIZES:
        scale_x = size / vw
        scale_y = size / vh

        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img, "RGBA")

        for node in root:
            tag = node.tag.split(ns_suffix)[-1]
            if tag == "rect":
                x = _scale(float(node.attrib.get("x", "0")), 0, scale_x)
                y = _scale(float(node.attrib.get("y", "0")), 0, scale_y)
                w = float(node.attrib.get("width", "0")) * scale_x
                h = float(node.attrib.get("height", "0")) * scale_y
                rx = float(node.attrib.get("rx", "0")) * min(scale_x, scale_y)
                fill = _hex_to_rgba(node.attrib.get("fill"))
                draw.rounded_rectangle([x, y, x + w, y + h], radius=rx, fill=fill)
            elif tag == "line":
                x1 = _scale(float(node.attrib.get("x1", "0")), 0, scale_x)
                y1 = _scale(float(node.attrib.get("y1", "0")), 0, scale_y)
                x2 = _scale(float(node.attrib.get("x2", "0")), 0, scale_x)
                y2 = _scale(float(node.attrib.get("y2", "0")), 0, scale_y)
                stroke = _hex_to_rgba(node.attrib.get("stroke"))
                width = max(1, round(float(node.attrib.get("stroke-width", "1")) * min(scale_x, scale_y)))
                draw.line([x1, y1, x2, y2], fill=stroke, width=width)
            elif tag == "circle":
                cx = _scale(float(node.attrib.get("cx", "0")), 0, scale_x)
                cy = _scale(float(node.attrib.get("cy", "0")), 0, scale_y)
                r = float(node.attrib.get("r", "0")) * min(scale_x, scale_y)
                fill = _hex_to_rgba(node.attrib.get("fill"))
                draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)

        png_name = f"stream-hub-{size}.png"
        img.save(out_dir / png_name, format="PNG", optimize=True)
        if size == 180:
            img.save(out_dir / "apple-touch-icon.png", format="PNG", optimize=True)

    ico_src_48 = Image.open(out_dir / "stream-hub-48.png")
    favicon_path = out_dir.parent.parent / "favicon.ico"
    ico_src_48.save(favicon_path, format="ICO", sizes=[(16, 16), (32, 32), (48, 48)])


def main() -> None:
    parser = argparse.ArgumentParser(description="Render Stream Hub icon set from SVG")
    parser.add_argument("--svg", default="web/assets/icons/stream-hub.svg", help="Path to source SVG")
    parser.add_argument("--out", default="web/assets/icons", help="Output directory for PNG icons")
    args = parser.parse_args()

    svg_path = pathlib.Path(args.svg).resolve()
    out_dir = pathlib.Path(args.out).resolve()

    render(svg_path, out_dir)
    print(f"OK: generated icons in {out_dir}")


if __name__ == "__main__":
    main()
