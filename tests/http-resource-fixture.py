"""Loopback-only fixture for ordinary resource bytes; never executes requests."""
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        path = unquote(self.path)
        status = 200
        headers = {}
        if path == "/assets/binary.bin":
            body = bytes(range(256)) + b"\x00\xff\x80"
        elif path == "/assets/中文 空格.txt":
            body = b"\xef\xbb\xbf" + "中文资源\n第二行".encode("utf-8")
        elif path == "/assets/data.json":
            body = json.dumps({"name": "中文", "number": 42}, ensure_ascii=False).encode("utf-8")
        elif path == "/assets/README.md":
            body = "普通入口 HTTP 测试".encode("utf-8")
        elif path == "/assets/slow":
            time.sleep(3)
            body = b"slow"
        elif path == "/assets/redirect":
            status, body = 302, b"redirect"
            headers["Location"] = "/assets/binary.bin"
        else:
            status, body = 404, b"missing"
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        for key, value in headers.items():
            self.send_header(key, value)
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(sys.argv[1], "w", encoding="ascii") as port_file:
    port_file.write(str(server.server_address[1]))
server.serve_forever()
