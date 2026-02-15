#!/usr/bin/env python3
"""
Stream: scheduled per-input network autotune (HTTP/HTTPS/HLS).

Задача:
- Для входов, помеченных опцией URL `#net_tune=1`, подобрать более устойчивый набор параметров.
- Тюнинг выполняется через API: меняем input URL options -> даём стриму поработать -> оцениваем статусы.

Важно:
- Скрипт не трогает SoftCAM/ECM/CW и не включает транскодинг.
- По умолчанию перебираем только профили `bad/max/superbad` и их "жирные" jitter/net_auto значения.
- Тюнинг ограничен по времени (3-5 минут на стрим) и выполняется последовательно (без параллелизма),
  чтобы не плодить сетевые запросы.
"""

from __future__ import annotations

import argparse
import copy
import http.cookiejar
import json
import os
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple


# Предустановленные "жирные" пресеты. Значения подобраны так, чтобы:
# - держать соединение при кратких провалах,
# - не дёргать переподключения слишком часто,
# - иметь достаточный jitter буфер "с запасом".
PRESETS: Dict[str, Dict[str, Any]] = {
    "bad": {
        "net_profile": "bad",
        "ua": "vlc",
        "net_auto": 1,
        "net_auto_max_level": 4,
        "net_auto_burst": 3,
        "net_auto_relax_sec": 180,
        "net_auto_window_sec": 25,
        "net_auto_min_interval_sec": 5,
        "jitter_buffer_ms": 2000,
        "jitter_max_buffer_mb": 16,
    },
    "bad_playout": {
        # Как bad, но дополнительно включаем paced playout (NULL stuffing),
        # чтобы /play не "залипал" на паузах входа.
        "net_profile": "bad",
        "ua": "vlc",
        "net_auto": 1,
        "net_auto_max_level": 4,
        "net_auto_burst": 3,
        "net_auto_relax_sec": 180,
        "net_auto_window_sec": 25,
        "net_auto_min_interval_sec": 5,
        "jitter_buffer_ms": 2000,
        "jitter_max_buffer_mb": 16,
        "playout": 1,
        "playout_mode": "auto",
        "playout_target_kbps": "auto",
        "playout_tick_ms": 10,
        "playout_null_stuffing": 1,
        "playout_target_fill_ms": 2000,
        "playout_max_buffer_mb": 16,
    },
    "max": {
        "net_profile": "max",
        "ua": "vlc",
        "net_auto": 1,
        "net_auto_max_level": 6,
        "net_auto_burst": 1,
        "net_auto_relax_sec": 600,
        "net_auto_window_sec": 60,
        "net_auto_min_interval_sec": 10,
        "jitter_buffer_ms": 3000,
        "jitter_max_buffer_mb": 32,
    },
    "max_playout": {
        "net_profile": "max",
        "ua": "vlc",
        "net_auto": 1,
        "net_auto_max_level": 6,
        "net_auto_burst": 1,
        "net_auto_relax_sec": 600,
        "net_auto_window_sec": 60,
        "net_auto_min_interval_sec": 10,
        "jitter_buffer_ms": 3000,
        "jitter_max_buffer_mb": 32,
        "playout": 1,
        "playout_mode": "auto",
        "playout_target_kbps": "auto",
        "playout_tick_ms": 10,
        "playout_null_stuffing": 1,
        "playout_target_fill_ms": 3000,
        "playout_max_buffer_mb": 32,
    },
    "superbad": {
        "net_profile": "superbad",
        "ua": "vlc",
        "net_auto": 1,
        "net_auto_max_level": 8,
        "net_auto_burst": 1,
        "net_auto_relax_sec": 900,
        "net_auto_window_sec": 120,
        "net_auto_min_interval_sec": 10,
        # Для "супер-bad" даём большой запас буфера, чтобы переживать длинные дыры.
        # Цена: задержка.
        "jitter_buffer_ms": 20000,
        "jitter_max_buffer_mb": 64,
    },
    "superbad_playout": {
        # Для superbad playout обычно и так включается по профилю, но добавим явный кандидат
        # для случаев, когда нужно зафиксировать поведение строго через URL.
        "net_profile": "superbad",
        "ua": "vlc",
        "net_auto": 1,
        "net_auto_max_level": 8,
        "net_auto_burst": 1,
        "net_auto_relax_sec": 900,
        "net_auto_window_sec": 120,
        "net_auto_min_interval_sec": 10,
        "jitter_buffer_ms": 20000,
        "jitter_max_buffer_mb": 64,
        "playout": 1,
        "playout_mode": "auto",
        "playout_target_kbps": "auto",
        "playout_tick_ms": 10,
        "playout_null_stuffing": 1,
        "playout_target_fill_ms": 20000,
        "playout_max_buffer_mb": 64,
    },
}


