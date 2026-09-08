#!/usr/bin/env python3
"""Read-only loopback endpoint. No upload, telemetry, commands or external traffic."""
import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def make_handler(schedule_path):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.headers.get('Host') not in (f'127.0.0.1:{self.server.server_port}',):
                self.send_error(403)
                return
            origin = self.headers.get('Origin', '')
            if origin and not origin.startswith('chrome-extension://'):
                self.send_error(403)
                return
            if self.path != '/schedule':
                self.send_error(404)
                return
            try:
                data = schedule_path.read_bytes()
                if len(data) > 262144:
                    raise ValueError('Schedule too large')
                value = json.loads(data)
                # Send only window IDs and timestamps, never task text or reports.
                data = json.dumps({'version': value['version'], 'windows': [
                    {k: w[k] for k in ('id', 'start', 'end')} for w in value['windows']
                ]}).encode()
            except (OSError, ValueError, KeyError, TypeError):
                self.send_error(503, 'Schedule unavailable')
                return
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, *_):
            pass

    return Handler


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=18764)
    args = parser.parse_args()
    path = Path(__file__).resolve().with_name('schedule.json')
    ThreadingHTTPServer(('127.0.0.1', args.port), make_handler(path)).serve_forever()
