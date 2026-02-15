#!/usr/bin/env python3
# Stream Hub docs admin (minimal, standard library only).
# - Edits MkDocs markdown files in-place
# - Optional: builds + deploys site into publish dir
#
# Security model:
# - Run on 127.0.0.1 only
# - Put nginx basic auth in front of /admin
# - For state-changing requests require header: X-Stream-Admin: 1
#
# Комментарии — на русском, потому что это админка для эксплуатации.

import argparse
import cgi
import json
import os
import re
import subprocess
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


def _json(handler, status, obj):
    data = json.dumps(obj, ensure_ascii=False, indent=2).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(data)))
    handler.end_headers()
    handler.wfile.write(data)


def _text(handler, status, text):
    data = (text or "").encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "text/plain; charset=utf-8")
    handler.send_header("Content-Length", str(len(data)))
    handler.end_headers()
    handler.wfile.write(data)


def _require_admin_header(handler):
    # Простой CSRF-барьер: браузер с другого сайта не сможет послать кастомный header без CORS-preflight.
    v = handler.headers.get("X-Stream-Admin")
    if v != "1":
        _text(handler, HTTPStatus.FORBIDDEN, "Missing X-Stream-Admin: 1")
        return False
    return True


def _safe_rel_path(p):
    # Разрешаем только относительные пути внутри docs/ и только с forward slashes.
    # Никаких ".." и абсолютных путей.
    if not p or not isinstance(p, str):
        return None
    p = p.strip().replace("\\", "/")
    if p.startswith("/"):
        return None
    parts = [x for x in p.split("/") if x]
    if not parts:
        return None
    if any(x == ".." for x in parts):
        return None
    return "/".join(parts)


def _walk_md_files(docs_dir):
    out = []
    for path in docs_dir.rglob("*.md"):
        rel = path.relative_to(docs_dir).as_posix()
        # Не даём редактировать саму админку отсюда (чтобы не выстрелить себе в ногу).
        if rel.startswith("admin/"):
            continue
        out.append(rel)
    out.sort()
    return out


def _sanitize_filename(name):
    # Разрешаем только безопасные символы. Остальное заменяем на "-".
    name = (name or "").strip()
    name = re.sub(r"[^A-Za-z0-9._-]+", "-", name)
    name = name.strip(".-")
    return name or None


