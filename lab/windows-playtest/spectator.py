#!/usr/bin/env python3
"""Read-only game-window-only spectator for an interactive Windows OpenLRR test.

Attaches to an explicit PID. Never captures a desktop, enters inputs, stores
frames, or exposes arbitrary files. Bind is fixed to loopback; an authenticated
tunnel must be configured separately before sharing it.
"""
from __future__ import annotations
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from io import BytesIO
import re
import sys
from urllib.parse import urlsplit

VIEWER = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>OpenLRR — live spectator</title>
<style>
:root { color-scheme:dark; font:16px system-ui,sans-serif; background:#101720; color:#eaf0f8 }
body { margin:0; display:flex; justify-content:center; min-height:100vh }
main { width:min(1100px,98vw); padding:20px 0 }
h1 { margin:0 0 8px; font-size:22px } #status { margin:0 0 12px; color:#acbacd }
#frame { max-width:100%; height:auto; object-fit:contain; display:block; background:#07090c; border:1px solid #455367; aspect-ratio:4/3; margin:auto }
small { color:#96a4b5; display:block; margin-top:14px }
</style></head><body><main><h1>OpenLRR — Windows game spectator</h1>
<p id="status" role="status">Connecting to the game window…</p>
<img id="frame" alt="Live captured pixels from the original Windows game window only">
<small>Read-only. No mouse or keyboard controls. Frames are sampled for research, not a 60 FPS stream.</small>
<script>
const frame=document.getElementById('frame'), status=document.getElementById('status');
let count=0, failures=0;
async function poll(){
 try{
  const res=await fetch('/frame.jpg?v='+Date.now(),{cache:'no-store'});
  if(!res.ok)throw new Error('Game window unavailable ('+res.status+')');
  const blob=await res.blob(); const url=URL.createObjectURL(blob);
  frame.onload=()=>URL.revokeObjectURL(url);
  frame.src=url; failures=0; count++; status.textContent='Game window connected · '+count+' frames received';
 }catch(e){ failures++; status.textContent=e.message+' · retrying'; }
 setTimeout(poll,failures?1500:500);
}
poll();
</script></main></body></html>'''


class WindowsGameFrameSource:
    """Never use ImageGrab without its explicit window= target."""
    def __init__(self, pid: int, title: str):
        from playtest import Win32
        self.pid, self.pattern, self.win = pid, title, Win32()
        re.compile(title)

    def jpeg(self) -> bytes:
        from PIL import ImageGrab
        wins = self.win.windows(self.pid, self.pattern)
        if len(wins) != 1:
            raise RuntimeError('Expected exactly one target window owned by test PID')
        hwnd, _ = wins[0]
        self.win.ensure_window(hwnd, self.pid)
        image = ImageGrab.grab(window=int(hwnd))
        self.win.ensure_window(hwnd, self.pid)
        if image.width < 16 or image.height < 16:
            raise RuntimeError('Window capture invalid')
        stream = BytesIO()
        image.convert('RGB').save(stream, format='JPEG', quality=77)
        return stream.getvalue()


def make_handler(source):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            path = urlsplit(self.path).path
            if path == '/':
                self.reply(200, 'text/html; charset=utf-8', VIEWER.encode())
            elif path == '/frame.jpg':
                try:
                    frame = source.jpeg()
                except Exception:
                    # No stack traces, paths or window titles go to viewers.
                    self.reply(503, 'application/json', b'{"status":"game-window-unavailable"}')
                    return
                self.reply(200, 'image/jpeg', frame)
            elif path == '/health':
                self.reply(200, 'application/json', b'{"status":"spectator-running"}')
            else:
                self.reply(404, 'text/plain', b'Not found')

        def reply(self, code, mime, body):
            self.send_response(code)
            self.send_header('Content-Type', mime)
            self.send_header('Cache-Control', 'no-store, max-age=0')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('X-Frame-Options', 'DENY')
            self.send_header('Content-Security-Policy', "default-src 'none'; img-src 'self' blob:; script-src 'unsafe-inline'; style-src 'unsafe-inline'; base-uri 'none'")
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt, *args):
            pass
    return Handler


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid', type=int, required=True, help='Exact game PID')
    parser.add_argument('--title', default='Rock Raiders|OpenLRR')
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args(argv)
    if not 1 <= args.pid <= 2**31 - 1 or not 1024 <= args.port <= 65535:
        parser.error('Invalid PID or port')
    if sys.platform != 'win32':
        parser.error('Requires an interactive Windows desktop')
    source = WindowsGameFrameSource(args.pid, args.title)
    httpd = ThreadingHTTPServer(('127.0.0.1', args.port), make_handler(source))
    print(f'SPECTATOR_READY http://127.0.0.1:{args.port}', flush=True)
    try:
        httpd.serve_forever(poll_interval=.2)
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


if __name__ == '__main__':
    main()
