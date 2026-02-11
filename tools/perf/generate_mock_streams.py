#!/usr/bin/env python3
import argparse
import json


def make_stream(i: int):
    sid = f"perf_{i:04d}"
    return {
        "id": sid,
        "name": f"Perf Stream {i:04d}",
        "type": "stream",
        "enable": True,
        "input": [
            {
                "url": f"udp://239.10.{(i // 250) % 255}.{(i % 250) + 1}:{10000 + i}",
                "name": "primary"
            }
        ],
        "output": [],
    }


def main():
    ap = argparse.ArgumentParser(description="Generate mock stream config list for perf tests")
    ap.add_argument("--count", type=int, default=200)
    ap.add_argument("--out", default="tools/perf/mock_streams.json")
    args = ap.parse_args()

    payload = [make_stream(i + 1) for i in range(max(1, args.count))]
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    print(f"written {len(payload)} streams -> {args.out}")


if __name__ == "__main__":
    main()
