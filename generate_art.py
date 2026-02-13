#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
generate_art.py

Генерация ассетов по manifest JSON через OpenAI Images API.

Что улучшено под твои задачи:
- Поддержка style_profile/style_preset (например: diary_cookie_ui).
- Поддержка negative_prompt (добавляется в конец prompt как запреты).
- Строгая прозрачность: если background=transparent -> используем только gpt-image модели.
- Проверка "есть ли прозрачность" внутри PNG (без Pillow).
- quality всегда форсится в low (иконки).

Важно:
- Для прозрачного фона используем background="transparent" и output_format="png".
- Для гарантии прозрачности лучше использовать model: gpt-image-1 (или другую gpt-image*).
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import struct
from pathlib import Path
from typing import Any, Dict, List, Optional

import requests

IMAGES_URL = "https://api.openai.com/v1/images/generations"
MAX_IMAGE_DIM = 1536

PNG_SIG = b"\x89PNG\r\n\x1a\n"


# -----------------------------
# Утилиты
# -----------------------------

def normalize_model(model: Optional[str]) -> str:
    return (model or "").strip()


def parse_model_list(raw: Optional[str]) -> List[str]:
    if not raw:
        return []
    parts: List[str] = []
    for chunk in raw.split(","):
        m = normalize_model(chunk)
        if m:
            parts.append(m)
    return parts


def model_supports_background(model: str) -> bool:
    # Прозрачный фон гарантированно поддерживают gpt-image* модели
    return normalize_model(model).startswith("gpt-image")


def map_quality_for_model(quality: str, model: str) -> Optional[str]:
    """
    quality: low|medium|high
    Для dall-e-3: standard/hd
    Для gpt-image*: low|medium|high (как есть)
    """
    quality = (quality or "").strip().lower()
    model = normalize_model(model)
    if not quality:
        return None
    if model == "dall-e-3":
        return "hd" if quality == "high" else "standard"
    if model == "dall-e-2":
        return None
    return quality


def parse_size(size: str) -> Optional[tuple[int, int]]:
    if not size or "x" not in size:
        return None
    try:
        w, h = size.lower().split("x", 1)
        return int(w), int(h)
    except ValueError:
        return None


def enforce_max_size(size: str, max_dim: int = MAX_IMAGE_DIM) -> str:
    parsed = parse_size(size)
    if not parsed:
        return "1024x1024"
    w, h = parsed
    if w > max_dim or h > max_dim:
        return "1024x1024"
    return size


def size_from_asset(asset: Dict[str, Any], default_size: str) -> str:
    size = str(asset.get("size") or "").strip()
    if size:
        return enforce_max_size(size)
    size_px = asset.get("size_px")
    if isinstance(size_px, dict):
        w = size_px.get("w") or size_px.get("width")
        h = size_px.get("h") or size_px.get("height")
        try:
            if w and h:
                return enforce_max_size(f"{int(w)}x{int(h)}")
        except (TypeError, ValueError):
            pass
    return default_size


def build_prompt_raw(base_prompt: str, negative_prompt: str) -> str:
    base_prompt = (base_prompt or "").strip()
    neg = (negative_prompt or "").strip()
    if not neg:
        return base_prompt
    return f"{base_prompt}\n\nAvoid: {neg}"


def load_dotenv(dotenv_path: Path) -> None:
    """
    Мини-загрузчик .env без внешних зависимостей.
    Формат: KEY="VALUE" или KEY=VALUE
    """
    if not dotenv_path.exists():
        return
    for raw in dotenv_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k = k.strip()
        v = v.strip().strip('"').strip("'")
        if k and v and k not in os.environ:
            os.environ[k] = v


def load_env(repo: Path) -> None:
    for candidate in (repo / ".env", repo / "Tools" / "AI" / ".env", repo / "Tools" / ".env"):
        load_dotenv(candidate)


