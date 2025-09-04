#!/usr/bin/env bash
set -Eeuo pipefail

# Simple local server with live reload
# Usage: ./serve.sh [port]

PORT="${1:-8000}"

# Serve from the script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo
echo "Serving '$PWD' at http://localhost:${PORT} (live reload)"
echo "Press Ctrl+C to stop"
echo

PYTHON=""
if command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON=python
else
  echo "ERROR: Python is required but was not found on PATH." >&2
  echo "Install Python: https://www.python.org/downloads/" >&2
  exit 1
fi

"$PYTHON" - <<'PY'
import io
import os
import sys
import time
import threading
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

PORT = int(os.environ.get('PORT', '8000'))
ROOT = os.getcwd()

# Change detection state
version = 0
cond = threading.Condition()

def snapshot(root):
    data = {}
    for base, dirs, files in os.walk(root):
        # Skip common hidden dirs
        dirs[:] = [d for d in dirs if not d.startswith('.') and d not in ('node_modules', '.git', '.venv')]
        for name in files:
            path = os.path.join(base, name)
            try:
                st = os.stat(path)
            except OSError:
                continue
            data[path] = st.st_mtime_ns
    return data

def watcher():
    global version
    last = snapshot(ROOT)
    while True:
        time.sleep(0.5)
        cur = snapshot(ROOT)
        if cur != last:
            last = cur
            with cond:
                version += 1
                cond.notify_all()

SNIPPET = (
    "\n<script>\n"
    "(function(){\n"
    "  try {\n"
    "    var es = new EventSource('/_livereload');\n"
    "    es.onmessage = function(){ try { location.reload(); } catch(e){} };\n"
    "    es.onerror = function(){ /* retry handled by browser */ };\n"
    "    console.log('[serve] live reload connected');\n"
    "  } catch (e) { console.warn('[serve] live reload unavailable:', e); }\n"
    "})();\n"
    "</script>\n"
)

class LiveReloadHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        # Prevent caching to ensure reloads fetch fresh content
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()

    def do_GET(self):
        if self.path.startswith('/_livereload'):
            return self.handle_sse()
        return super().do_GET()

    def handle_sse(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Connection', 'keep-alive')
        self.end_headers()
        # Initial comment to open stream
        try:
            self.wfile.write(b': connected\n\n')
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            return
        local = None
        try:
            while True:
                with cond:
                    current = version
                    if local is None:
                        local = current
                    cond.wait(timeout=30)
                    changed = (version != local)
                if changed:
                    try:
                        self.wfile.write(b'data: reload\n\n')
                        self.wfile.flush()
                    except (BrokenPipeError, ConnectionResetError):
                        return
                    return  # browser will reload, closing connection
                else:
                    # keep-alive ping
                    try:
                        self.wfile.write(b': ping\n\n')
                        self.wfile.flush()
                    except (BrokenPipeError, ConnectionResetError):
                        return
        except Exception:
            return

    def send_head(self):
        # Intercept HTML to inject the live reload snippet
        path = self.translate_path(self.path)
        if os.path.isdir(path):
            # Delegate to default directory listing / index logic
            return super().send_head()
        ctype = self.guess_type(path)
        if ctype.startswith('text/html'):
            try:
                with open(path, 'rb') as f:
                    raw = f.read()
            except OSError:
                self.send_error(404, 'File not found')
                return None
            try:
                text = raw.decode('utf-8')
            except UnicodeDecodeError:
                text = raw.decode('utf-8', 'ignore')
            lower = text.lower()
            idx = lower.rfind('</body>')
            if idx == -1:
                idx = lower.rfind('</head>')
            if idx == -1:
                injected = text + SNIPPET
            else:
                injected = text[:idx] + SNIPPET + text[idx:]
            out = injected.encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(out)))
            try:
                self.send_header('Last-Modified', self.date_time_string(os.path.getmtime(path)))
            except Exception:
                pass
            self.end_headers()
            return io.BytesIO(out)
        # Non-HTML: default behavior
        return super().send_head()


def main():
    t = threading.Thread(target=watcher, daemon=True)
    t.start()
    server = ThreadingHTTPServer(('', PORT), LiveReloadHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    # PORT is passed via env from the shell wrapper
    PORT = int(os.environ.get('PORT', '8000'))
    print(f"Serving {ROOT} at http://localhost:{PORT} (live reload)...")
    main()
PY