def _json_dumps(obj: Any) -> str:
    return json.dumps(obj, ensure_ascii=True, sort_keys=True, indent=2)


def _now_ts() -> int:
    return int(time.time())


def normalize_api_base(value: str) -> str:
    base = (value or "").strip().rstrip("/")
    if not base:
        raise ValueError("api base is empty")
    # Поддержим оба варианта: base=... и base=.../api/v1
    if not base.endswith("/api/v1"):
        base = base + "/api/v1"
    return base


class StreamApiError(RuntimeError):
    pass


class StreamClient:
    def __init__(self, api_base: str, username: str, password: str, timeout_sec: int = 30):
        self.api_base = normalize_api_base(api_base)
        self.timeout_sec = int(timeout_sec)
        self.cookiejar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.cookiejar))
        self.session: Optional[str] = None
        self.session_cookie_name: Optional[str] = None
        self._login(username, password)

    def _login(self, username: str, password: str) -> None:
        payload = {"username": username, "password": password}
        self._request_json("POST", "/auth/login", payload)
        token = None
        cookie_name = None
        for c in self.cookiejar:
            if c.name == "stream_session":
                token = c.value
                cookie_name = "stream_session"
                break
        if not token:
            for c in self.cookiejar:
                if c.name == "astra_session":
                    token = c.value
                    cookie_name = "astra_session"
                    break
        if not token:
            raise StreamApiError("login ok but session cookie is missing")
        self.session = token
        self.session_cookie_name = cookie_name

    def _request_json(self, method: str, path: str, body: Optional[Dict[str, Any]] = None) -> Any:
        url = self.api_base + path
        headers = {
            "Accept": "application/json",
        }
        data = None
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        if self.session:
            # Use the cookie name returned by the server (supports older/newer deployments).
            cookie_name = self.session_cookie_name or "stream_session"
            headers["Cookie"] = f"{cookie_name}={self.session}"
            if method in ("POST", "PUT", "DELETE", "PATCH"):
                headers["X-CSRF-Token"] = self.session
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with self.opener.open(req, timeout=self.timeout_sec) as resp:
                raw = resp.read().decode("utf-8", errors="replace")
                if not raw:
                    return {}
                try:
                    return json.loads(raw)
                except Exception:
                    raise StreamApiError(f"invalid json from {path}")
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8", errors="replace") if hasattr(e, "read") else ""
            msg = raw.strip() or str(e)
            raise StreamApiError(f"{method} {path}: HTTP {e.code}: {msg}")
        except urllib.error.URLError as e:
            raise StreamApiError(f"{method} {path}: network error: {e}")

    def list_streams(self) -> List[Dict[str, Any]]:
        payload = self._request_json("GET", "/streams")
        if isinstance(payload, list):
            return payload
        if isinstance(payload, dict) and isinstance(payload.get("streams"), list):
            return payload["streams"]
        raise StreamApiError("unexpected /streams payload")

    def get_stream(self, stream_id: str) -> Dict[str, Any]:
        return self._request_json("GET", f"/streams/{stream_id}")

    def put_stream(self, stream_id: str, enabled: Optional[bool], config: Dict[str, Any]) -> Dict[str, Any]:
        body: Dict[str, Any] = {"id": stream_id, "config": config}
        if enabled is not None:
            body["enabled"] = bool(enabled)
        return self._request_json("PUT", f"/streams/{stream_id}", body)

    def get_status(self, stream_id: str) -> Dict[str, Any]:
        return self._request_json("GET", f"/stream-status/{stream_id}")