def png_has_transparency(png: bytes) -> bool:
    """
    Проверяем, что PNG потенциально содержит прозрачность.
    1) Если IHDR color_type 4 или 6 -> есть alpha.
    2) Если color_type 3 (палитра) и есть chunk tRNS -> тоже есть прозрачность.
    """
    if not png.startswith(PNG_SIG):
        return False

    # Идём по чанкам PNG
    # chunk: length(4) + type(4) + data(length) + crc(4)
    pos = 8
    color_type = None
    has_trns = False

    while pos + 8 <= len(png):
        length = struct.unpack(">I", png[pos:pos+4])[0]
        ctype = png[pos+4:pos+8]
        pos += 8
        if pos + length > len(png):
            break
        data = png[pos:pos+length]
        pos += length
        pos += 4  # crc

        if ctype == b"IHDR" and len(data) >= 13:
            # IHDR: width(4), height(4), bit_depth(1), color_type(1), ...
            color_type = data[9]
        elif ctype == b"tRNS":
            has_trns = True

        if ctype == b"IEND":
            break

    if color_type in (4, 6):
        return True
    if color_type == 3 and has_trns:
        return True
    return False


# -----------------------------
# Стиль-предустановки
# -----------------------------

def style_profile_text(style_profile: str) -> str:
    """
    Возвращает текст арт-дирекшена для конкретного стиля.
    """
    style_profile = (style_profile or "").strip().lower()

    if style_profile in ("diary_cookie_icon", "diary_cookie_ui"):
        return (
            "Style: appetizing sugar cookie button icon, thick smooth icing, cute and friendly, "
            "soft 2.5D look, clean edges, minimal details, readable at small size, "
            "tactile 'pressable' feel, gentle highlights, no text."
        )

    if style_profile == "diary_cookie_illustration":
        return (
            "Style: small friendly bakery-sticker illustration, sugar cookie + icing vibe, "
            "soft pastel colors, minimal details, UI-friendly, no text."
        )

    if style_profile.startswith("diary_kidline"):
        return (
            "Style: kidline black sketch, uneven black lines only, no fills, no color, "
            "no shading, no paper texture, minimal details."
        )

    if style_profile.startswith("kidline_card") or style_profile.startswith("newyear_kid"):
        return (
            "Style: naive child line art, uneven black lines, shaky contours, no fills, no color, "
            "no shading, light paper texture background allowed."
        )

    if style_profile.startswith("diary_plush"):
        return (
            "Style: plush felt/fleece texture with stitched details, pastel colors, soft lighting, "
            "friendly and minimal."
        )

    if style_profile.startswith("plush_card"):
        return (
            "Style: plush toy look, soft felt/fleece texture, rounded proportions, "
            "stitched seams, embroidered details, warm pastel palette, soft lighting."
        )

    if style_profile.startswith("diary_neon"):
        return (
            "Style: neon tube icon, thick neon line, soft glow, add a thin neutral outer stroke "
            "so it reads on white background."
        )

    # Нейтральный дефолт (если preset не задан)
    return (
        "Style: modern medical-tech UI illustration, clean, friendly, minimal, crisp edges, no text."
    )


def build_prompt(
    base_prompt: str,
    asset_type: str,
    background: str,
    style_profile: str,
    negative_prompt: str,
) -> str:
    """
    Собираем финальный промт.
    Важно: генератор картинок не имеет отдельного negative_prompt параметра,
    поэтому мы добавляем запреты в текст.
    """
    asset_type = (asset_type or "").strip().lower()
    background = (background or "auto").strip().lower()

    # Общие требования
    req_common = [
        "No text, no letters, no numbers.",
        "No watermark, no logo, no brand names.",
        "No frame, no background rectangle.",
        "Centered composition, clean silhouette.",
        "Keep the full object inside the frame with padding (10-15%).",
    ]

    # Уточнения по фону
    if background == "transparent":
        req_bg = ["Transparent background (alpha)."]
    else:
        req_bg = ["Clean simple background."]

    # Уточнения по типу ассета и стиля
    style_profile = (style_profile or "").strip().lower()
    allow_shadow = style_profile.startswith("diary_plush") or style_profile.startswith("diary_cookie")
    disallow_shadow = style_profile.startswith("diary_kidline")
    allow_glow = style_profile.startswith("diary_neon")

    req_type: List[str] = []
    if asset_type in ("icon", "badge", "ui", "sprite", "logo"):
        req_type = [
            "Single object only, isolated, no environment scene.",
            "Avoid excessive tiny details; keep it readable as an app icon.",
        ]
        if allow_shadow:
            req_type.append("Soft subtle shadow under the object is allowed.")
        if disallow_shadow:
            req_type.append("No shadow at all.")
        if allow_glow:
            req_type.append("Soft neon glow is allowed, no background plate.")
    else:
        req_type = [
            "UI illustration, simple scene allowed, but keep it clean and minimal.",
        ]

    # Стиль
    style_txt = style_profile_text(style_profile)

    # Запреты
    neg = (negative_prompt or "").strip()
    neg_lines: List[str] = []
    if neg:
        neg_lines.append(f"Avoid: {neg}")

    # Собираем
    parts = [
        base_prompt.strip(),
        "",
        style_txt,
        "",
        "Requirements:",
        *[f"- {x}" for x in (req_common + req_bg + req_type)],
    ]
    if neg_lines:
        parts += ["", *neg_lines]

    return "\n".join(parts).strip()


