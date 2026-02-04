#!/usr/bin/env python3
import json
import re
from pathlib import Path


def read_text(path):
    return Path(path).read_text(encoding="utf-8")


def find_function_body(text, name):
    marker = f"function {name}("
    start = text.find(marker)
    if start == -1:
        return None
    brace = text.find("{", start)
    if brace == -1:
        return None
    depth = 0
    for idx in range(brace, len(text)):
        ch = text[idx]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[brace + 1:idx]
    return None


def extract_object_literal(text, start_idx):
    brace = text.find("{", start_idx)
    if brace == -1:
        return None, -1
    depth = 0
    for idx in range(brace, len(text)):
        ch = text[idx]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[brace + 1:idx], idx + 1
    return None, -1


def extract_object_keys(obj_text):
    if not obj_text:
        return []
    keys = set(re.findall(r"\b([A-Za-z0-9_]+)\s*:", obj_text))
    shorthand = re.findall(r"^\s*([A-Za-z0-9_]+)\s*,\s*$", obj_text, flags=re.M)
    tail = re.findall(r"^\s*([A-Za-z0-9_]+)\s*$", obj_text, flags=re.M)
    keys.update(shorthand)
    keys.update(tail)
    return sorted(keys)


def extract_object_keys_lua(obj_text):
    if not obj_text:
        return []
    return sorted(set(re.findall(r"\b([A-Za-z0-9_]+)\s*=", obj_text)))


def unique_sorted(values):
    return sorted({v for v in values if v})


def extract_ui_settings(app_text):
    read_keys = re.findall(r"getSetting(?:String|Number|Bool)\(\s*'([^']+)'", app_text)
    read_keys += re.findall(r'getSetting(?:String|Number|Bool)\(\s*"([^"]+)"', app_text)
    read_keys = unique_sorted(read_keys)

    write_groups = {}
    for match in re.finditer(r"function (collect[A-Za-z0-9]+Settings)\(", app_text):
        name = match.group(1)
        body = find_function_body(app_text, name)
        if not body:
            continue
        ret_idx = body.find("return {")
        if ret_idx == -1:
            continue
        obj_text, _ = extract_object_literal(body, ret_idx)
        write_groups[name] = extract_object_keys(obj_text)

    write_keys = unique_sorted([k for keys in write_groups.values() for k in keys])
    all_keys = unique_sorted(read_keys + write_keys)
    return {
        "read_keys": read_keys,
        "write_keys": write_keys,
        "write_groups": write_groups,
        "all_keys": all_keys,
    }


def extract_ui_read_output(app_text):
    body = find_function_body(app_text, "readOutputForm")
    outputs = {}
    if not body:
        return outputs
    idx = 0
    while True:
        ret_idx = body.find("return {", idx)
        if ret_idx == -1:
            break
        obj_text, next_idx = extract_object_literal(body, ret_idx)
        keys = extract_object_keys(obj_text)
        fmt_match = re.search(r"\bformat\s*:\s*'([^']+)'", obj_text)
        if not fmt_match:
            fmt_match = re.search(r'\bformat\s*:\s*"([^"]+)"', obj_text)
        fmt = fmt_match.group(1) if fmt_match else "udp/rtp"
        outputs.setdefault(fmt, [])
        outputs[fmt] = unique_sorted(outputs[fmt] + keys)
        idx = next_idx if next_idx > 0 else ret_idx + 1
    return outputs


def extract_ui_read_input(app_text):
    body = find_function_body(app_text, "readInputForm")
    if not body:
        return {"option_keys": [], "data_keys": []}
    option_keys = re.findall(r"add(?:Number|String)\(\s*'([^']+)'", body)
    option_keys += re.findall(r'add(?:Number|String)\(\s*"([^"]+)"', body)
    option_keys += re.findall(r"\boptions\.([A-Za-z0-9_]+)\s*=", body)
    option_keys = unique_sorted(option_keys)

    data_keys = re.findall(r"\bdata\.([A-Za-z0-9_]+)\s*=", body)
    data_keys = unique_sorted(data_keys)
    return {
        "option_keys": option_keys,
        "data_keys": data_keys,
    }


def extract_ui_stream_form(app_text):
    body = find_function_body(app_text, "readStreamForm")
    if not body:
        return {}
    config_keys = []
    idx = body.find("const config = {")
    if idx != -1:
        obj_text, _ = extract_object_literal(body, idx)
        config_keys += extract_object_keys(obj_text)
    config_keys += re.findall(r"\bconfig\.([A-Za-z0-9_]+)\s*=", body)

    transcode_keys = re.findall(r"\btranscode\.([A-Za-z0-9_]+)\s*=", body)
    watchdog_keys = re.findall(r"\bwatchdog\.([A-Za-z0-9_]+)\s*=", body)
    output_keys = re.findall(r"\bcleaned\.([A-Za-z0-9_]+)\s*=", body)

    return {
        "config_keys": unique_sorted(config_keys),
        "transcode_keys": unique_sorted(transcode_keys),
        "transcode_output_keys": unique_sorted(output_keys),
        "transcode_watchdog_keys": unique_sorted(watchdog_keys),
    }


