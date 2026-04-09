#!/usr/bin/env python3
"""Simple static server with no-cache headers.

Use this for local validation to avoid stale browser/service-worker behavior
when testing Flutter web builds.
"""

from __future__ import annotations

import argparse
import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class NoCacheHandler(SimpleHTTPRequestHandler):
    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Serve static files with no-cache headers")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--directory", default=".")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    handler = functools.partial(NoCacheHandler, directory=args.directory)
    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"Serving {args.directory} on http://{args.host}:{args.port} (no-cache)")
    server.serve_forever()


if __name__ == "__main__":
    main()
