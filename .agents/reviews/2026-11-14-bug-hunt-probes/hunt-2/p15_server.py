# Loopback HTTP mock peer: serves files from a dir, in small delayed chunks; /nolen omits Content-Length; /short lies about it.
import http.server, sys, time, os
root = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        parts = self.path.strip('/').split('/')
        mode, name = parts[0], parts[1]
        p = os.path.join(root, name)
        if not os.path.exists(p):
            self.send_response(404); self.end_headers(); return
        b = open(p, 'rb').read()
        self.send_response(200)
        if mode == 'len': self.send_header('Content-Length', str(len(b)))
        if mode == 'short': self.send_header('Content-Length', str(len(b) + 50))
        self.end_headers()
        for i in range(0, len(b), 37):
            self.wfile.write(b[i:i+37]); self.wfile.flush(); time.sleep(0.002)
srv = http.server.HTTPServer(('127.0.0.1', 0), H)
print(srv.server_address[1], flush=True)
srv.serve_forever()
