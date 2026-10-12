#!/usr/bin/env python3
"""Disposable local Gitea API stub for live-validation of fm-pr-check arming.

Serves exactly what the real `tea` CLI touches for this scenario:
  GET /api/v1/user                            (tea login add)
  GET /api/v1/repos/{owner}/{repo}/pulls/{n}  (tea api pull record)

Pull merged state is read fresh from the file named by FM_LAB_PR_STATE on
every request: "open" -> merged=false, "merged" -> merged=true.
Every request line is appended to the log named by FM_LAB_HTTP_LOG.
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse

STATE_FILE = os.environ["FM_LAB_PR_STATE"]
LOG_FILE = os.environ.get("FM_LAB_HTTP_LOG", "/dev/null")


def pr_state():
    try:
        with open(STATE_FILE) as fh:
            return fh.read().strip()
    except OSError:
        return "open"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        with open(LOG_FILE, "a") as fh:
            fh.write((fmt % args) + "\n")

    def _send(self, obj):
        body = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        with open(LOG_FILE, "a") as fh:
            fh.write("GET %s\n" % path)
        if path == "/api/v1/user":
            self._send({"login": "fmlab", "id": 1, "full_name": "FM Lab"})
            return
        if path == "/api/v1/repos/fmlab/fixture-repo/pulls/7":
            merged = pr_state() == "merged"
            self._send({
                "state": "merged" if merged else "open",
                "merged": merged,
                "head": {"sha": "0123456789abcdef0123456789abcdef01234567"
                                 if not merged else
                                 "89abcdef0123456789abcdef0123456789abcdef"},
            })
            return
        self.send_response(404)
        body = b'{"message":"Not Found"}'
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    port = int(sys.argv[1])
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()
