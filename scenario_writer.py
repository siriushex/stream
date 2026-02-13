#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
scenario_writer.py

Генерирует промты для картинок и пишет manifest JSON, совместимый с generate_art.py.

Поддержка:
- preset: site_default, diary_cookie_ui, diary_kidline_ui, diary_plush_ui, diary_neon_ui, newyear_kid_cards, blast_dark_premium_v1, blast_light_rocket_v1, blast_dark_plush_splash_v1.
- Все ассеты по умолчанию: transparent background.
- В manifest добавляются: style_profile, negative_prompt, quality, iconKey.
- prompt_override/prompt сохраняются без вызова OpenAI.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any, Dict, List, Optional

import requests

CHAT_URL = "https://api.openai.com/v1/chat/completions"
DEFAULT_PRESET = "diary_cookie_ui"
DEFAULT_MANIFEST_OUT = "Tools/AI/_ai_out/05_diary_ui_art_manifest.json"
DEFAULT_CARD_MANIFEST_OUT = "_ai_out/newyear_cards_manifest.json"
DEFAULT_BLAST_MANIFEST_OUT = "scenarios/blast_dark_premium_v1.json"
DEFAULT_BLAST_LIGHT_MANIFEST_OUT = "scenarios/blast_light_rocket_v1.json"
DEFAULT_BLAST_PLUSH_SPLASH_MANIFEST_OUT = "scenarios/blast_dark_plush_splash_v1.json"

DIARY_PRESETS = {
    "diary_cookie_ui",
    "diary_kidline_ui",
    "diary_plush_ui",
    "diary_neon_ui",
}

CARD_PRESETS = {
    "newyear_kid_cards",
}

BLAST_PRESETS = {
    "blast_dark_premium_v1",
    "blast_light_rocket_v1",
    "blast_dark_plush_splash_v1",
}

BLAST_STYLE_SUFFIX = (
    "Dark premium UI illustration, minimal, no text, no letters, no numbers, no watermark, "
    "vector-like shapes with subtle soft glow, high contrast, lots of negative space, smooth edges, "
    "modern tech aesthetic, centered composition, safe margins."
)

BLAST_LIGHT_STYLE_SUFFIX = (
    "Light premium UI illustration, minimal, no text, no letters, no numbers, no watermark, "
    "vector-like shapes with soft warm glow, high-key palette, lots of negative space, smooth edges, "
    "modern friendly aesthetic, centered composition, safe margins."
)

BLAST_PLUSH_DARK_STYLE_SUFFIX = (
    "Plush mascot style, soft felt texture, stitched seams, rounded puffy shapes, gentle soft light, "
    "cute friendly mood, clean silhouette, premium cozy look, centered composition, safe margins."
)