def parse_url_options(url: str) -> Tuple[str, Dict[str, str], List[str]]:
    """
    Возвращает:
    - base_url (без #...),
    - opts dict (последнее значение ключа),
    - order (порядок ключей как в исходном URL).
    """
    if "#" not in url:
        return url, {}, []
    base, frag = url.split("#", 1)
    frag = frag.strip()
    if not frag:
        return base, {}, []
    opts: Dict[str, str] = {}
    order: List[str] = []
    for part in frag.split("&"):
        part = part.strip()
        if not part:
            continue
        if "=" in part:
            k, v = part.split("=", 1)
        else:
            k, v = part, "1"
        k = k.strip()
        v = v.strip()
        if not k:
            continue
        if k not in opts:
            order.append(k)
        opts[k] = v
    return base, opts, order


def build_url_with_options(base: str, opts: Dict[str, Any], order: List[str]) -> str:
    # Сохраним порядок исходных ключей, а новые добавим в конец (по алфавиту для повторяемости).
    parts: List[str] = []
    used = set()
    for k in order:
        if k in opts:
            v = opts[k]
            used.add(k)
            if v is True:
                parts.append(k)
            else:
                parts.append(f"{k}={v}")
    for k in sorted(opts.keys()):
        if k in used:
            continue
        v = opts[k]
        if v is True:
            parts.append(k)
        else:
            parts.append(f"{k}={v}")
    if not parts:
        return base
    return base + "#" + "&".join(parts)


def as_bool(value: Any) -> bool:
    if value is True:
        return True
    if value is False or value is None:
        return False
    s = str(value).strip().lower()
    return s in ("1", "true", "yes", "on")


def pick_stream_enabled(stream: Dict[str, Any]) -> Optional[bool]:
    if isinstance(stream.get("enabled"), bool):
        return stream["enabled"]
    if isinstance(stream.get("enable"), bool):
        return stream["enable"]
    return None


def pick_stream_config(stream: Dict[str, Any]) -> Dict[str, Any]:
    cfg = stream.get("config")
    if isinstance(cfg, dict):
        return cfg
    # legacy: тело могло быть самим config
    if isinstance(stream, dict):
        return stream
    return {}


def normalize_input_list(cfg: Dict[str, Any]) -> List[Any]:
    inputs = cfg.get("input")
    if isinstance(inputs, list):
        return inputs
    if inputs is None:
        return []
    # Иногда input может быть строкой
    if isinstance(inputs, str):
        return [inputs]
    return []


@dataclass
class InputMetrics:
    ok: bool
    health: str
    reason: str
    on_air: bool
    reconnects: int
    fail_count: int
    backoff_ms: int
    last_recv_ts: int
    auto_level: int
    jitter_underruns: int
    jitter_drops: int
    playout_enabled: bool
    playout_null_packets: int
    playout_underrun_ms: int
    playout_drops: int


def extract_metrics_for_input(status: Dict[str, Any], input_index: int) -> Optional[InputMetrics]:
    inputs = status.get("inputs")
    if not isinstance(inputs, list):
        return None
    entry = None
    for it in inputs:
        if isinstance(it, dict) and int(it.get("index", -1)) == int(input_index):
            entry = it
            break
    if not isinstance(entry, dict):
        return None
    health = str(entry.get("health_state") or "").lower() or "unknown"
    reason = str(entry.get("health_reason") or entry.get("last_error") or "")
    on_air = bool(entry.get("on_air") is True)
    net = entry.get("net") if isinstance(entry.get("net"), dict) else {}
    reconnects = int(net.get("reconnects_total") or 0)
    fail_count = int(net.get("fail_count") or 0)
    backoff_ms = int(net.get("current_backoff_ms") or 0)
    last_recv_ts = int(net.get("last_recv_ts") or 0)
    auto_level = int(net.get("auto_level") or 0)
    jitter = entry.get("jitter") if isinstance(entry.get("jitter"), dict) else {}
    jitter_underruns = int(jitter.get("buffer_underruns_total") or 0)
    jitter_drops = int(jitter.get("buffer_drops_total") or 0)
    playout = entry.get("playout") if isinstance(entry.get("playout"), dict) else {}
    playout_enabled = bool(playout.get("playout_enabled") is True)
    playout_null_packets = int(playout.get("null_packets_total") or 0)
    playout_underrun_ms = int(playout.get("underrun_ms_total") or 0)
    playout_drops = int(playout.get("drops_total") or 0)

    ok = health in ("ok", "online", "running")
    return InputMetrics(
        ok=ok,
        health=health,
        reason=reason,
        on_air=on_air,
        reconnects=reconnects,
        fail_count=fail_count,
        backoff_ms=backoff_ms,
        last_recv_ts=last_recv_ts,
        auto_level=auto_level,
        jitter_underruns=jitter_underruns,
        jitter_drops=jitter_drops,
        playout_enabled=playout_enabled,
        playout_null_packets=playout_null_packets,
        playout_underrun_ms=playout_underrun_ms,
        playout_drops=playout_drops,
    )