class DocsAdmin:
    def __init__(self, repo_dir, docs_dir, mkdocs_yml, site_dir, publish_dir, mkdocs_python):
        self.repo_dir = Path(repo_dir).resolve()
        self.docs_dir = Path(docs_dir).resolve()
        self.mkdocs_yml = Path(mkdocs_yml).resolve()
        self.site_dir = Path(site_dir).resolve()
        self.publish_dir = Path(publish_dir).resolve() if publish_dir else None
        self.mkdocs_python = mkdocs_python

        if not self.docs_dir.is_dir():
            raise RuntimeError("docs_dir not found: %s" % self.docs_dir)

    def list_files(self):
        return _walk_md_files(self.docs_dir)

    def read_file(self, rel_path):
        rel = _safe_rel_path(rel_path)
        if not rel or not rel.endswith(".md"):
            raise ValueError("invalid path")
        full = (self.docs_dir / rel).resolve()
        if not str(full).startswith(str(self.docs_dir) + os.sep):
            raise ValueError("path escape")
        if not full.exists():
            raise FileNotFoundError(rel)
        return full.read_text(encoding="utf-8")

    def write_file(self, rel_path, content):
        rel = _safe_rel_path(rel_path)
        if not rel or not rel.endswith(".md"):
            raise ValueError("invalid path")
        full = (self.docs_dir / rel).resolve()
        if not str(full).startswith(str(self.docs_dir) + os.sep):
            raise ValueError("path escape")
        if not full.exists():
            raise FileNotFoundError(rel)
        if content is None:
            content = ""
        if len(content) > 2 * 1024 * 1024:
            raise ValueError("content too large")
        full.write_text(content, encoding="utf-8")

    def upload_asset(self, filename, data):
        if data is None:
            raise ValueError("empty upload")
        if len(data) > 10 * 1024 * 1024:
            raise ValueError("file too large")

        safe = _sanitize_filename(filename)
        if not safe:
            raise ValueError("bad filename")

        ext = safe.lower().rsplit(".", 1)[-1] if "." in safe else ""
        if ext not in ("png", "jpg", "jpeg", "webp", "svg"):
            raise ValueError("unsupported file type")

        up_dir = (self.docs_dir / "assets" / "uploads").resolve()
        up_dir.mkdir(parents=True, exist_ok=True)

        full = (up_dir / safe).resolve()
        if not str(full).startswith(str(up_dir) + os.sep):
            raise ValueError("path escape")

        full.write_bytes(data)
        return "/assets/uploads/%s" % safe

    def build_and_deploy(self):
        if not self.mkdocs_python:
            raise RuntimeError("mkdocs_python is not configured")

        t0 = time.time()
        cmd = [self.mkdocs_python, "-m", "mkdocs", "build", "-f", str(self.mkdocs_yml), "-d", str(self.site_dir), "--clean"]
        subprocess.run(cmd, cwd=str(self.repo_dir), check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        build_ms = int((time.time() - t0) * 1000)

        deploy_ms = 0
        if self.publish_dir:
            t1 = time.time()
            self.publish_dir.mkdir(parents=True, exist_ok=True)
            # Важно: в publish_dir лежат установщики/бинарники, их не трогаем.
            rsync = [
                "rsync",
                "-a",
                "--delete",
                "--exclude=install.sh",
                "--exclude=install-centos.sh",
                "--exclude=install-macos.sh",
                "--exclude=stream-macos-arm64",
                # Linux release artifacts (binary mode installer downloads these).
                "--exclude=stream-linux-*",
                str(self.site_dir) + "/",
                str(self.publish_dir) + "/",
            ]
            subprocess.run(rsync, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            deploy_ms = int((time.time() - t1) * 1000)

        return build_ms, deploy_ms


class Handler(BaseHTTPRequestHandler):
    admin = None

    def log_message(self, fmt, *args):
        # Без шумных access-логов, только ошибки/важное.
        return

    def _route(self):
        u = urlparse(self.path)
        return u.path, parse_qs(u.query or "")

    def do_GET(self):
        path, q = self._route()
        if path == "/api/health":
            return _json(self, HTTPStatus.OK, {"ok": True})

        if path == "/api/list":
            try:
                return _json(self, HTTPStatus.OK, {"files": self.admin.list_files()})
            except Exception as e:
                return _text(self, HTTPStatus.INTERNAL_SERVER_ERROR, str(e))

        if path == "/api/file":
            rel = (q.get("path") or [""])[0]
            try:
                content = self.admin.read_file(rel)
                return _json(self, HTTPStatus.OK, {"path": rel, "content": content})
            except FileNotFoundError:
                return _text(self, HTTPStatus.NOT_FOUND, "not found")
            except Exception as e:
                return _text(self, HTTPStatus.BAD_REQUEST, str(e))

        return _text(self, HTTPStatus.NOT_FOUND, "not found")

    def do_PUT(self):
        if not _require_admin_header(self):
            return

        path, q = self._route()
        if path != "/api/file":
            return _text(self, HTTPStatus.NOT_FOUND, "not found")

        rel = (q.get("path") or [""])[0]
        try:
            length = int(self.headers.get("content-length") or "0")
            if length <= 0 or length > 3 * 1024 * 1024:
                return _text(self, HTTPStatus.BAD_REQUEST, "bad content-length")
            raw = self.rfile.read(length)
            data = json.loads(raw.decode("utf-8"))
            content = data.get("content", "")
            self.admin.write_file(rel, content)
            return _json(self, HTTPStatus.OK, {"ok": True})
        except FileNotFoundError:
            return _text(self, HTTPStatus.NOT_FOUND, "not found")
        except Exception as e:
            return _text(self, HTTPStatus.BAD_REQUEST, str(e))

    def do_POST(self):
        if not _require_admin_header(self):
            return

        path, _ = self._route()

        if path == "/api/build":
            try:
                build_ms, deploy_ms = self.admin.build_and_deploy()
                return _json(self, HTTPStatus.OK, {"ok": True, "message": "Опубликовано", "build_ms": build_ms, "deploy_ms": deploy_ms})
            except subprocess.CalledProcessError as e:
                out = e.stdout.decode("utf-8", errors="replace") if e.stdout else str(e)
                return _text(self, HTTPStatus.INTERNAL_SERVER_ERROR, out)
            except Exception as e:
                return _text(self, HTTPStatus.INTERNAL_SERVER_ERROR, str(e))

        if path == "/api/upload":
            ctype, pdict = cgi.parse_header(self.headers.get("content-type") or "")
            if ctype != "multipart/form-data":
                return _text(self, HTTPStatus.BAD_REQUEST, "expected multipart/form-data")

            pdict["boundary"] = pdict.get("boundary", "").encode("utf-8")
            pdict["CONTENT-LENGTH"] = int(self.headers.get("content-length") or "0")
            form = cgi.FieldStorage(fp=self.rfile, headers=self.headers, environ={"REQUEST_METHOD": "POST"}, keep_blank_values=True)
            f = form["file"] if "file" in form else None
            if not f or not getattr(f, "filename", None):
                return _text(self, HTTPStatus.BAD_REQUEST, "missing file")
            data = f.file.read()
            try:
                url = self.admin.upload_asset(f.filename, data)
                return _json(self, HTTPStatus.OK, {"ok": True, "url": url})
            except Exception as e:
                return _text(self, HTTPStatus.BAD_REQUEST, str(e))

        return _text(self, HTTPStatus.NOT_FOUND, "not found")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bind", default=os.environ.get("STREAM_DOCS_BIND", "127.0.0.1"))
    ap.add_argument("--port", type=int, default=int(os.environ.get("STREAM_DOCS_PORT", "9377")))
    ap.add_argument("--repo", default=os.environ.get("STREAM_DOCS_REPO", "/home/hex/stream"))
    ap.add_argument("--docs-dir", default=os.environ.get("STREAM_DOCS_DOCS_DIR", "docs"))
    ap.add_argument("--mkdocs-yml", default=os.environ.get("STREAM_DOCS_MKDOCS_YML", "mkdocs.yml"))
    ap.add_argument("--site-dir", default=os.environ.get("STREAM_DOCS_SITE_DIR", "site"))
    ap.add_argument("--publish-dir", default=os.environ.get("STREAM_DOCS_PUBLISH_DIR", "/var/www/stream.centv.ru"))
    ap.add_argument("--mkdocs-python", default=os.environ.get("STREAM_DOCS_MKDOCS_PY", ""))
    args = ap.parse_args()

    repo = Path(args.repo).resolve()
    docs_dir = (repo / args.docs_dir).resolve()
    mkdocs_yml = (repo / args.mkdocs_yml).resolve()
    site_dir = (repo / args.site_dir).resolve()

    Handler.admin = DocsAdmin(
        repo_dir=repo,
        docs_dir=docs_dir,
        mkdocs_yml=mkdocs_yml,
        site_dir=site_dir,
        publish_dir=args.publish_dir,
        mkdocs_python=args.mkdocs_python,
    )

    httpd = ThreadingHTTPServer((args.bind, args.port), Handler)
    print("docs_admin_server listening on %s:%s" % (args.bind, args.port))
    httpd.serve_forever()


if __name__ == "__main__":
    main()
