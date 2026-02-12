#!/usr/bin/env python3
"""
Matrix smoke для Settings -> General:
- применяет безопасные ключи по одному,
- проверяет, что uptime стрима не падает,
- (опционально) проверяет, что ffmpeg PID не меняется.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any, Dict, List, Optional


@dataclass
class Case:
    key: str
    kind: str  # bool|enum|int
    values: Optional[List[Any]] = None


SAFE_CASES: List[Case] = [
    Case("log_level", "enum", ["debug", "info", "warning"]),
    Case("ui_status_polling_interval_sec", "enum", [0.2, 0.5, 1, 2, 4]),
    Case("ui_status_lite_enabled", "bool"),
    Case("performance_aggregate_stream_timers", "bool"),
    Case("performance_aggregate_transcode_timers", "bool"),
    Case("observability_system_rollup_enabled", "bool"),
    Case("lua_gc_step_units", "int", [0, 10, 20, 50]),
]


def api_json(
    base_url: str,
    path: str,
    method: str = "GET",
    payload: Optional[Dict[str, Any]] = None,
    token: Optional[str] = None,
) -> Any:
    url = f"{base_url.rstrip('/')}{path}"
    data = None
    headers = {}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
        headers["X-CSRF-Token"] = token
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            body = resp.read().decode("utf-8")
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"{method} {path} failed: HTTP {exc.code} {body}")


def login(base_url: str, username: str, password: str) -> str:
    body = api_json(
        base_url,
        "/api/v1/auth/login",
        method="POST",
        payload={"username": username, "password": password},
    )
    token = str((body or {}).get("token") or "")
    if not token:
        raise RuntimeError("failed to get auth token")
    return token


def get_uptime(base_url: str, token: str, stream_id: str) -> int:
    status = api_json(base_url, "/api/v1/stream-status?lite=1", token=token)
    entry = status.get(stream_id) if isinstance(status, dict) else None
    if not isinstance(entry, dict):
        return -1
    value = entry.get("uptime_sec")
    try:
        return int(value)
    except Exception:
        return -1


def get_ffmpeg_pid(stream_id: str) -> str:
    cmd = f"pgrep -f 'ffmpeg.*input/{stream_id}' | head -n1"
    try:
        out = subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL).strip()
        return out
    except subprocess.CalledProcessError:
        return ""


def choose_next_value(case: Case, current: Any) -> Optional[Any]:
    if case.kind == "bool":
        cur = bool(current)
        return not cur
    if case.kind in ("enum", "int"):
        values = case.values or []
        for v in values:
            if str(v) != str(current):
                return v
        return None
    return None


def as_json_value(value: Any) -> Any:
    # json.dumps сам корректно сериализует bool/int/float/string.
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="http://127.0.0.1:9060")
    parser.add_argument("--stream", default="a014")
    parser.add_argument("--user", default="admin")
    parser.add_argument("--pass", dest="password", default="admin")
    parser.add_argument("--token", default="")
    parser.add_argument("--wait-sec", type=float, default=2.0)
    parser.add_argument("--check-local-pid", action="store_true")
    parser.add_argument("--max-uptime-drop-sec", type=int, default=1)
    parser.add_argument("--out", default="")
    args = parser.parse_args()

    token = args.token or login(args.base, args.user, args.password)
    settings = api_json(args.base, "/api/v1/settings", token=token)
    if not isinstance(settings, dict):
        raise RuntimeError("invalid /api/v1/settings response")

    results: List[Dict[str, Any]] = []
    failures = 0

    for case in SAFE_CASES:
        if case.key not in settings:
            results.append(
                {
                    "key": case.key,
                    "status": "SKIP",
                    "reason": "missing in settings",
                }
            )
            continue

        original = settings.get(case.key)
        new_value = choose_next_value(case, original)
        if new_value is None:
            results.append(
                {
                    "key": case.key,
                    "status": "SKIP",
                    "reason": "no alternative value",
                }
            )
            continue

        u1 = get_uptime(args.base, token, args.stream)
        p1 = get_ffmpeg_pid(args.stream) if args.check_local_pid else ""

        api_json(
            args.base,
            "/api/v1/settings",
            method="PUT",
            payload={case.key: as_json_value(new_value)},
            token=token,
        )
        time.sleep(args.wait_sec)

        u2 = get_uptime(args.base, token, args.stream)
        p2 = get_ffmpeg_pid(args.stream) if args.check_local_pid else ""

        # Возвращаем исходное значение сразу после проверки кейса.
        api_json(
            args.base,
            "/api/v1/settings",
            method="PUT",
            payload={case.key: as_json_value(original)},
            token=token,
        )

        ok = True
        reason = ""
        if u1 >= 0 and u2 >= 0 and u2 < (u1 - int(args.max_uptime_drop_sec)):
            ok = False
            reason = f"uptime dropped {u1}->{u2}"
        if args.check_local_pid and p1 and p2 and p1 != p2:
            ok = False
            reason = (reason + "; " if reason else "") + f"pid changed {p1}->{p2}"

        if not ok:
            failures += 1

        results.append(
            {
                "key": case.key,
                "from": original,
                "to": new_value,
                "uptime_before": u1,
                "uptime_after": u2,
                "pid_before": p1,
                "pid_after": p2,
                "status": "PASS" if ok else "FAIL",
                "reason": reason,
            }
        )

    lines = []
    lines.append("| key | from | to | uptime | pid | status | note |")
    lines.append("|---|---:|---:|---:|---|---|---|")
    for r in results:
        if r["status"] == "SKIP":
            lines.append(f"| {r['key']} | - | - | - | - | SKIP | {r.get('reason','')} |")
            continue
        uptime_text = f"{r.get('uptime_before')}→{r.get('uptime_after')}"
        pid_text = "-"
        if args.check_local_pid:
            pid_text = f"{r.get('pid_before') or '-'}→{r.get('pid_after') or '-'}"
        lines.append(
            f"| {r['key']} | {r.get('from')} | {r.get('to')} | {uptime_text} | {pid_text} | {r['status']} | {r.get('reason','')} |"
        )

    output = "\n".join(lines)
    print(output)

    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(output + "\n")

    if failures:
        print(f"\nFAILURES: {failures}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