def score_window(samples: List[InputMetrics]) -> Tuple[int, Dict[str, Any]]:
    if not samples:
        return 10_000, {"error": "no samples"}
    first = samples[0]
    last = samples[-1]
    delta_reconnects = max(0, last.reconnects - first.reconnects)
    delta_fail = max(0, last.fail_count - first.fail_count)
    delta_underruns = max(0, last.jitter_underruns - first.jitter_underruns)
    delta_drops = max(0, last.jitter_drops - first.jitter_drops)
    delta_playout_null = max(0, last.playout_null_packets - first.playout_null_packets)
    delta_playout_underrun_ms = max(0, last.playout_underrun_ms - first.playout_underrun_ms)
    delta_playout_drops = max(0, last.playout_drops - first.playout_drops)
    offline = sum(1 for s in samples if s.health == "offline")
    degraded = sum(1 for s in samples if s.health == "degraded")
    onair_bad = sum(1 for s in samples if not s.on_air)

    # Чем меньше тем лучше.
    score = 0
    score += delta_reconnects * 50
    score += delta_fail * 10
    score += delta_underruns * 200
    score += delta_drops * 10
    # Если включён playout, минимизируем время underflow (когда выдаём NULL вместо контента).
    # 1 балл за секунду underrun + небольшой штраф за количество NULL/дропов.
    score += int(delta_playout_underrun_ms / 1000) * 10
    score += int(delta_playout_null / 1000) * 2
    score += delta_playout_drops * 10
    score += degraded * 20
    score += offline * 200
    # Для вещания важнее всего непрерывность; on_air провалы считаем сильно.
    score += onair_bad * 50

    summary = {
        "delta_reconnects": delta_reconnects,
        "delta_fail": delta_fail,
        "delta_jitter_underruns": delta_underruns,
        "delta_jitter_drops": delta_drops,
        "delta_playout_null_packets": delta_playout_null,
        "delta_playout_underrun_ms": delta_playout_underrun_ms,
        "delta_playout_drops": delta_playout_drops,
        "degraded_samples": degraded,
        "offline_samples": offline,
        "onair_bad_samples": onair_bad,
        "last_reason": last.reason,
        "last_auto_level": last.auto_level,
        "score": score,
    }
    return score, summary


