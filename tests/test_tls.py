#!/usr/bin/env python3
"""Real TLS test-only servers/certificates; Python stdlib + OpenSSL + curl."""
import json
import os
from pathlib import Path
import ssl
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
ROOT = Path(__file__).resolve().parents[1]

class TLS(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='fmc-tls-test-', dir=os.environ.get('TMPDIR'))
        self.addCleanup(self.tmp.cleanup)
        self.p = Path(self.tmp.name)
        config = self.p/'test-only-openssl.cnf'
        config.write_text('[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=localhost\n[ext]\nsubjectAltName=DNS:localhost,IP:127.0.0.1\nbasicConstraints=critical,CA:TRUE\n')
        self.cert = self.p/'test-only-cert.pem'
        key = self.p/'test-only-key.pem'
        subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1',
                        '-keyout',str(key),'-out',str(self.cert),'-config',str(config)],
                       check=True, capture_output=True)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(self.cert,key)
        self.received = []
        self.target_received = []
        self.redirect = None
        owner = self
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args): pass
            def do_POST(self): self.respond()
            def do_GET(self): self.respond()
            def respond(self):
                # Never record raw Authorization, only whether it arrived.
                dest = owner.target_received if self.server.is_target else owner.received
                dest.append({'path':self.path,'auth':bool(self.headers.get('Authorization'))})
                if owner.redirect and not self.server.is_target:
                    self.send_response(302)
                    self.send_header('Location',owner.redirect)
                    self.send_header('Content-Length','0')
                    self.end_headers()
                    return
                body = json.dumps(dict(status='ok',total_checkins=1,
                                       first_seen='2026-10-11T00:00:00Z',last_seen='2026-10-11T00:00:00Z')).encode()
                self.send_response(200); self.send_header('Content-Length',str(len(body)))
                self.end_headers(); self.wfile.write(body)
        def server(tls, target):
            srv = ThreadingHTTPServer(('127.0.0.1',0),Handler)
            srv.is_target = target
            if tls: srv.socket = context.wrap_socket(srv.socket,server_side=True)
            threading.Thread(target=srv.serve_forever,daemon=True).start()
            self.addCleanup(srv.server_close); self.addCleanup(srv.shutdown)
            return srv
        self.source = server(True,False)
        self.http_target = server(False,True)
        self.https_target = server(True,True)
        self.env = dict(os.environ, HOME=str(self.p),TMPDIR=str(self.p),
                        XDG_CONFIG_HOME=str(self.p/'config'), XDG_DATA_HOME=str(self.p/'data'),
                        FMC_API=f'https://127.0.0.1:{self.source.server_port}/api',NO_COLOR='1')
        for name in ('CURL_CA_BUNDLE','SSL_CERT_FILE','SSL_CERT_DIR'):
            self.env.pop(name,None)
        # Deliberately malicious HOME config: CLI must ignore this file.
        (self.p/'.curlrc').write_text('insecure\nlocation\nlocation-trusted\n')
    def run_cli(self, command):
        return subprocess.run([str(ROOT/'founder-mode-coffee'),command,'--json'],
                              env=self.env,text=True,capture_output=True,timeout=20)
    def test_untrusted_selfsigned_rejected_despite_curlrc(self):
        result = self.run_cli('checkin')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('error',json.loads(result.stdout))
        self.assertEqual(self.received,[], 'untrusted server received application traffic')
    def test_authenticated_downgrade_and_crosshost_redirects(self):
        self.env['CURL_CA_BUNDLE'] = str(self.cert)
        # Prove the certificate is accepted when explicitly trusted by this test.
        self.assertEqual(self.run_cli('checkin').returncode,0)
        self.assertTrue(self.received[-1]['auth'])
        for target in (f'http://127.0.0.1:{self.http_target.server_port}/landing',
                       f'https://localhost:{self.https_target.server_port}/landing'):
            self.redirect = target
            for command in ('checkin','me','online','offline'):
                result = self.run_cli(command)
                self.assertNotEqual(result.returncode,0)
                self.assertIn('error',json.loads(result.stdout))
                token = (self.p/'config/founder-mode-coffee/identity').read_text().strip()
                self.assertNotIn(token,result.stdout+result.stderr)
                self.assertTrue(self.received[-1]['auth'])
        self.assertEqual(self.target_received,[], 'redirect destination received traffic/credential')
    def test_unauthenticated_https_cannot_downgrade(self):
        self.env['CURL_CA_BUNDLE'] = str(self.cert)
        self.redirect = f'http://127.0.0.1:{self.http_target.server_port}/landing'
        for command in ('ping','doctor'):
            self.assertNotEqual(self.run_cli(command).returncode,0)
        self.assertEqual(self.target_received,[])

if __name__=='__main__': unittest.main(verbosity=2)
