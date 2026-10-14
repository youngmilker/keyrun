import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

root = Path(sys.argv[1])
allowed = {"ps1", "resource-loader.ps1", "keyrun.ps1", "scripts/install.ps1", "scripts/diagnose-idea-paths.ps1"}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        relative = self.path.lstrip("/")
        if relative not in allowed:
            self.send_error(404)
            return
        body = (root / relative).read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
Path(sys.argv[2]).write_text(str(server.server_address[1]), encoding="ascii")
server.serve_forever()