def infer_style_profile(
    style_profile: str,
    style_preset: str,
    intent: str,
    folder_path: str,
    asset_type: str,
) -> str:
    profile = (style_profile or "").strip()
    if profile:
        return profile
    legacy = (style_preset or "").strip()
    if legacy:
        return legacy
    intent = (intent or "").strip().lower()
    folder_path = (folder_path or "").replace("\\", "/").lower()
    if intent.startswith("diary_") or "/ui/diary/" in folder_path:
        return "diary_cookie_icon" if (asset_type or "").strip().lower() == "icon" else "diary_cookie_illustration"
    return ""


# -----------------------------
# Запрос к Images API
# -----------------------------

def generate_png(
    api_key: str,
    prompt: str,
    model: str,
    size: str,
    quality: str,
    background: Optional[str],
    org_id: Optional[str],
) -> bytes:
    model = normalize_model(model)

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    }
    if org_id:
        headers["OpenAI-Organization"] = org_id

    payload: Dict[str, Any] = {
        "model": model,
        "prompt": prompt,
        "size": size,
        "n": 1,
    }

    quality_mapped = map_quality_for_model(quality, model)

    if model_supports_background(model):
        payload["output_format"] = "png"
        if quality_mapped:
            payload["quality"] = quality_mapped
        if background in ("transparent", "opaque"):
            payload["background"] = background
    else:
        # Для DALL-E
        payload["response_format"] = "b64_json"
        if quality_mapped:
            payload["quality"] = quality_mapped

    r = requests.post(IMAGES_URL, headers=headers, json=payload, timeout=180)
    if not r.ok:
        try:
            err = r.json()
        except Exception:
            err = r.text
        raise RuntimeError(f"OpenAI Images API {r.status_code}: {err}")

    data = r.json()
    b64 = data["data"][0].get("b64_json")
    if b64:
        return base64.b64decode(b64)

    url = data["data"][0].get("url")
    if url:
        r_img = requests.get(url, timeout=180)
        r_img.raise_for_status()
        return r_img.content

    raise RuntimeError("Не найден b64_json/url в ответе.")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate art assets from manifest JSON")
    parser.add_argument("--manifest", required=True, help="Путь к manifest JSON")
    parser.add_argument("--repo_root", default=".", help="Корень репозитория")
    parser.add_argument("--unity_root", dest="repo_root", help="Alias of --repo_root")
    parser.add_argument("--model", default=None, help="Основная модель (например gpt-image-1)")
    parser.add_argument("--fallback-models", default=None, help="Запасные модели через запятую")
    parser.add_argument("--size", default=None, help="Размер по умолчанию, например 1024x1024")
    parser.add_argument("--quality", default=None, help="low|medium|high")
    parser.add_argument("--overwrite", action="store_true", help="Перегенерировать, даже если файл уже существует")
    parser.add_argument("--skip-if-no-key", action="store_true", help="Не падать, если OPENAI_API_KEY не задан")
    args = parser.parse_args()

    repo = Path(args.repo_root).resolve()
    load_env(repo)

    api_key = os.environ.get("OPENAI_API_KEY", "").strip()
    org_id = os.environ.get("OPENAI_ORG_ID", "").strip() or None
    if not api_key:
        if args.skip_if_no_key:
            print("SKIP: OPENAI_API_KEY не задан.")
            return 0
        print("Ошибка: OPENAI_API_KEY не задан.")
        return 2

    manifest_path = (repo / args.manifest).resolve()
    if not manifest_path.exists():
        print(f"Ошибка: не найден manifest: {manifest_path}")
        return 2

    manifest: Dict[str, Any] = json.loads(manifest_path.read_text(encoding="utf-8"))
    assets = manifest.get("assets", [])
    if not isinstance(assets, list):
        print("Ошибка: manifest.assets должен быть массивом.")
        return 2

    model = normalize_model(args.model or os.environ.get("OPENAI_IMAGE_MODEL", "gpt-image-1"))
    fallback_raw = args.fallback_models or os.environ.get("OPENAI_IMAGE_FALLBACK_MODELS", "")
    fallback_models = parse_model_list(fallback_raw)

    # Цепочка моделей (но прозрачные ассеты будут фильтровать её отдельно)
    model_chain_all = [model] + [m for m in fallback_models if m and m != model]

    default_size = enforce_max_size(args.size or os.environ.get("OPENAI_IMAGE_SIZE", "1024x1024"))
    default_quality = "low"

    generated = 0

    for a in assets:
        asset_id = a.get("asset_id")
        if not asset_id:
            print("[SKIP] asset без asset_id")
            continue

        asset_type = a.get("type", "")
        folder_path = a.get("folder_path", "_ai_out")
        file_name = a.get("file_name", f"{asset_id}.png")
        prompt = a.get("prompt", "")
        background = (a.get("background") or "auto").strip().lower()

        style_profile = infer_style_profile(
            style_profile=str(a.get("style_profile", "")),
            style_preset=str(a.get("style_preset", "")),
            intent=str(a.get("intent", "")),
            folder_path=str(folder_path),
            asset_type=str(asset_type),
        )
        negative_prompt = a.get("negative_prompt", "")
        prompt_mode = str(a.get("prompt_mode") or "").strip().lower()

        asset_quality = (a.get("quality") or default_quality)

        if not file_name.lower().endswith(".png"):
            file_name = f"{file_name}.png"

        # Собираем финальный промт
        if prompt_mode == "raw":
            final_prompt = build_prompt_raw(
                base_prompt=str(prompt),
                negative_prompt=str(negative_prompt),
            )
        else:
            final_prompt = build_prompt(
                base_prompt=str(prompt),
                asset_type=str(asset_type),
                background=str(background),
                style_profile=str(style_profile),
                negative_prompt=str(negative_prompt),
            )

        target_dir = (repo / folder_path).resolve()
        target_dir.mkdir(parents=True, exist_ok=True)
        out_path = target_dir / file_name

        if out_path.exists() and not args.overwrite:
            print(f"[SKIP] Уже есть: {out_path}")
            continue

        size_value = size_from_asset(a, default_size)

        # Если нужен прозрачный фон -> используем только gpt-image модели.
        model_chain = list(model_chain_all)
        if background == "transparent":
            model_chain = [m for m in model_chain if model_supports_background(m)]
            if not model_chain:
                print(f"[ERR] {asset_id}: нет моделей, которые гарантируют прозрачность. Используй gpt-image-1.")
                continue

        print(f"[GEN] {asset_id} -> {out_path}")

        success = False
        for active_model in model_chain:
            try:
                png = generate_png(
                    api_key=api_key,
                    prompt=final_prompt,
                    model=active_model,
                    size=size_value,
                    quality=asset_quality,
                    background=background if background in ("transparent", "opaque") else None,
                    org_id=org_id,
                )

                # Строгая проверка прозрачности
                if background == "transparent" and not png_has_transparency(png):
                    raise RuntimeError("PNG не содержит прозрачности (alpha). Модель/промт не выполнили требование.")

                out_path.write_bytes(png)
                generated += 1
                success = True
                break

            except Exception as e:
                print(f"[ERR] {asset_id} ({active_model}): {e}")

        if not success:
            print(f"[FAIL] {asset_id}: не удалось сгенерировать.")
            continue

    print(f"Готово. Сгенерировано: {generated}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
