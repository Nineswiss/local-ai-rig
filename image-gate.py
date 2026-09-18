#!/usr/bin/env python3
"""image-gate.py
A tiny standalone page that answers one question: is it safe to fire up
ComfyUI right now, or is Ollama still holding the GPU? qwen2.5:14b alone
uses ~10GB of a 12GB card - running that and a FLUX-class model at the
same time doesn't really work. Rather than forking Open WebUI's frontend
to add a real "Image" section (a much bigger commitment - hand-rebuilding
on every Open WebUI update), this is a separate zero-dependency page: it
polls Ollama's own /api/ps to see what's loaded, shows a waiting message
while something is, and links out to ComfyUI once the GPU is actually
free. ComfyUI Desktop is a normal GUI app - open it yourself as usual
once this says it's clear.

Stdlib only, nothing to install. Safe to leave running - it's a handful
of KB of RAM and does nothing when nobody's looking at the page.

Usage:
  python image-gate.py [port]          # defaults to 8189
  python image-gate.py --ollama-host adampc.local:11434
  python image-gate.py --comfyui-port 8188
"""
from __future__ import annotations

import argparse
import json
import urllib.error
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PAGE = """<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Image Gate</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root { color-scheme: dark; }
  body {
    background: #0f0f10; color: #e8e8e8; font-family: system-ui, sans-serif;
    display: flex; align-items: center; justify-content: center;
    height: 100vh; margin: 0; text-align: center;
  }
  .card { max-width: 420px; padding: 2rem; }
  .status { font-size: 1.25rem; margin-bottom: 1rem; }
  .detail { color: #999; font-size: 0.9rem; margin-bottom: 1.5rem; }
  .dot {
    display: inline-block; width: 10px; height: 10px; border-radius: 50%;
    margin-right: 8px; vertical-align: middle;
  }
  .dot.busy { background: #e0a030; animation: pulse 1.2s infinite; }
  .dot.free { background: #3fb950; }
  .dot.unknown { background: #666; }
  @keyframes pulse { 0%,100% { opacity: 1; } 50% { opacity: 0.35; } }
  a.open {
    display: inline-block; padding: 0.7rem 1.4rem; border-radius: 8px;
    background: #3fb950; color: #04220c; text-decoration: none;
    font-weight: 600; opacity: 0; pointer-events: none; transition: opacity 0.2s;
  }
  a.open.ready { opacity: 1; pointer-events: auto; }
</style>
</head>
<body>
  <div class="card">
    <div class="status"><span id="dot" class="dot unknown"></span><span id="text">Checking...</span></div>
    <div class="detail" id="detail"></div>
    <a class="open" id="link" href="#" target="_blank">Open ComfyUI &rarr;</a>
  </div>
<script>
// Point at ComfyUI on whatever host actually served this page (localhost,
// the PC's .local hostname, or its LAN IP) rather than a baked-in address -
// that way it works the same whether you're at the PC or on another device.
document.getElementById('link').href = `http://${location.hostname}:__COMFYUI_PORT__/`;

async function poll() {
  const dot = document.getElementById('dot');
  const text = document.getElementById('text');
  const detail = document.getElementById('detail');
  const link = document.getElementById('link');
  try {
    const r = await fetch('/status');
    const s = await r.json();
    if (s.loaded) {
      dot.className = 'dot busy';
      text.textContent = 'Waiting for the GPU to free up';
      detail.textContent = s.model
        ? `${s.model} is loaded (~${s.vram_gb} GB VRAM) - Ollama unloads it automatically after a few idle minutes.`
        : 'A model is currently loaded.';
      link.classList.remove('ready');
    } else {
      dot.className = 'dot free';
      text.textContent = 'GPU is free';
      detail.textContent = 'Safe to open ComfyUI now (launch it as usual if it isn\\'t already running).';
      link.classList.add('ready');
    }
  } catch (e) {
    dot.className = 'dot unknown';
    text.textContent = 'Can\\'t reach Ollama';
    detail.textContent = 'Check the PC is on and check-connection.sh from the client.';
    link.classList.remove('ready');
  }
}
poll();
setInterval(poll, 4000);
</script>
</body>
</html>
"""


def make_handler(ollama_host: str, comfyui_port: int):
    page = PAGE.replace("__COMFYUI_PORT__", str(comfyui_port))

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            pass  # keep the console quiet

        def do_GET(self):
            if self.path == "/status":
                self._serve_status()
            else:
                self._serve_page()

        def _serve_page(self):
            body = page.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _serve_status(self):
            result = {"loaded": False, "model": None, "vram_gb": None}
            try:
                req = urllib.request.Request(f"http://{ollama_host}/api/ps")
                with urllib.request.urlopen(req, timeout=4) as resp:
                    data = json.loads(resp.read().decode("utf-8"))
                models = data.get("models", [])
                if models:
                    m = models[0]
                    result["loaded"] = True
                    result["model"] = m.get("name") or m.get("model")
                    vram = m.get("size_vram")
                    if vram:
                        result["vram_gb"] = round(vram / (1024**3), 1)
            except (urllib.error.URLError, TimeoutError, OSError, ValueError):
                # Ollama unreachable/down - no LLM can be holding VRAM either way.
                pass

            body = json.dumps(result).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("port", nargs="?", type=int, default=8189)
    parser.add_argument("--ollama-host", default="127.0.0.1:11434")
    parser.add_argument("--comfyui-port", type=int, default=8188)
    parser.add_argument("--no-browser", action="store_true", help="don't auto-open a browser tab")
    args = parser.parse_args()

    handler = make_handler(args.ollama_host, args.comfyui_port)
    server = ThreadingHTTPServer(("0.0.0.0", args.port), handler)
    print(f"Image gate running on http://0.0.0.0:{args.port}")
    print(f"Checking Ollama at {args.ollama_host}, ComfyUI expected on port {args.comfyui_port}")
    if not args.no_browser:
        webbrowser.open(f"http://127.0.0.1:{args.port}/")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
