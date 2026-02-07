# Update Stream Names From SDT (Service Name)

This repo includes a low-impact CLI tool that can refresh `stream.name` by probing each stream input with `astral --analyze` and extracting the SDT service name.

Tool:
- `tools/update_stream_names_from_sdt.py`

## What It Does
- Fetches streams from the running Astral API.
- For each stream, checks inputs in priority order.
- Runs `astral --analyze` with a short timeout.
- Extracts SDT service name (UTF-8 supported).
- Updates `stream.name` (only if a new name is found).

## Safety Defaults (Minimal Load)
- Dry-run by default (no writes).
- Low parallelism by default (`--parallel 2`).
- Per-input timeout (`--timeout-sec 10`).
- Rate limit (`--rate-per-min 30`) to avoid spikes.
- Stops `--analyze` as soon as a name is found for a stream.

## Requirements
- Astral server running and reachable via API.
- Credentials or token with permission to update streams.
- `astral` binary available to run `--analyze` (or provide `--astral-bin`).

## Examples

Dry-run (default):
```bash
python3 tools/update_stream_names_from_sdt.py --api http://127.0.0.1:9060
```

Dry-run with strict limits:
```bash
python3 tools/update_stream_names_from_sdt.py \
  --api http://127.0.0.1:9060 \
  --parallel 2 \
  --timeout-sec 10 \
  --rate-per-min 30
```

Apply changes:
```bash
python3 tools/update_stream_names_from_sdt.py --api http://127.0.0.1:9060 --apply
```

Only streams matching a regex (id or name):
```bash
python3 tools/update_stream_names_from_sdt.py --api http://127.0.0.1:9060 --match "(ntv|viasat)"
```

Force update even if current name already looks human:
```bash
python3 tools/update_stream_names_from_sdt.py --api http://127.0.0.1:9060 --apply --force
```

Use explicit token:
```bash
python3 tools/update_stream_names_from_sdt.py --api http://127.0.0.1:9060 --token "$TOKEN"
```

Parser test without real `--analyze`:
```bash
python3 tools/update_stream_names_from_sdt.py --api http://127.0.0.1:9060 --mock-analyze-file ./fixtures/analyze_sample.txt
```

## Notes
- For MPTS outputs, `--analyze` may print multiple SDT services. The tool tries to prefer the stream `pnr`/`set_pnr` or the first `#pnr=` in inputs (when present).
- If a stream has no working inputs (within timeout), it is skipped and counted as `failed`.