def extract_ui_adapter_form(app_text):
    body = find_function_body(app_text, "readAdapterForm")
    if not body:
        return {}
    config_keys = []
    idx = body.find("const config = {")
    if idx != -1:
        obj_text, _ = extract_object_literal(body, idx)
        config_keys += extract_object_keys(obj_text)
    config_keys += re.findall(r"\bconfig\.([A-Za-z0-9_]+)\s*=", body)
    return {
        "config_keys": unique_sorted(config_keys),
        "top_level_keys": ["id", "enabled", "config"],
    }


def extract_ui_buffer(app_text):
    body = find_function_body(app_text, "readBufferForm")
    resource_keys = []
    if body:
        idx = body.find("return {")
        if idx != -1:
            obj_text, _ = extract_object_literal(body, idx)
            resource_keys = extract_object_keys(obj_text)

    input_keys = []
    body = find_function_body(app_text, "saveBufferInput")
    if body:
        idx = body.find("const payload = {")
        if idx != -1:
            obj_text, _ = extract_object_literal(body, idx)
            input_keys = extract_object_keys(obj_text)

    allow_keys = []
    body = find_function_body(app_text, "saveBufferAllow")
    if body:
        idx = body.find("const payload = {")
        if idx != -1:
            obj_text, _ = extract_object_literal(body, idx)
            allow_keys = extract_object_keys(obj_text)

    return {
        "resource_keys": unique_sorted(resource_keys),
        "input_keys": unique_sorted(input_keys),
        "allow_keys": unique_sorted(allow_keys),
    }


def extract_ui_splitter(app_text):
    config_keys = []
    body = find_function_body(app_text, "saveSplitter")
    if body:
        idx = body.find("const payload = {")
        if idx != -1:
            obj_text, _ = extract_object_literal(body, idx)
            config_keys = extract_object_keys(obj_text)

    link_keys = []
    body = find_function_body(app_text, "saveSplitterLink")
    if body:
        idx = body.find("const payload = {")
        if idx != -1:
            obj_text, _ = extract_object_literal(body, idx)
            link_keys = extract_object_keys(obj_text)

    allow_keys = []
    body = find_function_body(app_text, "saveSplitterAllow")
    if body:
        idx = body.find("const payload = {")
        if idx != -1:
            obj_text, _ = extract_object_literal(body, idx)
            allow_keys = extract_object_keys(obj_text)

    return {
        "config_keys": unique_sorted(config_keys),
        "link_keys": unique_sorted(link_keys),
        "allow_keys": unique_sorted(allow_keys),
    }


def extract_lua_settings(script_paths):
    key_sources = {}
    key_pattern = re.compile(
        r"\b(?:get_setting|setting_(?:string|number|bool)|"
        r"config\.get_setting|config\.set_setting|"
        r"password_setting_(?:bool|number))\(\s*['\"]([^'\"]+)['\"]"
    )
    payload_pattern = re.compile(r"payload\.settings\.([A-Za-z0-9_]+)")
    for path in script_paths:
        text = read_text(path)
        keys = set(key_pattern.findall(text))
        keys.update(payload_pattern.findall(text))
        if not keys:
            continue
        for key in keys:
            key_sources.setdefault(key, []).append(path.name)
    for key, files in key_sources.items():
        key_sources[key] = sorted(set(files))
    return {
        "keys": unique_sorted(key_sources.keys()),
        "sources": key_sources,
    }


def extract_lua_stream_conf(script_path):
    text = read_text(script_path)
    keys = re.findall(r"\bconf\.([A-Za-z0-9_]+)", text)
    return unique_sorted(keys)


def extract_lua_transcode(script_path):
    text = read_text(script_path)
    tc_keys = re.findall(r"\btc\.([A-Za-z0-9_]+)", text)
    output_keys = re.findall(r"\boutput\.([A-Za-z0-9_]+)", text)
    watchdog_keys = []
    body = find_function_body(text, "normalize_watchdog")
    if body:
        ret_idx = body.find("return {")
        if ret_idx != -1:
            obj_text, _ = extract_object_literal(body, ret_idx)
            watchdog_keys = extract_object_keys(obj_text)
    return {
        "transcode_keys": unique_sorted(tc_keys),
        "output_keys": unique_sorted(output_keys),
        "watchdog_keys": unique_sorted(watchdog_keys),
    }


