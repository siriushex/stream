#!/usr/bin/env python3
import argparse
import json
import pathlib
from statistics import fmean


def parse_samples(path: pathlib.Path):
    cpu = []
    rss = []
    threads = []
    fds = []
    if not path.exists():
        return None
    for line in path.read_text().splitlines():
        parts = {}
        for token in line.strip().split():
            if "=" not in token:
                continue
            k, v = token.split("=", 1)
            parts[k] = v
        try:
            cpu.append(float(parts.get("cpu_pct", 0)))
            rss.append(float(parts.get("rss_kb", 0)))
            threads.append(float(parts.get("threads", 0)))
            fds.append(float(parts.get("fds", 0)))
        except ValueError:
            continue
    if not cpu:
        return None
    return {
        "cpu_avg_pct": round(fmean(cpu), 2),
        "rss_avg_mb": round(fmean(rss) / 1024.0, 2),
        "threads_avg": round(fmean(threads), 2),
        "fds_avg": round(fmean(fds), 2),
    }


def parse_latency(path: pathlib.Path):
    if not path.exists():
        return None
    try:
        obj = json.loads(path.read_text())
    except Exception:
        return None
    lat = obj.get("latency_ms") or {}
    return {
        "requests_ok": obj.get("ok"),
        "errors": obj.get("errors"),
        "rps": obj.get("rps"),
        "p95_ms": lat.get("p95"),
        "p99_ms": lat.get("p99"),
        "avg_ms": lat.get("avg"),
    }


def report_case(name: str, latency_path: pathlib.Path, samples_path: pathlib.Path):
    lat = parse_latency(latency_path)
    smp = parse_samples(samples_path)
    if not lat and not smp:
        return None
    return {
        "case": name,
        **(lat or {}),
        **(smp or {}),
    }


def main():
    ap = argparse.ArgumentParser(description="Summarize tools/perf/run_polling_suite.sh output")
    ap.add_argument("--dir", required=True, help="Results directory")
    args = ap.parse_args()

    root = pathlib.Path(args.dir)
    cases = [
        report_case("status_full", root / "status_full.json", root / "status_full_samples.log"),
        report_case("status_lite", root / "status_lite.json", root / "status_lite_samples.log"),
    ]
    cases = [c for c in cases if c]
    if not cases:
        raise SystemExit("No cases found in result directory")

    print("| case | ok | errors | rps | p95 ms | p99 ms | avg cpu % | avg rss MB | avg threads | avg fds |")
    print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for c in cases:
        print(
            f"| {c.get('case','-')} | {c.get('requests_ok','-')} | {c.get('errors','-')} | "
            f"{c.get('rps','-')} | {c.get('p95_ms','-')} | {c.get('p99_ms','-')} | "
            f"{c.get('cpu_avg_pct','-')} | {c.get('rss_avg_mb','-')} | "
            f"{c.get('threads_avg','-')} | {c.get('fds_avg','-')} |"
        )


if __name__ == "__main__":
    main()