BLAST_DARK_PREMIUM_V1_ASSETS: List[Dict[str, Any]] = [
    {
        "asset_id": "blast-bg-main",
        "type": "background",
        "intent": "bg_main",
        "quality": "high",
        "size_px": {"w": 1024, "h": 1536},
        "background": "opaque",
        "folder_path": "assets/blast/v2/backgrounds",
        "file_name": "bg_main.png",
        "prompt_override": (
            "Abstract dark gradient background for a VPN/proxy mobile app. "
            "Deep navy to teal smooth gradient, very subtle noise texture, gentle vignette, "
            "soft light bloom in the center, faint diagonal light streaks, minimal, calm, premium. "
            f"{BLAST_STYLE_SUFFIX} 2:3."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
    {
        "asset_id": "blast-bg-proxy-list",
        "type": "background",
        "intent": "bg_proxy_list",
        "quality": "high",
        "size_px": {"w": 1024, "h": 1536},
        "background": "opaque",
        "folder_path": "assets/blast/v2/backgrounds",
        "file_name": "bg_proxy_list.png",
        "prompt_override": (
            "Background for a proxy list screen in a VPN app. "
            "Dark navy gradient with very subtle vertical haze, soft vignette, "
            "faint abstract shapes near edges only, clean center area for readable list content. "
            f"{BLAST_STYLE_SUFFIX} 2:3."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
    {
        "asset_id": "blast-bg-connecting",
        "type": "background",
        "intent": "bg_connecting",
        "quality": "high",
        "size_px": {"w": 1024, "h": 1536},
        "background": "opaque",
        "folder_path": "assets/blast/v2/backgrounds",
        "file_name": "bg_connecting.png",
        "prompt_override": (
            "Connecting state background for a VPN app. "
            "Dark navy background with a thin circular orbit ring around the center, "
            "subtle motion feel, faint rotating arc segments, soft glow, minimal, elegant, not busy. "
            f"{BLAST_STYLE_SUFFIX} 2:3."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
    {
        "asset_id": "blast-bg-connected",
        "type": "background",
        "intent": "bg_connected",
        "quality": "high",
        "size_px": {"w": 1024, "h": 1536},
        "background": "opaque",
        "folder_path": "assets/blast/v2/backgrounds",
        "file_name": "bg_connected.png",
        "prompt_override": (
            "Connected state background for a VPN app. "
            "Dark navy background with a subtle circular energy halo behind the center button, "
            "soft radial glow, faint particles drifting, gentle light rays, calm but alive, premium. "
            f"{BLAST_STYLE_SUFFIX} 2:3."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
    {
        "asset_id": "blast-ill-empty-service",
        "type": "illustration",
        "intent": "ill_empty_service_not_started",
        "quality": "medium",
        "size_px": {"w": 1024, "h": 1536},
        "background": "opaque",
        "folder_path": "assets/blast/v2/illustrations",
        "file_name": "ill_empty_service_not_started.png",
        "prompt_override": (
            "Empty state illustration for 'service not started' in a VPN/proxy app. "
            "A small minimalist server block and a disconnected cable plug, "
            "tiny pause/stop indicator icon, friendly and calm, centered, lots of space. "
            f"{BLAST_STYLE_SUFFIX} 2:3."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
    {
        "asset_id": "blast-ill-login-telegram",
        "type": "illustration",
        "intent": "ill_login_telegram",
        "quality": "medium",
        "size_px": {"w": 1024, "h": 1536},
        "background": "opaque",
        "folder_path": "assets/blast/v2/illustrations",
        "file_name": "ill_login_telegram.png",
        "prompt_override": (
            "Login screen hero illustration for a VPN app with Telegram authentication. "
            "Minimal smartphone outline with a paper-plane inspired shape (generic, not a logo), "
            "plus a secure key/lock symbol, connected by a thin line, friendly, modern, centered, not childish. "
            f"{BLAST_STYLE_SUFFIX} 2:3."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
    {
        "asset_id": "blast-ic-proxy",
        "type": "icon",
        "intent": "ic_proxy",
        "quality": "low",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "assets/blast/v2/icons",
        "file_name": "ic_proxy.png",
        "prompt_override": (
            "Minimal vector icon for 'Proxy'. A small network node diagram: "
            "three dots connected to a central dot, clean lines, rounded corners, high contrast, "
            "suitable for dark UI, no text, 1:1, transparent background."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
    {
        "asset_id": "blast-ic-connect",
        "type": "icon",
        "intent": "ic_connect",
        "quality": "low",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "assets/blast/v2/icons",
        "file_name": "ic_connect.png",
        "prompt_override": (
            "Minimal vector icon for 'Connect'. A circular ring with a power symbol inside, "
            "clean geometry, flat, high contrast, 1:1, transparent background, no text."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
    {
        "asset_id": "blast-ic-sync",
        "type": "icon",
        "intent": "ic_sync",
        "quality": "low",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "assets/blast/v2/icons",
        "file_name": "ic_sync.png",
        "prompt_override": (
            "Minimal vector icon for 'Sync'. Two curved arrows forming a circle, clean lines, "
            "rounded ends, modern UI style, 1:1, transparent background, no text."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
    {
        "asset_id": "blast-ic-import",
        "type": "icon",
        "intent": "ic_import",
        "quality": "low",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "assets/blast/v2/icons",
        "file_name": "ic_import.png",
        "prompt_override": (
            "Minimal vector icon for 'Import config'. A tray with a downward arrow, clean geometry, "
            "rounded corners, 1:1, transparent background, no text."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
]

BLAST_LIGHT_ROCKET_V1_ASSETS: List[Dict[str, Any]] = [
    {
        "asset_id": "blast-light-bg-main",
        "type": "background",
        "intent": "bg_main",
        "quality": "high",
        "size_px": {"w": 1024, "h": 1536},
        "background": "opaque",
        "folder_path": "assets/blast/v3/backgrounds",
        "file_name": "bg_main.png",
        "prompt_override": (
            "Abstract light gradient background for a VPN/proxy mobile app. "
            "Warm off-white to soft peach smooth gradient, subtle paper texture, gentle vignette, "
            "soft center glow, faint diagonal light streaks, minimal, calm, premium. "
            f"{BLAST_LIGHT_STYLE_SUFFIX} 2:3."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
    {
        "asset_id": "blast-light-bg-proxy-list",
        "type": "background",
        "intent": "bg_proxy_list",
        "quality": "high",
        "size_px": {"w": 1024, "h": 1536},
        "background": "opaque",
        "folder_path": "assets/blast/v3/backgrounds",
        "file_name": "bg_proxy_list.png",
        "prompt_override": (
            "Background for a proxy list screen in a VPN app. "
            "Soft warm off-white gradient with very subtle vertical haze, "
            "faint abstract shapes near edges only, clean center area for readable list content. "
            f"{BLAST_LIGHT_STYLE_SUFFIX} 2:3."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
    {
        "asset_id": "blast-light-bg-connecting",
        "type": "background",
        "intent": "bg_connecting",
        "quality": "high",
        "size_px": {"w": 1024, "h": 1536},
        "background": "opaque",
        "folder_path": "assets/blast/v3/backgrounds",
        "file_name": "bg_connecting.png",
        "prompt_override": (
            "Connecting state background for a VPN app. "
            "Light warm background with a thin circular orbit ring around the center, "
            "subtle motion feel, faint rotating arc segments, soft orange glow, minimal, elegant, not busy. "
            f"{BLAST_LIGHT_STYLE_SUFFIX} 2:3."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
    {
        "asset_id": "blast-light-bg-connected",
        "type": "background",
        "intent": "bg_connected",
        "quality": "high",
        "size_px": {"w": 1024, "h": 1536},
        "background": "opaque",
        "folder_path": "assets/blast/v3/backgrounds",
        "file_name": "bg_connected.png",
        "prompt_override": (
            "Connected state background for a VPN app. "
            "Light warm background with a subtle circular energy halo behind the center button, "
            "soft radial glow, faint particles drifting, gentle light rays, calm but alive, premium. "
            f"{BLAST_LIGHT_STYLE_SUFFIX} 2:3."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
    {
        "asset_id": "blast-light-ill-empty-service",
        "type": "illustration",
        "intent": "ill_empty_service_not_started",
        "quality": "medium",
        "size_px": {"w": 1024, "h": 1536},
        "background": "opaque",
        "folder_path": "assets/blast/v3/illustrations",
        "file_name": "ill_empty_service_not_started.png",
        "prompt_override": (
            "Empty state illustration for 'service not started' in a VPN/proxy app. "
            "Minimal orange rocket sitting idle with a disconnected cable plug, "
            "tiny pause/stop indicator icon, friendly and calm, centered, lots of space. "
            f"{BLAST_LIGHT_STYLE_SUFFIX} 2:3."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
    {
        "asset_id": "blast-light-ill-login-telegram",
        "type": "illustration",
        "intent": "ill_login_telegram",
        "quality": "medium",
        "size_px": {"w": 1024, "h": 1536},
        "background": "opaque",
        "folder_path": "assets/blast/v3/illustrations",
        "file_name": "ill_login_telegram.png",
        "prompt_override": (
            "Login screen hero illustration for a VPN app with Telegram authentication. "
            "Minimal smartphone outline, a small orange rocket badge (generic, not a logo), "
            "plus a paper-plane inspired shape (generic), connected by a thin line, friendly, modern, centered, not childish. "
            f"{BLAST_LIGHT_STYLE_SUFFIX} 2:3."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
    {
        "asset_id": "blast-light-ic-proxy",
        "type": "icon",
        "intent": "ic_proxy",
        "quality": "low",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "assets/blast/v3/icons",
        "file_name": "ic_proxy.png",
        "prompt_override": (
            "Minimal vector icon for 'Proxy'. A small network node diagram: "
            "three dots connected to a central dot, clean lines, rounded corners, "
            "dark charcoal with a warm orange accent, suitable for light UI, 1:1, transparent background, no text."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
    {
        "asset_id": "blast-light-ic-connect",
        "type": "icon",
        "intent": "ic_connect",
        "quality": "low",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "assets/blast/v3/icons",
        "file_name": "ic_connect.png",
        "prompt_override": (
            "Minimal vector icon for 'Connect'. A circular ring with a power symbol inside, "
            "clean geometry, flat, dark charcoal with warm orange accent, 1:1, transparent background, no text."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
    {
        "asset_id": "blast-light-ic-sync",
        "type": "icon",
        "intent": "ic_sync",
        "quality": "low",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "assets/blast/v3/icons",
        "file_name": "ic_sync.png",
        "prompt_override": (
            "Minimal vector icon for 'Sync'. Two curved arrows forming a circle, clean lines, "
            "rounded ends, modern UI style, dark charcoal with warm orange accent, 1:1, transparent background, no text."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
    {
        "asset_id": "blast-light-ic-import",
        "type": "icon",
        "intent": "ic_import",
        "quality": "low",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "assets/blast/v3/icons",
        "file_name": "ic_import.png",
        "prompt_override": (
            "Minimal vector icon for 'Import config'. A tray with a downward arrow, clean geometry, "
            "rounded corners, dark charcoal with warm orange accent, 1:1, transparent background, no text."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
]

BLAST_DARK_PLUSH_SPLASH_V1_ASSETS: List[Dict[str, Any]] = [
    {
        "asset_id": "blast-splash-bg-dark",
        "type": "background",
        "intent": "splash_bg",
        "quality": "high",
        "size_px": {"w": 1024, "h": 1536},
        "background": "opaque",
        "folder_path": "assets/blast/v4/splash",
        "file_name": "splash_bg.png",
        "prompt_override": (
            "Dark splash background for a VPN app. Deep navy to charcoal gradient, "
            "soft radial glow behind the center, subtle fabric-like noise, gentle vignette, "
            "faint floating dust particles, minimal and premium. "
            f"{BLAST_PLUSH_DARK_STYLE_SUFFIX} 2:3."
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
    {
        "asset_id": "blast-splash-plush-shield",
        "type": "illustration",
        "intent": "splash_mascot",
        "quality": "high",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "assets/blast/v4/splash",
        "file_name": "splash_plush_shield.png",
        "prompt_override": (
            "Cute plush lightning shield mascot. Soft felt texture with visible stitched seams, "
            "rounded puffy shapes, friendly smile, subtle blush, "
            "cyan and violet accents with a gentle glow, centered, 1:1, "
            "isolated on transparent background, no text. "
            f"{BLAST_PLUSH_DARK_STYLE_SUFFIX}"
        ),
        "negative_prompt": "text, letters, numbers, watermark, logo, frame, busy details",
        "prompt_mode": "raw",
    },
]

DIARY_HEADER = (
    "UI asset for a web diary app. Transparent background (PNG with alpha), no background, no scene. "
    "Single centered subject, 10–15% padding, crisp edges, readable at 24–32px. "
    "No text, no letters, no numbers, no watermark, no logo, no frame."
)

DIARY_NEGATIVE_DEFAULTS = {
    "diary_kidline_ui": (
        "color, fills, shading, gradients, photorealism, 3d render, paper background, "
        "texture background, text, watermark, logo, frame, busy details"
    ),
    "diary_plush_ui": (
        "text, watermark, logo, photorealistic photo, plastic toy look, hard glossy 3d, "
        "busy background, too many tiny details, gore"
    ),
    "diary_neon_ui": (
        "text, watermark, logo, photorealism, complex background, too many details, thin hairlines, low contrast"
    ),
    "diary_cookie_ui": (
        "text, letters, numbers, watermark, logo, frame, background rectangle, messy details, blurry"
    ),
}

CARD_NEGATIVE_DEFAULTS = {
    "newyear_kid_cards": (
        "color, fills, shading, gradients, photorealism, 3d render, crayon, colored pencil, "
        "watercolor, messy background, extra text, misspelled text, watermark, logo"
    ),
}

CARD_STYLE_NEGATIVE_DEFAULTS = {
    "kidline_card": (
        "color, fills, shading, gradients, photorealism, 3d render, crayon, colored pencil, "
        "watercolor, messy background, extra text, misspelled text, watermark, logo"
    ),
    "plush_card": (
        "photorealistic photo, hard plastic toy, metal, glass, glossy 3d render, harsh shadows, "
        "busy background, clutter, horror, gore, extra text, misspelled text, watermark, logo"
    ),
}

CARD_HEADER = (
    "Printable New Year gift certificate card for kids. Portrait A6 size (quarter of A4). "
    "Hand-drawn border, generous margins, all text inside the border."
)


# -----------------------------
# Ассеты для дневника
# -----------------------------

DEFAULT_DIARY_ASSETS: List[Dict[str, Any]] = [
    # Верхняя навигация (пример)
    {
        "asset_id": "diary-nav-recent",
        "type": "icon",
        "intent": "nav",
        "style_preset": "diary_cookie_icon",
        "quality": "medium",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "apps/frontend/public/ui/diary/icons",
        "file_name": "nav-recent.png",
        "notes": "Icon for 'Последние события': clock + list vibe. Cookie icing button icon. No text.",
    },
    {
        "asset_id": "diary-nav-12w",
        "type": "icon",
        "intent": "nav",
        "style_preset": "diary_cookie_icon",
        "quality": "medium",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "apps/frontend/public/ui/diary/icons",
        "file_name": "nav-12w.png",
        "notes": "Icon for '12 недель': calendar with 12 dots. Cookie icing button icon. No text.",
    },
    {
        "asset_id": "diary-nav-health",
        "type": "icon",
        "intent": "nav",
        "style_preset": "diary_cookie_icon",
        "quality": "medium",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "apps/frontend/public/ui/diary/icons",
        "file_name": "nav-health.png",
        "notes": "Icon for 'Здоровье': heart pulse. Cookie icing button icon. No text.",
    },
    {
        "asset_id": "diary-nav-control",
        "type": "icon",
        "intent": "nav",
        "style_preset": "diary_cookie_icon",
        "quality": "medium",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "apps/frontend/public/ui/diary/icons",
        "file_name": "nav-control.png",
        "notes": "Icon for 'Контроль': sliders. Cookie icing button icon. No text.",
    },

    # Под-вкладки "Контроль"
    {
        "asset_id": "diary-tab-input",
        "type": "icon",
        "intent": "control_tab",
        "style_preset": "diary_cookie_icon",
        "quality": "medium",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "apps/frontend/public/ui/diary/icons",
        "file_name": "tab-input.png",
        "notes": "Icon for 'Ввод': plus in circle. Cookie icing. No text.",
    },
    {
        "asset_id": "diary-tab-history",
        "type": "icon",
        "intent": "control_tab",
        "style_preset": "diary_cookie_icon",
        "quality": "medium",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "apps/frontend/public/ui/diary/icons",
        "file_name": "tab-history.png",
        "notes": "Icon for 'История': calendar + clock. Cookie icing. No text.",
    },
    {
        "asset_id": "diary-tab-stats",
        "type": "icon",
        "intent": "control_tab",
        "style_preset": "diary_cookie_icon",
        "quality": "medium",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "apps/frontend/public/ui/diary/icons",
        "file_name": "tab-stats.png",
        "notes": "Icon for 'Статистика': line chart. Cookie icing. No text.",
    },
    {
        "asset_id": "diary-tab-profile",
        "type": "icon",
        "intent": "control_tab",
        "style_preset": "diary_cookie_icon",
        "quality": "medium",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "apps/frontend/public/ui/diary/icons",
        "file_name": "tab-profile.png",
        "notes": "Icon for 'Профиль': user + sliders badge. Cookie icing. No text.",
    },
    {
        "asset_id": "diary-tab-settings",
        "type": "icon",
        "intent": "control_tab",
        "style_preset": "diary_cookie_icon",
        "quality": "medium",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "apps/frontend/public/ui/diary/icons",
        "file_name": "tab-settings.png",
        "notes": "Icon for 'Настройки': gear. Cookie icing. No text.",
    },
    {
        "asset_id": "diary-tab-help",
        "type": "icon",
        "intent": "control_tab",
        "style_preset": "diary_cookie_icon",
        "quality": "medium",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "apps/frontend/public/ui/diary/icons",
        "file_name": "tab-help.png",
        "notes": "Icon for 'Помощь': help circle. Cookie icing. No text.",
    },

    # Типы записей
    {
        "asset_id": "diary-entry-bg",
        "type": "icon",
        "intent": "entry_type",
        "style_preset": "diary_cookie_icon",
        "quality": "high",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "apps/frontend/public/ui/diary/icons",
        "file_name": "entry-bg.png",
        "notes": "Entry type 'Сахар': droplet with tiny highlight. Cookie icing. No text.",
    },
    {
        "asset_id": "diary-entry-carbs",
        "type": "icon",
        "intent": "entry_type",
        "style_preset": "diary_cookie_icon",
        "quality": "high",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "apps/frontend/public/ui/diary/icons",
        "file_name": "entry-carbs.png",
        "notes": "Entry type 'Углеводы': plate + small bread. Cookie icing. No text.",
    },
    {
        "asset_id": "diary-entry-bolus",
        "type": "icon",
        "intent": "entry_type",
        "style_preset": "diary_cookie_icon",
        "quality": "high",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "apps/frontend/public/ui/diary/icons",
        "file_name": "entry-bolus.png",
        "notes": "Entry type 'Короткий': insulin pen + lightning badge. Cookie icing. No text.",
    },
    {
        "asset_id": "diary-entry-basal",
        "type": "icon",
        "intent": "entry_type",
        "style_preset": "diary_cookie_icon",
        "quality": "high",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "apps/frontend/public/ui/diary/icons",
        "file_name": "entry-basal.png",
        "notes": "Entry type 'Продлённый': insulin pen + moon badge. Cookie icing. No text.",
    },
    {
        "asset_id": "diary-entry-exercise",
        "type": "icon",
        "intent": "entry_type",
        "style_preset": "diary_cookie_icon",
        "quality": "high",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "apps/frontend/public/ui/diary/icons",
        "file_name": "entry-exercise.png",
        "notes": "Entry type 'Нагрузка': running shoe + motion line. Cookie icing. No text.",
    },
    {
        "asset_id": "diary-entry-note",
        "type": "icon",
        "intent": "entry_type",
        "style_preset": "diary_cookie_icon",
        "quality": "high",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "apps/frontend/public/ui/diary/icons",
        "file_name": "entry-note.png",
        "notes": "Entry type 'Заметка': sticky note with folded corner. Cookie icing. No text.",
    },

    # Иллюстрации пустых состояний (прозрачные)
    {
        "asset_id": "diary-empty-today",
        "type": "illustration",
        "intent": "empty_state",
        "style_preset": "diary_cookie_illustration",
        "quality": "medium",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "apps/frontend/public/ui/diary/illustrations",
        "file_name": "empty-today.png",
        "notes": "Empty state: notebook + small droplet cookie icon + small plate cookie icon. Calm, friendly, no text.",
    },
    {
        "asset_id": "diary-empty-history",
        "type": "illustration",
        "intent": "empty_state",
        "style_preset": "diary_cookie_illustration",
        "quality": "medium",
        "size_px": {"w": 1024, "h": 1024},
        "background": "transparent",
        "folder_path": "apps/frontend/public/ui/diary/illustrations",
        "file_name": "empty-history.png",
        "notes": "Empty state: calendar page + tiny sparkles. Calm, friendly, no text.",
    },
]


def load_dotenv(dotenv_path: Path) -> None:
    if not dotenv_path.exists():
        return
    for raw in dotenv_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and value and key not in os.environ:
            os.environ[key] = value


def load_env(repo: Path) -> None:
    for candidate in (repo / ".env", repo / "Tools" / ".env", repo / "Tools" / "AI" / ".env"):
        load_dotenv(candidate)


def make_prompt_request(
    model: str,
    api_key: str,
    brief: str,
    language: str,
    asset: Dict[str, Any],
    preset: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Просим модель написать prompt + negative_prompt в JSON.
    """
    system = (
        "You are an art director writing image generation prompts for UI icons and UI illustrations. "
        "Return JSON only with keys: prompt, negative_prompt."
    )

    # Главное: стиль и требования к прозрачности
    requirements = [
        "No text, no letters, no numbers.",
        "No watermark, no logo.",
        "Transparent background (alpha).",
        "Centered object with padding, no background plate, no frame.",
        "Keep it simple and readable as an app icon.",
        "Avoid scary or medical-realistic gore. Friendly only.",
    ]
    if (preset or "").strip().lower() == "diary_cookie_ui":
        requirements += [
            "Cookie icing UI style: thick smooth icing, soft highlights, tactile pressable look.",
            "Readable at small size, minimal details.",
        ]

    user = {
        "brief": brief,
        "language": language,
        "asset": {
            "asset_id": asset.get("asset_id"),
            "type": asset.get("type"),
            "intent": asset.get("intent"),
            "style_preset": asset.get("style_preset"),
            "notes": asset.get("notes"),
        },
        "requirements": requirements,
        "output_format": {"prompt": "...", "negative_prompt": "..."},
    }

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": json.dumps(user, ensure_ascii=False)},
        ],
        "response_format": {"type": "json_object"},
        "temperature": 0.2,
    }

    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    r = requests.post(CHAT_URL, headers=headers, json=payload, timeout=120)
    if not r.ok:
        raise RuntimeError(f"OpenAI error {r.status_code}: {r.text}")

    data = r.json()
    content = data["choices"][0]["message"]["content"]
    return json.loads(content)


def fallback_prompt(asset: Dict[str, Any]) -> Dict[str, str]:
    """
    Если offline — делаем предсказуемый промт руками.
    """
    notes = asset.get("notes") or asset.get("asset_id") or "UI icon"
    style_profile = (asset.get("style_profile") or asset.get("style_preset") or "").strip().lower()

    if style_profile in ("diary_cookie_icon", "diary_cookie_ui"):
        prompt = (
            f"Create a sugar cookie button icon with thick smooth icing. {notes}. "
            "Cute, friendly, minimal details, readable at small size. "
            "Transparent background. No text."
        )
    else:
        prompt = (
            f"Create a small friendly UI illustration. {notes}. "
            "Transparent background. No text."
        )

    negative = "text, letters, numbers, watermark, logo, frame, background rectangle, messy details, blurry"
    return {"prompt": prompt, "negative_prompt": negative}


def is_diary_preset(preset: Optional[str]) -> bool:
    if not preset:
        return False
    return preset.startswith("diary_")


def resolve_style_profile(asset: Dict[str, Any], preset: Optional[str]) -> str:
    style_profile = str(asset.get("style_profile") or "").strip()
    if style_profile:
        return style_profile
    legacy = str(asset.get("style_preset") or "").strip()
    if legacy:
        return legacy
    if (preset or "").strip().lower() in DIARY_PRESETS:
        return (preset or "").strip().lower()
    if (preset or "").strip().lower() in CARD_PRESETS:
        return "kidline_card"
    return ""


def build_diary_prompt(subject: str, preset: str) -> str:
    preset = (preset or "").strip().lower()
    if preset == "diary_kidline_ui":
        style = (
            "Style: kidline black sketch only. Uneven black lines, no fills, no color, "
            "no shading, no paper texture. Single subject only."
        )
    elif preset == "diary_plush_ui":
        style = (
            "Style: plush felt/fleece texture with stitched details, pastel colors, soft lighting. "
            "Soft subtle shadow under the object is allowed."
        )
    elif preset == "diary_neon_ui":
        style = (
            "Style: neon tube icon, thick glowing line, soft glow. "
            "Add a thin neutral outer stroke so it reads on white background."
        )
    else:
        style = (
            "Style: sugar cookie icing UI, thick smooth icing, cute and friendly, soft highlights, "
            "pressable button look."
        )

    return f"{DIARY_HEADER}\n\nSubject: {subject}.\n{style}"


def is_card_preset(preset: Optional[str]) -> bool:
    if not preset:
        return False
    return (preset or "").strip().lower() in CARD_PRESETS


def format_card_text(card: Dict[str, Any]) -> str:
    number = str(card.get("number") or "").strip()
    title = str(card.get("title") or "").strip()
    body_lines = card.get("body_lines") or []
    condition_lines = card.get("condition_lines") or []
    footer = str(card.get("footer") or "").strip()

    lines: List[str] = []
    if number:
        lines.append(f"СЕРТИФИКАТ № {number}")
    if title:
        lines.append(f"★ {title} ★")
    if body_lines:
        lines.append("")
        lines.extend([str(x).rstrip() for x in body_lines])
    if condition_lines:
        lines.append("")
        lines.extend([str(x).rstrip() for x in condition_lines])
    if footer:
        lines.append("")
        lines.append(footer)

    return "\n".join(lines).strip()


def build_card_prompt(asset: Dict[str, Any]) -> str:
    card = asset.get("card") if isinstance(asset.get("card"), dict) else asset
    doodle = str(card.get("doodle") or "tiny snowflake or star").strip()
    text_block = format_card_text(card)
    style_profile = str(card.get("style_profile") or asset.get("style_profile") or "").strip().lower()

    if style_profile == "plush_card":
        style = (
            "Style: adorable plush toy look with soft felt/fleece texture, rounded proportions, "
            "simplified smooth shapes, delicate stitched seams, embroidered eyes/mouth details, "
            "warm pastel or neutral palette, soft diffused lighting, cozy and huggable."
        )
        background_line = "Background: clean light fabric or matte card stock, subtle texture, not busy."
        doodle_line = f"Add one small plush-themed icon related to the card: {doodle}."
        border_line = "Border: simple stitched line or dashed seam, matching plush aesthetic."
        text_line = "Text in dark ink, clean and readable."
    else:
        style = (
            "Style: naive child line drawing with rough uneven black lines and exaggerated, clumsy proportions. "
            "Draw in a loose, messy manner with shaky contours, uncertain strokes, and simple shapes. "
            "Line art only, no fills, no color, no shading, no crayon texture."
        )
        background_line = "Background: simple or lightly textured paper."
        doodle_line = f"Add one small, simple doodle related to the card: {doodle}."
        border_line = "Use only black line art for border and doodle."
        text_line = "Text in black ink, clean and readable."

    return (
        f"{CARD_HEADER}\n"
        f"{style}\n"
        f"{background_line}\n"
        f"{doodle_line}\n"
        f"{border_line}\n"
        f"{text_line}\n"
        "Text (Cyrillic, exact, keep line breaks):\n"
        f"{text_block}\n"
        "No extra text."
    ).strip()


def card_negative_for_style(style_profile: str, preset: Optional[str]) -> str:
    style_profile = (style_profile or "").strip().lower()
    if style_profile in CARD_STYLE_NEGATIVE_DEFAULTS:
        return CARD_STYLE_NEGATIVE_DEFAULTS[style_profile]
    return CARD_NEGATIVE_DEFAULTS.get(preset or "", "")


def load_assets_from_file(path: Path) -> List[Dict[str, Any]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, dict):
        assets = data.get("assets", [])
        if not isinstance(assets, list):
            raise ValueError("Scenario JSON must contain assets array.")
        return assets
    if isinstance(data, list):
        return data
    raise ValueError("Scenario JSON must be an array or an object with assets.")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate diary art prompts (manifest)")
    parser.add_argument(
        "--preset",
        default=None,
        help=(
            "Preset name (site_default, diary_cookie_ui, diary_kidline_ui, "
            "diary_plush_ui, diary_neon_ui, newyear_kid_cards, blast_dark_premium_v1, "
            "blast_light_rocket_v1, blast_dark_plush_splash_v1)"
        ),
    )
    parser.add_argument("--assets", default=None, help="Path to scenario assets JSON")
    parser.add_argument("--brief", default=None, help="Brief for the art set")
    parser.add_argument("--out", default=None, help="Output manifest path")
    parser.add_argument("--model", default=None, help="Model for prompt writing (chat)")
    parser.add_argument("--offline", action="store_true", help="Do not call API; use fallback prompts")
    parser.add_argument("--language", default="en", help="Prompt language (recommend: en)")
    args = parser.parse_args()

    repo = Path(".").resolve()
    load_env(repo)

    api_key = os.environ.get("OPENAI_API_KEY", "").strip()
    model = (args.model or os.environ.get("OPENAI_PROMPT_MODEL") or "gpt-4o-mini").strip()

    preset = (args.preset or "").strip().lower() or None
    assets_path = args.assets
    if preset == DEFAULT_PRESET and not assets_path:
        assets_path = str(repo / "Tools" / "AI" / "scenarios" / "diary_cookie_ui_assets.json")
    if preset in CARD_PRESETS and not assets_path:
        assets_path = str(repo / "scenarios" / "newyear_cards_assets.json")
    if preset == "blast_light_rocket_v1" and not assets_path:
        assets = BLAST_LIGHT_ROCKET_V1_ASSETS
    elif preset == "blast_dark_plush_splash_v1" and not assets_path:
        assets = BLAST_DARK_PLUSH_SPLASH_V1_ASSETS
    elif preset in BLAST_PRESETS and not assets_path:
        assets = BLAST_DARK_PREMIUM_V1_ASSETS
    elif assets_path:
        assets = load_assets_from_file((repo / assets_path).resolve())
    else:
        assets = DEFAULT_DIARY_ASSETS

    brief = (args.brief or "Diary cookie UI assets").strip()
    if preset in CARD_PRESETS and not args.brief:
        brief = "New Year gift certificate cards for kids"
    if preset == "blast_light_rocket_v1" and not args.brief:
        brief = "Blast light rocket UI assets"
    elif preset == "blast_dark_plush_splash_v1" and not args.brief:
        brief = "Blast dark plush splash assets"
    elif preset in BLAST_PRESETS and not args.brief:
        brief = "Blast dark premium UI assets"

    if args.out:
        out_value = args.out
    elif preset == DEFAULT_PRESET:
        out_value = DEFAULT_MANIFEST_OUT
    elif preset in CARD_PRESETS:
        out_value = DEFAULT_CARD_MANIFEST_OUT
    elif preset == "blast_light_rocket_v1":
        out_value = DEFAULT_BLAST_LIGHT_MANIFEST_OUT
    elif preset == "blast_dark_plush_splash_v1":
        out_value = DEFAULT_BLAST_PLUSH_SPLASH_MANIFEST_OUT
    elif preset in BLAST_PRESETS:
        out_value = DEFAULT_BLAST_MANIFEST_OUT
    else:
        out_value = "Tools/AI/_ai_out/05_diary_art_manifest.json"
    out_path = (repo / out_value).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)

    manifest_assets: List[Dict[str, Any]] = []
    for asset in assets:
        prompt_override = asset.get("prompt_override") or asset.get("prompt")
        negative_override = asset.get("negative_prompt_override") or asset.get("negative_prompt")
        style_profile = resolve_style_profile(asset, preset)

        if prompt_override:
            prompt = str(prompt_override).strip()
            negative_prompt = str(negative_override or "").strip()
            if not negative_prompt:
                style_profile = resolve_style_profile(asset, preset)
                negative_prompt = (
                    card_negative_for_style(style_profile, preset)
                    or DIARY_NEGATIVE_DEFAULTS.get(preset or "", "")
                    or fallback_prompt(asset)["negative_prompt"]
                )
        else:
            if preset and is_card_preset(preset):
                prompt = build_card_prompt(asset)
                style_profile = resolve_style_profile(asset, preset)
                negative_prompt = (
                    str(negative_override or "").strip()
                    or card_negative_for_style(style_profile, preset)
                )
            elif preset and is_diary_preset(preset):
                subject = str(asset.get("subject") or asset.get("iconKey") or asset.get("asset_id") or "Diary UI asset").strip()
                prompt = build_diary_prompt(subject, preset)
                negative_prompt = str(negative_override or "").strip() or DIARY_NEGATIVE_DEFAULTS.get(preset, "")
                if not negative_prompt:
                    negative_prompt = fallback_prompt(asset)["negative_prompt"]
            elif args.offline or not api_key:
                prompt_data = fallback_prompt(asset)
                prompt = str(prompt_data.get("prompt", "")).strip()
                negative_prompt = str(negative_override or prompt_data.get("negative_prompt", "")).strip()
            else:
                prompt_data = make_prompt_request(
                    model=model,
                    api_key=api_key,
                    brief=brief,
                    language=args.language,
                    asset=asset,
                    preset=preset,
                )
                prompt = str(prompt_data.get("prompt", "")).strip() or fallback_prompt(asset)["prompt"]
                negative_prompt = str(negative_override or prompt_data.get("negative_prompt", "")).strip() or fallback_prompt(asset)["negative_prompt"]

        prompt_mode = asset.get("prompt_mode")
        if not prompt_mode and preset in CARD_PRESETS:
            prompt_mode = "raw"

        manifest_assets.append(
            {
                "asset_id": asset["asset_id"],
                "type": asset.get("type", ""),
                "intent": asset.get("intent", ""),
                "iconKey": asset.get("iconKey"),
                "style_profile": style_profile,
                "quality": asset.get("quality", "low"),
                "folder_path": asset.get("folder_path"),
                "file_name": asset.get("file_name"),
                "size_px": asset.get("size_px"),
                "background": asset.get("background") or "transparent",
                "prompt": prompt,
                "negative_prompt": negative_prompt,
                "prompt_mode": prompt_mode,
            }
        )

    out_data = {"assets": manifest_assets}
    out_path.write_text(json.dumps(out_data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Wrote {len(manifest_assets)} prompts to {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
