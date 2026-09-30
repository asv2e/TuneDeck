#!/usr/bin/env python3
"""
TuneDeck stream resolver: a small companion server that uses yt-dlp to find playable audio.

  GET /health                 -> {"ok": true, "yt_dlp": "<version>"}
  GET /resolve?id=<videoId>   -> {"mode": "proxy"}                         (default; audio via /stream)
  GET /resolve?id=<id>&mode=direct
                              -> {"mode": "direct", "url": ..., "headers": {...}, "ttl": <seconds>}
  GET /stream?id=<videoId>    -> audio bytes, Range requests supported

Why proxy by default: YouTube stream URLs are bound to the IP address that resolved them. If the
phone and this server are on different networks (phone on cellular, server at home), a direct URL
returns 403. Proxying makes the server the only party talking to YouTube.

Environment:
  TUNEDECK_TOKEN   if set, every request must send "Authorization: Bearer <token>"
  HOST, PORT       bind address (default 0.0.0.0:8787)

Requires yt-dlp with a JavaScript runtime (Deno) for YouTube. See README.md.
"""
from __future__ import annotations

import hmac
import json
import os
import re
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

import yt_dlp
from yt_dlp.version import __version__ as YTDLP_VERSION

HOST = os.environ.get("HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "8787"))
TOKEN = os.environ.get("TUNEDECK_TOKEN", "").strip()
VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")

YDL_OPTS = {
    # AVPlayer can't decode Opus/WebM, so ask for AAC in an MP4 container first.
    "format": "bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/18/best[ext=mp4]",
    "quiet": True,
    "no_warnings": True,
    "noplaylist": True,
    "skip_download": True,
    "socket_timeout": 20,
}

_cache: dict[str, dict] = {}
_lock = threading.Lock()


def resolve(video_id: str) -> dict:
    """Return {"url", "user_agent", "expires"} for a video, cached until shortly before expiry."""
    now = time.time()
    with _lock:
        hit = _cache.get(video_id)
        if hit and hit["expires"] - now > 120:
            return hit

    with yt_dlp.YoutubeDL(YDL_OPTS) as ydl:
        info = ydl.extract_info(f"https://music.youtube.com/watch?v={video_id}", download=False)

    fmt = info
    if not info.get("url") and info.get("requested_formats"):
        fmt = info["requested_formats"][0]
    url = fmt.get("url")
    if not url:
        raise RuntimeError("yt-dlp returned no playable URL")

    headers = fmt.get("http_headers") or info.get("http_headers") or {}
    match = re.search(r"[?&]expire=(\d+)", url)
    entry = {
        "url": url,
        "user_agent": headers.get("User-Agent", "Mozilla/5.0"),
        "expires": float(match.group(1)) if match else now + 3600,
    }

    with _lock:
        for key in [k for k, v in _cache.items() if v["expires"] < now]:
            del _cache[key]
        _cache[video_id] = entry
    return entry


class Handler(BaseHTTPRequestHandler):
    server_version = "TuneDeckResolver/0.1"

    def _authorized(self) -> bool:
        if not TOKEN:
            return True
        supplied = self.headers.get("Authorization", "")
        return hmac.compare_digest(supplied, f"Bearer {TOKEN}")

    def _json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _proxy(self, entry: dict) -> None:
        request = urllib.request.Request(entry["url"], headers={"User-Agent": entry["user_agent"]})
        byte_range = self.headers.get("Range")
        if byte_range:
            request.add_header("Range", byte_range)
        try:
            with urllib.request.urlopen(request, timeout=20) as upstream:
                self.send_response(upstream.status)
                for name in ("Content-Type", "Content-Length", "Content-Range", "Accept-Ranges"):
                    value = upstream.headers.get(name)
                    if value:
                        self.send_header(name, value)
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                while chunk := upstream.read(64 * 1024):
                    self.wfile.write(chunk)
        except urllib.error.HTTPError as exc:
            self._json(exc.code, {"error": f"upstream returned {exc.code}"})
        except (BrokenPipeError, ConnectionResetError):
            pass  # the player closed the connection (seek, skip); nothing to report

    def do_GET(self) -> None:  # noqa: N802 (http.server naming)
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)

        if not self._authorized():
            return self._json(401, {"error": "unauthorized"})
        if parsed.path == "/health":
            return self._json(200, {"ok": True, "yt_dlp": YTDLP_VERSION})

        if parsed.path in ("/resolve", "/stream"):
            video_id = (query.get("id") or [""])[0]
            if not VIDEO_ID.match(video_id):
                return self._json(400, {"error": "invalid video id"})
            try:
                entry = resolve(video_id)
            except Exception as exc:  # yt-dlp raises many types; report and keep serving
                return self._json(502, {"error": str(exc)[:300]})

            if parsed.path == "/stream":
                return self._proxy(entry)

            if (query.get("mode") or ["proxy"])[0] == "direct":
                return self._json(200, {
                    "mode": "direct",
                    "url": entry["url"],
                    "headers": {"User-Agent": entry["user_agent"]},
                    "ttl": max(60, int(entry["expires"] - time.time())),
                })
            return self._json(200, {"mode": "proxy"})

        self._json(404, {"error": "not found"})


if __name__ == "__main__":
    auth = "on" if TOKEN else "OFF (set TUNEDECK_TOKEN before exposing this to the internet)"
    print(f"TuneDeck resolver listening on {HOST}:{PORT} | yt-dlp {YTDLP_VERSION} | auth {auth}", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
