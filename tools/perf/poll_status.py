#!/usr/bin/env python3
import argparse
import json
import math
import statistics
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed


def one_request(url: str, timeout: float, headers: dict):
    start = time.perf_counter()
    try:
        req = urllib.request.Request(url, method="GET")
        for key, value in headers.items():
            req.add_header(key, value)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            _ = resp.read()
            end = time.perf_counter()
            return True, (end - start) * 1000.0, int(getattr(resp, "status", 200)), ""
    except urllib.error.HTTPError as exc:
        try:
            _ = exc.read()
        except Exception:
            pass
        end = time.perf_counter()
        return False, (end - start) * 1000.0, int(exc.code), f"http_{exc.code}"
    except Exception as exc:
        end = time.perf_counter()
        return False, (end - start) * 1000.0, None, exc.__class__.__name__


def percentile(values, p):
    if not values:
        return float("nan")
    arr = sorted(values)
    if len(arr) == 1:
        return arr[0]
    idx = (len(arr) - 1) * p
    lo = math.floor(idx)
    hi = math.ceil(idx)
    if lo == hi:
        return arr[int(idx)]
    w = idx - lo
    return arr[lo] * (1 - w) + arr[hi] * w


def run(url: str, total: int, concurrency: int, timeout: float, headers: dict):
    lat = []
    errors = 0
    error_types = {}
    http_status = {}
    first_error = ""
    start = time.perf_counter()
    with ThreadPoolExecutor(max_workers=concurrency) as pool:
        futures = [pool.submit(one_request, url, timeout, headers) for _ in range(total)]
        for fut in as_completed(futures):
            try:
                ok, latency_ms, status_code, error_key = fut.result()
                if ok:
                    lat.append(latency_ms)
                else:
                    errors += 1
                    if status_code is not None:
                        key = str(status_code)
                        http_status[key] = http_status.get(key, 0) + 1
                    error_types[error_key] = error_types.get(error_key, 0) + 1
                    if not first_error:
                        first_error = error_key
            except Exception:
                errors += 1
                key = "future_exception"
                error_types[key] = error_types.get(key, 0) + 1
                if not first_error:
                    first_error = key
    end = time.perf_counter()
    elapsed = end - start
    rps = (len(lat) / elapsed) if elapsed > 0 else 0
    return {
        "url": url,
        "requests": total,
        "ok": len(lat),
        "errors": errors,
        "duration_sec": round(elapsed, 3),
        "rps": round(rps, 2),
        "attempts_per_sec": round((total / elapsed), 2) if elapsed > 0 else 0.0,
        "latency_ms": {
            "avg": round(statistics.fmean(lat), 2) if lat else None,
            "p50": round(percentile(lat, 0.50), 2) if lat else None,
            "p95": round(percentile(lat, 0.95), 2) if lat else None,
            "p99": round(percentile(lat, 0.99), 2) if lat else None,
            "max": round(max(lat), 2) if lat else None,
        },
        "http_status": http_status,
        "error_types": error_types,
        "first_error": first_error if first_error else None,
    }


def main():
    ap = argparse.ArgumentParser(description="Status endpoint latency benchmark")
    ap.add_argument("--url", required=True, help="Endpoint URL, e.g. http://127.0.0.1:8000/api/v1/stream-status")
    ap.add_argument("--requests", type=int, default=500)
    ap.add_argument("--concurrency", type=int, default=10)
    ap.add_argument("--timeout", type=float, default=3.0)
    ap.add_argument("--bearer", default="", help="Bearer token for Authorization header")
    ap.add_argument("--header", action="append", default=[],
                    help="Extra header in Key:Value format; can be repeated")
    args = ap.parse_args()

    headers = {}
    if args.bearer:
        headers["Authorization"] = f"Bearer {args.bearer}"
    for raw in args.header:
        if ":" not in raw:
            continue
        key, value = raw.split(":", 1)
        headers[key.strip()] = value.strip()

    report = run(args.url, args.requests, args.concurrency, args.timeout, headers)
    if headers:
        report["headers"] = list(headers.keys())
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
