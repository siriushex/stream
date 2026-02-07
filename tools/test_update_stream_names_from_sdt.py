#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import sys


def load_module():
    mod_path = Path(__file__).resolve().parent / "update_stream_names_from_sdt.py"
    spec = importlib.util.spec_from_file_location("update_stream_names_from_sdt", str(mod_path))
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    # dataclasses expects the module to be present in sys.modules during exec_module
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)  # type: ignore[attr-defined]
    return mod


def test_parser_services():
    mod = load_module()
    text = (Path(__file__).resolve().parent.parent / "fixtures" / "analyze_sample.txt").read_text(
        encoding="utf-8", errors="replace"
    )
    services, fallback = mod.parse_service_names_from_analyze_text(text)
    # Fallback may be present even if service_name lines are present.
    assert fallback == "Shopping Live"
    assert (801, "КИНОТВ") in services
    assert (802, "Комедия") in services


def test_parser_fallback():
    mod = load_module()
    services, fallback = mod.parse_service_names_from_analyze_text("SDT    service:Сарафан\n")
    assert fallback == "Сарафан"
    assert services == [(None, "Сарафан")]


def test_extract_pnr_from_url():
    mod = load_module()
    assert mod.extract_pnr_from_url("udp://239.0.0.1:1234#pnr=1106&cam=ntv") == 1106
    assert mod.extract_pnr_from_url("http://example.com/stream.m3u8") is None


def main():
    test_parser_services()
    test_parser_fallback()
    test_extract_pnr_from_url()
    print("ok")


if __name__ == "__main__":
    main()