def extract_export_schema(config_text):
    top_level = unique_sorted(re.findall(r"\bpayload\.([A-Za-z0-9_]+)\s*=", config_text))

    def extract_keys_between(start_marker, end_marker):
        end_idx = config_text.find(end_marker)
        if end_idx == -1:
            return ""
        start_idx = config_text.rfind(start_marker, 0, end_idx)
        if start_idx == -1:
            start_idx = 0
        return config_text[start_idx:end_idx]

    def extract_entry_keys(segment, entry_marker, entry_name):
        idx = segment.find(entry_marker)
        if idx == -1:
            return []
        obj_text, _ = extract_object_literal(segment, idx)
        keys = extract_object_keys_lua(obj_text)
        keys += re.findall(rf"\b{re.escape(entry_name)}\.([A-Za-z0-9_]+)\s*=", segment)
        return unique_sorted(keys)

    users_segment = extract_keys_between("local users", "payload.users = users")
    user_keys = extract_entry_keys(users_segment, "local entry = {", "entry")

    splitters_segment = extract_keys_between("local splitters", "payload.splitters = splitters")
    splitter_keys = extract_entry_keys(splitters_segment, "local entry = {", "entry")
    link_keys = extract_entry_keys(splitters_segment, "local link_entry = {", "link_entry")
    allow_keys = extract_entry_keys(splitters_segment, "table.insert(allow, {", "allow")

    return {
        "top_level_keys": top_level,
        "users_entry_keys": user_keys,
        "splitter_entry_keys": splitter_keys,
        "splitter_link_keys": link_keys,
        "splitter_allow_keys": allow_keys,
    }


def diff_sets(left, right):
    left_set = set(left)
    right_set = set(right)
    return {
        "common": unique_sorted(left_set & right_set),
        "left_only": unique_sorted(left_set - right_set),
        "right_only": unique_sorted(right_set - left_set),
    }


def main():
    repo_root = Path(__file__).resolve().parents[3]
    astra_root = repo_root / "astra"
    app_js = astra_root / "web" / "app.js"
    scripts_dir = astra_root / "scripts"

    app_text = read_text(app_js)
    script_paths = sorted(p for p in scripts_dir.glob("*.lua") if p.is_file())

    ui_settings = extract_ui_settings(app_text)
    ui_outputs = extract_ui_read_output(app_text)
    ui_inputs = extract_ui_read_input(app_text)
    ui_stream = extract_ui_stream_form(app_text)
    ui_adapter = extract_ui_adapter_form(app_text)
    ui_buffer = extract_ui_buffer(app_text)
    ui_splitter = extract_ui_splitter(app_text)

    lua_settings = extract_lua_settings(script_paths)
    lua_stream_keys = extract_lua_stream_conf(scripts_dir / "stream.lua")
    lua_transcode = extract_lua_transcode(scripts_dir / "transcode.lua")
    export_schema = extract_export_schema(read_text(scripts_dir / "config.lua"))

    output_union = []
    for keys in ui_outputs.values():
        output_union.extend(keys)
    output_union = unique_sorted([k for k in output_union if k not in ("format", "auto")])

    input_union = unique_sorted(ui_inputs["option_keys"] + ui_inputs["data_keys"])

    settings_diff = diff_sets(ui_settings["all_keys"], lua_settings["keys"])
    stream_diff = diff_sets(ui_stream.get("config_keys", []), lua_stream_keys)
    transcode_diff = diff_sets(ui_stream.get("transcode_keys", []), lua_transcode["transcode_keys"])
    output_diff = diff_sets(output_union, lua_stream_keys)
    input_diff = diff_sets(input_union, lua_stream_keys)
    transcode_output_diff = diff_sets(
        ui_stream.get("transcode_output_keys", []),
        lua_transcode["output_keys"]
    )

    output = {
        "ui": {
            "settings": ui_settings,
            "streams": {
                "config_keys": ui_stream.get("config_keys", []),
                "input_option_keys": ui_inputs["option_keys"],
                "input_url_parts": ui_inputs["data_keys"],
                "output_fields": ui_outputs,
                "transcode_config_keys": ui_stream.get("transcode_keys", []),
                "transcode_output_keys": ui_stream.get("transcode_output_keys", []),
                "transcode_watchdog_keys": ui_stream.get("transcode_watchdog_keys", []),
            },
            "adapters": ui_adapter,
            "buffers": ui_buffer,
            "splitters": ui_splitter,
        },
        "lua": {
            "settings": lua_settings,
            "stream_conf_keys": lua_stream_keys,
            "transcode": lua_transcode,
        },
        "json_schema": export_schema,
        "diffs": {
            "settings_ui_vs_lua": settings_diff,
            "stream_ui_vs_runtime": stream_diff,
            "transcode_ui_vs_runtime": transcode_diff,
            "output_ui_vs_runtime": output_diff,
            "input_ui_vs_runtime": input_diff,
            "transcode_output_ui_vs_runtime": transcode_output_diff,
        },
    }

    out_path = repo_root / "astra" / "re" / "astra-250612-diff-config-ui.json"
    out_path.write_text(json.dumps(output, indent=2, sort_keys=True), encoding="utf-8")


if __name__ == "__main__":
    main()
