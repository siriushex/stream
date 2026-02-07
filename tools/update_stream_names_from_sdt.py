#!/usr/bin/env python3
"""
Update stream.name from SDT service name by probing inputs via `astral --analyze`.

Design goals:
- Safe by default: dry-run unless --apply is provided.
- Low resource usage: small parallelism, per-input timeout, and stream rate limiting.
- Best-effort parsing across Astral/Astra analyze output variants.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple


ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")

# Legacy/variant analyzer outputs (keep these permissive).
SDT_SERVICE_RE = re.compile(r"SDT\s+service:(.+)\s*$", re.IGNORECASE)
SDT_DESCRIPTOR_SERVICE_RE = re.compile(r"SDT:.*\bService:\s*(.+)\s*$")
SDT_SERVICE_NAME_RE = re.compile(r"SDT:\s*service_name:\s*sid=(\d+)\s+value=(.+)\s*$")


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def normalize_api_base(value: str) -> str:
    base = value.strip()
    if base.endswith("/"):
        base = base[:-1]
    if base.endswith("/api/v1"):
        base = base[:-7]
    return base


def http_json(
    method: str,
    url: str,
    token: Optional[str] = None,
    payload: Optional[Dict[str, Any]] = None,
    timeout: int = 20,
) -> Any:
    data = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        data = body
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            if not raw:
                return None
            return json.loads(raw.decode("utf-8", errors="replace"))
    except urllib.error.HTTPError as exc:
        raw = exc.read() if hasattr(exc, "read") else b""
        msg = raw.decode("utf-8", errors="replace").strip() if raw else str(exc)
        raise RuntimeError(f"http {exc.code}: {msg}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"network error: {exc}") from exc


def login(api_base: str, username: str, password: str) -> str:
    url = f"{api_base}/api/v1/auth/login"
    data = http_json("POST", url, None, {"username": username, "password": password})
    token = (data or {}).get("token")
    if not token:
        raise RuntimeError("login failed: missing token")
    return str(token)


def ensure_list(value: Any) -> List[str]:
    if value is None:
        return []
    if isinstance(value, list):
        out: List[str] = []
        for item in value:
            if item is None:
                continue
            text = str(item).strip()
            if text:
                out.append(text)
        return out
    text = str(value).strip()
    return [text] if text else []


def extract_pnr_from_url(url: str) -> Optional[int]:
    # Input options in Astral URLs are typically passed via the fragment (#key=value&...).
    try:
        parts = urllib.parse.urlsplit(url)
    except Exception:
        return None
    frag = parts.fragment or ""
    if not frag:
        return None
    for chunk in frag.split("&"):
        if not chunk or "=" not in chunk:
            continue
        k, v = chunk.split("=", 1)
        k = k.strip().lower()
        if k in ("pnr", "set_pnr", "program", "sid"):
            try:
                return int(v.strip())
            except ValueError:
                return None
    return None


def looks_placeholder_name(name: str, stream_id: str) -> bool:
    n = (name or "").strip()
    if not n:
        return True
    if n == stream_id:
        return True
    low = n.lower()
    if low == f"stream {stream_id}".lower():
        return True
    if low.startswith("stream_") or low.startswith("stream-"):
        return True
    return False


@dataclass
class AnalyzeResult:
    service_name: Optional[str]
    preferred_sid: Optional[int]
    matched_sid: Optional[int]
    url: str
    error: Optional[str] = None


def parse_service_names_from_analyze_text(text: str) -> Tuple[List[Tuple[Optional[int], str]], Optional[str]]:
    services: List[Tuple[Optional[int], str]] = []
    first_fallback: Optional[str] = None
    for raw_line in (text or "").splitlines():
        line = ANSI_RE.sub("", raw_line).strip()
        if not line:
            continue

        m = SDT_SERVICE_NAME_RE.search(line)
        if m:
            sid = int(m.group(1))
            name = m.group(2).strip()
            if name:
                services.append((sid, name))
            continue

        m = SDT_SERVICE_RE.search(line)
        if m:
            name = m.group(1).strip()
            if name:
                first_fallback = first_fallback or name
            continue

        m = SDT_DESCRIPTOR_SERVICE_RE.search(line)
        if m:
            name = m.group(1).strip()
            if name:
                first_fallback = first_fallback or name
            continue

    if not services and first_fallback:
        services.append((None, first_fallback))
    return services, first_fallback


async def run_analyze_for_url(
    astral_bin: str,
    input_url: str,
    timeout_sec: int,
    preferred_sid: Optional[int],
    mock_text: Optional[str],
) -> AnalyzeResult:
    if mock_text is not None:
        services, _ = parse_service_names_from_analyze_text(mock_text)
        match_sid = None
        name = None
        if preferred_sid is not None:
            for sid, sname in services:
                if sid == preferred_sid:
                    name = sname
                    match_sid = sid
                    break
        if name is None and services:
            match_sid, name = services[0]
        return AnalyzeResult(service_name=name, preferred_sid=preferred_sid, matched_sid=match_sid, url=input_url)

    # Use -n to limit analyzer runtime, but still enforce an external timeout.
    nsec = max(1, int(timeout_sec))
    argv = [astral_bin, "--analyze", "-n", str(nsec), input_url]

    try:
        proc = await asyncio.create_subprocess_exec(
            *argv,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
    except FileNotFoundError:
        return AnalyzeResult(None, preferred_sid, None, input_url, error=f"astral bin not found: {astral_bin}")
    except Exception as exc:
        return AnalyzeResult(None, preferred_sid, None, input_url, error=f"failed to start analyze: {exc}")

    services: List[Tuple[Optional[int], str]] = []
    matched_sid: Optional[int] = None
    service_name: Optional[str] = None

    start = time.monotonic()
    try:
        assert proc.stdout is not None
        while True:
            remaining = timeout_sec - (time.monotonic() - start)
            if remaining <= 0:
                break
            try:
                line_b = await asyncio.wait_for(proc.stdout.readline(), timeout=remaining)
            except asyncio.TimeoutError:
                break
            if not line_b:
                break
            line = line_b.decode("utf-8", errors="replace")
            line = ANSI_RE.sub("", line).strip()
            if not line:
                continue

            # Prefer stable key/value output when available.
            m = SDT_SERVICE_NAME_RE.search(line)
            if m:
                sid = int(m.group(1))
                name = m.group(2).strip()
                if name:
                    services.append((sid, name))
                    if preferred_sid is not None and sid == preferred_sid:
                        matched_sid = sid
                        service_name = name
                        break
                    if preferred_sid is None and service_name is None:
                        matched_sid = sid
                        service_name = name
                        break
                continue

            # Backward-compatible outputs.
            m = SDT_SERVICE_RE.search(line) or SDT_DESCRIPTOR_SERVICE_RE.search(line)
            if m:
                name = m.group(1).strip()
                if name:
                    services.append((None, name))
                    if preferred_sid is None and service_name is None:
                        matched_sid = None
                        service_name = name
                        break
    finally:
        # Stop early to reduce load.
        if proc.returncode is None:
            proc.terminate()
            try:
                await asyncio.wait_for(proc.wait(), timeout=0.6)
            except asyncio.TimeoutError:
                proc.kill()
                try:
                    await asyncio.wait_for(proc.wait(), timeout=0.6)
                except asyncio.TimeoutError:
                    pass

    if service_name is None and preferred_sid is not None:
        # Preferred SID not found, fall back to the first name if any.
        if services:
            matched_sid, service_name = services[0]

    return AnalyzeResult(service_name=service_name, preferred_sid=preferred_sid, matched_sid=matched_sid, url=input_url)


class RateLimiter:
    def __init__(self, rate_per_min: int) -> None:
        self.rate = max(1, int(rate_per_min))
        self._starts: List[float] = []
        self._lock = asyncio.Lock()

    async def acquire(self) -> None:
        async with self._lock:
            now = time.monotonic()
            window = 60.0
            self._starts = [t for t in self._starts if now - t < window]
            if len(self._starts) < self.rate:
                self._starts.append(now)
                return
            oldest = min(self._starts)
            sleep_for = max(0.0, window - (now - oldest))
        if sleep_for > 0:
            await asyncio.sleep(sleep_for)
        async with self._lock:
            now = time.monotonic()
            self._starts = [t for t in self._starts if now - t < 60.0]
            self._starts.append(now)


def compile_match(pattern: Optional[str]) -> Optional[re.Pattern[str]]:
    if not pattern:
        return None
    return re.compile(pattern)


def stream_matches(stream_id: str, name: str, rx: Optional[re.Pattern[str]], ids: Optional[Iterable[str]]) -> bool:
    if ids:
        wanted = {str(x) for x in ids}
        if stream_id not in wanted:
            return False
    if rx is None:
        return True
    hay = f"{stream_id} {name}".strip()
    return rx.search(hay) is not None


async def main_async() -> int:
    parser = argparse.ArgumentParser(description="Update stream names from SDT service name via `astral --analyze`.")
    parser.add_argument("--api", default="http://127.0.0.1:9060", help="Astral base URL (default: http://127.0.0.1:9060)")
    parser.add_argument("--token", default="", help="API token (Bearer). If empty, will login.")
    parser.add_argument("--username", default=os.getenv("ASTRAL_USER", "admin"), help="Login username (default: admin)")
    parser.add_argument("--password", default=os.getenv("ASTRAL_PASS", "admin"), help="Login password (default: admin)")
    parser.add_argument("--astral-bin", default="", help="Path to astral binary (default: ./astral or astral)")
    parser.add_argument("--timeout-sec", type=int, default=10, help="Per-input analyze timeout in seconds (default: 10)")
    parser.add_argument("--parallel", type=int, default=2, help="Max concurrent streams (default: 2)")
    parser.add_argument("--rate-per-min", type=int, default=30, help="Max streams per minute (default: 30)")
    parser.add_argument("--only-enabled", action="store_true", default=True, help="Process only enabled streams (default: true)")
    parser.add_argument("--all", action="store_true", help="Process enabled and disabled streams")
    parser.add_argument("--id", dest="ids", action="append", default=[], help="Stream id to process (repeatable)")
    parser.add_argument("--match", default="", help="Regex to match streams by id or name")
    parser.add_argument("--force", action="store_true", help="Update even if current name looks human")
    parser.add_argument("--apply", action="store_true", help="Apply changes (default: dry-run)")
    parser.add_argument("--max-streams", type=int, default=0, help="Optional limit on processed streams (0 = no limit)")
    parser.add_argument("--mock-analyze-file", default="", help="Use static analyze output from file (testing)")

    args = parser.parse_args()

    api_base = normalize_api_base(args.api)
    base_v1 = f"{api_base}/api/v1"

    repo_root = Path(__file__).resolve().parent.parent
    default_bin = str(repo_root / "astral") if (repo_root / "astral").exists() else "astral"
    astral_bin = args.astral_bin.strip() or default_bin

    dry_run = not bool(args.apply)
    only_enabled = bool(args.only_enabled) and not bool(args.all)
    parallel = max(1, int(args.parallel))

    rx = compile_match(args.match.strip() or None)
    ids = [x.strip() for x in (args.ids or []) if x and x.strip()]
    limiter = RateLimiter(args.rate_per_min)

    mock_text = None
    if args.mock_analyze_file:
        mock_path = Path(args.mock_analyze_file)
        mock_text = mock_path.read_text(encoding="utf-8", errors="replace")

    token = args.token.strip() or None
    if token is None:
        token = await asyncio.to_thread(login, api_base, args.username, args.password)

    streams = await asyncio.to_thread(http_json, "GET", f"{base_v1}/streams", token, None)
    if not isinstance(streams, list):
        raise RuntimeError("invalid /streams response")

    work: List[Dict[str, Any]] = []
    for item in streams:
        if not isinstance(item, dict):
            continue
        stream_id = str(item.get("id", "")).strip()
        cfg = item.get("config") if isinstance(item.get("config"), dict) else {}
        name = str(cfg.get("name", "") or "")
        enabled = bool(item.get("enabled", True))
        if only_enabled and not enabled:
            continue
        if not stream_id:
            continue
        if not stream_matches(stream_id, name, rx, ids):
            continue
        work.append(item)

    if args.max_streams and args.max_streams > 0:
        work = work[: int(args.max_streams)]

    eprint(f"Streams selected: {len(work)} (dry_run={dry_run}, parallel={parallel}, timeout={args.timeout_sec}s)")

    updated = 0
    skipped = 0
    failed = 0

    async def handle_stream(item: Dict[str, Any]) -> None:
        nonlocal updated, skipped, failed
        stream_id = str(item.get("id", "")).strip()
        cfg = item.get("config") if isinstance(item.get("config"), dict) else {}
        enabled = bool(item.get("enabled", True))
        old_name = str(cfg.get("name", "") or "")

        if not args.force and not looks_placeholder_name(old_name, stream_id):
            skipped += 1
            return

        inputs = ensure_list(cfg.get("input"))
        if not inputs:
            skipped += 1
            return

        # Prefer pnr hints when present.
        preferred_sid = None
        if isinstance(cfg.get("pnr"), int):
            preferred_sid = int(cfg["pnr"])
        elif isinstance(cfg.get("set_pnr"), int):
            preferred_sid = int(cfg["set_pnr"])
        else:
            for u in inputs:
                preferred_sid = extract_pnr_from_url(u)
                if preferred_sid is not None:
                    break

        await limiter.acquire()
        new_name = None
        used_url = None
        for u in inputs:
            res = await run_analyze_for_url(
                astral_bin=astral_bin,
                input_url=u,
                timeout_sec=int(args.timeout_sec),
                preferred_sid=preferred_sid,
                mock_text=mock_text,
            )
            if res.error:
                continue
            if res.service_name:
                new_name = res.service_name
                used_url = u
                break

        if not new_name:
            failed += 1
            return

        if new_name.strip() == old_name.strip():
            skipped += 1
            return

        print(f"{stream_id}: {old_name or '(empty)'} -> {new_name} (via {used_url})")

        if dry_run:
            updated += 1
            return

        next_cfg = dict(cfg)
        next_cfg["id"] = stream_id
        next_cfg["name"] = new_name
        payload = {"enabled": bool(enabled), "config": next_cfg}
        await asyncio.to_thread(http_json, "PUT", f"{base_v1}/streams/{urllib.parse.quote(stream_id)}", token, payload)
        updated += 1

    q: asyncio.Queue[Dict[str, Any]] = asyncio.Queue()
    for item in work:
        q.put_nowait(item)

    async def worker() -> None:
        while True:
            try:
                item = q.get_nowait()
            except asyncio.QueueEmpty:
                return
            try:
                await handle_stream(item)
            finally:
                q.task_done()

    workers = [asyncio.create_task(worker()) for _ in range(parallel)]
    await q.join()
    await asyncio.gather(*workers)

    eprint(f"Done. updated={updated} skipped={skipped} failed={failed} (apply={not dry_run})")
    return 0


def main() -> int:
    try:
        return asyncio.run(main_async())
    except KeyboardInterrupt:
        eprint("Interrupted.")
        return 130
    except Exception as exc:
        eprint(f"Error: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