def calc_jitter_max_mb(jitter_ms: int, assumed_mbps: int, max_auto_mb: int) -> int:
    # Должно совпадать по смыслу с base.lua/web/app.js (safety factor + clamp).
    safety = 4
    bytes_count = (jitter_ms / 1000.0) * (assumed_mbps * 1000 * 1000 / 8.0) * safety
    mb = int((bytes_count + (1024 * 1024 - 1)) // (1024 * 1024))
    if mb < 8:
        mb = 8
    if mb > max_auto_mb:
        mb = max_auto_mb
    return mb


def expand_candidates(base_candidates: List[str], jitter_variants_ms: List[int]) -> List[Tuple[str, Dict[str, Any]]]:
    out: List[Tuple[str, Dict[str, Any]]] = []
    for name in base_candidates:
        preset = PRESETS.get(name)
        if not preset:
            continue
        base_prof = str(preset.get("net_profile") or name).strip().lower()
        assumed_map = {"bad": 16, "max": 20, "superbad": 20}

        # Для bad/max пробуем разные jitter варианты. superbad оставляем как есть (у него уже большой jitter).
        if base_prof in ("bad", "max") and jitter_variants_ms:
            for ms in jitter_variants_ms:
                p = copy.deepcopy(preset)
                p["jitter_buffer_ms"] = int(ms)
                # Расчёт лимита по "профильному" assumed Mbps.
                assumed = assumed_map.get(base_prof, 16)
                p["jitter_max_buffer_mb"] = calc_jitter_max_mb(int(ms), assumed_mbps=assumed, max_auto_mb=64)
                if as_bool(p.get("playout")):
                    p["playout_target_fill_ms"] = int(ms)
                    p["playout_max_buffer_mb"] = int(p["jitter_max_buffer_mb"])
                out.append((f"{name}-j{ms}", p))
        else:
            out.append((name, preset))
    return out


def acquire_lock(lock_file: str) -> Optional[int]:
    # Стараемся не плодить параллельные autotune прогоны (таймеры/cron могут пересекаться).
    try:
        import fcntl  # type: ignore
    except Exception:
        return -1
    fd = os.open(lock_file, os.O_CREAT | os.O_RDWR, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(fd)
        return None
    os.ftruncate(fd, 0)
    os.write(fd, str(os.getpid()).encode("ascii"))
    os.fsync(fd)
    return fd


def tune_one_input(
    client: StreamClient,
    stream_id: str,
    input_index: int,
    original_url: str,
    candidates: List[Tuple[str, Dict[str, Any]]],
    total_budget_sec: int,
    settle_sec: int,
    poll_sec: int,
    dry_run: bool,
) -> Dict[str, Any]:
    base_url, opts, order = parse_url_options(original_url)
    if not as_bool(opts.get("net_tune")):
        return {"skipped": True, "reason": "net_tune not enabled"}

    # Делим бюджет на кандидаты (с небольшим запасом на settle).
    if total_budget_sec < 60:
        total_budget_sec = 60
    per_candidate = max(30, int((total_budget_sec - (settle_sec * len(candidates))) / max(1, len(candidates))))

    results = []
    best = None

    for prof, preset in candidates:
        new_opts = copy.deepcopy(opts)
        # Важно: не выключаем net_tune.
        new_opts["net_tune"] = "1"
        for k, v in preset.items():
            # Используем строковые значения для предсказуемости в URL.
            if isinstance(v, bool):
                new_opts[k] = "1" if v else "0"
            else:
                new_opts[k] = str(v)
        new_url = build_url_with_options(base_url, new_opts, order)

        # Применяем candidate
        applied = {"profile": prof, "url": new_url}
        if not dry_run:
            stream = client.get_stream(stream_id)
            enabled = pick_stream_enabled(stream)
            cfg = pick_stream_config(stream)
            cfg = copy.deepcopy(cfg)
            inputs = normalize_input_list(cfg)
            if input_index < 0 or input_index >= len(inputs):
                raise StreamApiError(f"stream {stream_id}: input index {input_index} out of range")
            # Поддержим и string и table input entries.
            entry = inputs[input_index]
            if isinstance(entry, str):
                inputs[input_index] = new_url
            elif isinstance(entry, dict):
                if "url" in entry and isinstance(entry["url"], str):
                    entry["url"] = new_url
                else:
                    # legacy: если table хранит разбор parse_url, то сохраним исходный URL строкой.
                    entry["url"] = new_url
            else:
                inputs[input_index] = new_url
            cfg["input"] = inputs
            client.put_stream(stream_id, enabled, cfg)

        # settle
        time.sleep(max(0, int(settle_sec)))

        # оценка
        samples: List[InputMetrics] = []
        deadline = time.time() + per_candidate
        while time.time() < deadline:
            st = client.get_status(stream_id)
            m = extract_metrics_for_input(st, input_index)
            if m:
                samples.append(m)
            time.sleep(max(1, int(poll_sec)))

        score, summary = score_window(samples)
        applied["score"] = score
        applied["summary"] = summary
        results.append(applied)

        if best is None or score < best["score"]:
            best = applied

    out: Dict[str, Any] = {
        "stream_id": stream_id,
        "input_index": input_index,
        "original_url": original_url,
        "budget_sec": total_budget_sec,
        "per_candidate_sec": per_candidate,
        "candidates": [c[0] for c in candidates],
        "results": results,
        "best": best,
    }

    # Вернём лучший пресет обратно (чтобы не оставлять тестовый кандидат).
    if best and not dry_run:
        stream = client.get_stream(stream_id)
        enabled = pick_stream_enabled(stream)
        cfg = pick_stream_config(stream)
        cfg = copy.deepcopy(cfg)
        inputs = normalize_input_list(cfg)
        entry = inputs[input_index] if input_index < len(inputs) else None
        if isinstance(entry, str):
            inputs[input_index] = best["url"]
        elif isinstance(entry, dict):
            entry["url"] = best["url"]
        else:
            inputs[input_index] = best["url"]
        cfg["input"] = inputs
        client.put_stream(stream_id, enabled, cfg)

    return out


def main(argv: List[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--api", required=True, help="Stream base URL, e.g. http://127.0.0.1:9060")
    ap.add_argument("--username", default="admin")
    ap.add_argument("--password", default="admin")
    ap.add_argument("--stream-id", action="append", help="Tune only this stream id (repeatable)")
    ap.add_argument("--duration-sec", type=int, default=240, help="Total tuning budget per stream (sec), 180..300 recommended")
    ap.add_argument("--settle-sec", type=int, default=15, help="Seconds to wait after applying a candidate")
    ap.add_argument("--poll-sec", type=int, default=10, help="Status polling interval (sec)")
    ap.add_argument("--candidates", default="bad,max,superbad", help="Comma-separated profiles to try")
    ap.add_argument("--jitter-variants-ms", default="2000,6000,12000", help="Comma-separated jitter_buffer_ms values for bad/max candidates")
    ap.add_argument("--lock-file", default="/tmp/stream_net_autotune.lock", help="Lock file to avoid overlapping runs")
    ap.add_argument("--dry-run", action="store_true", help="Don't apply changes, only print what would be done")
    args = ap.parse_args(argv)

    lock_fd = acquire_lock(str(args.lock_file))
    if lock_fd is None:
        print(_json_dumps({"ok": True, "skipped": True, "reason": "locked"}))
        return 0

    base_candidates = [c.strip().lower() for c in str(args.candidates).split(",") if c.strip()]
    for c in base_candidates:
        if c not in PRESETS:
            raise SystemExit(f"unknown candidate profile: {c}")

    jitter_variants = []
    for part in str(args.jitter_variants_ms).split(","):
        part = part.strip()
        if not part:
            continue
        try:
            ms = int(part)
        except Exception:
            continue
        if ms > 0:
            jitter_variants.append(ms)
    jitter_variants = sorted(set(jitter_variants))
    candidates = expand_candidates(base_candidates, jitter_variants)

    client = StreamClient(args.api, args.username, args.password)

    if args.stream_id:
        stream_ids = [str(x).strip() for x in args.stream_id if str(x).strip()]
    else:
        streams = client.list_streams()
        stream_ids = [str(s.get("id")) for s in streams if isinstance(s, dict) and s.get("id")]

    all_results = []

    for sid in stream_ids:
        stream = client.get_stream(sid)
        cfg = pick_stream_config(stream)
        inputs = normalize_input_list(cfg)
        for idx, entry in enumerate(inputs):
            url = None
            if isinstance(entry, str):
                url = entry
            elif isinstance(entry, dict):
                u = entry.get("url")
                if isinstance(u, str):
                    url = u
            if not url or "#" not in url:
                continue
            _, opts, _ = parse_url_options(url)
            if not as_bool(opts.get("net_tune")):
                continue
            # Тюним только HTTP/HTTPS/HLS входы (по схеме).
            if "://" not in url:
                continue
            scheme = url.split("://", 1)[0].lower()
            if scheme not in ("http", "https", "hls"):
                continue
            res = tune_one_input(
                client=client,
                stream_id=sid,
                input_index=idx,
                original_url=url,
                candidates=candidates,
                total_budget_sec=int(args.duration_sec),
                settle_sec=int(args.settle_sec),
                poll_sec=int(args.poll_sec),
                dry_run=bool(args.dry_run),
            )
            all_results.append(res)
            print(_json_dumps(res))

    if not all_results:
        print(_json_dumps({"ok": True, "tuned": 0}))
    else:
        print(_json_dumps({"ok": True, "tuned": len(all_results), "ts": _now_ts()}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
