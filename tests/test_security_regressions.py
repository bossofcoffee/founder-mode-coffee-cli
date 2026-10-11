#!/usr/bin/env python3
"""Test-only adversarial curl capture. Never logs bearer stdin."""
import json
import os
import pathlib
import subprocess
import tempfile
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
CLI = str(ROOT/'founder-mode-coffee')

class Security(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='fmc-security-', dir=os.environ.get('TMPDIR'))
        self.addCleanup(self.tmp.cleanup)
        self.p = pathlib.Path(self.tmp.name).resolve()
        (self.p/'bin').mkdir()
        self.log = self.p/'calls.jsonl'
        mock = self.p/'bin/curl'
        mock.write_text('''#!/usr/bin/env python3
import json,os,sys,pathlib,re
args=sys.argv[1:]; config=sys.stdin.read() if '--config' in args else ''
m=re.search(r'Bearer ([a-f0-9]{64})',config); token=m[1] if m else ''
with open(os.environ['MOCK_SEC_LOG'],'a') as f:
 f.write(json.dumps({'args':args,'has_auth':bool(token),'stdin_fields':['Authorization'] if token else []})+'\\n')
url=args[-1]; stamp='2026-10-10T00:00:00.000Z'
body={'status':'offline' if url.endswith('/offline') else 'ok','total_checkins':1,'first_seen':stamp,'last_seen':stamp}
if url.endswith('/network'):body={'status':'ok','online_users':1,'checked_in_users':1,'total_users':1,'total_checkins':1,'online_window_seconds':300,'timestamp':stamp}
if url.endswith('/ping'):body={'message':'pong','total_pings':1,'timestamp':stamp}
if 'api.github.com' in url:body={'tag_name':'v2.4.0'}
mode=os.environ.get('MOCK_HOSTILE',''); code='200'
if mode=='error':body={'error':token};code='401'
if mode=='status':body['status']=token
if mode=='timestamp':body['first_seen']=token;body['timestamp']='bad'
if mode=='extra':body['private']=token;body['command']='test-only secret'
if '--output' in args:
 pathlib.Path(args[args.index('--output')+1]).write_text(json.dumps(body));print(code,end='')
else:print(json.dumps(body))
''')
        mock.chmod(0o700)
        self.env = dict(os.environ, PATH=str(self.p/'bin')+os.pathsep+os.environ['PATH'],
                        HOME=str(self.p), TMPDIR=str(self.p), XDG_CONFIG_HOME=str(self.p/'config'),
                        XDG_DATA_HOME=str(self.p/'data'), MOCK_SEC_LOG=str(self.log), NO_COLOR='1',
                        FMC_API='https://example.com/api')
    def run_cli(self, *args):
        return subprocess.run([CLI, *args], env=self.env, text=True, capture_output=True, timeout=20)
    def test_http_rejected_before_traffic(self):
        for endpoint in ('http://example.com/api','http://localhost/api','http://127.1/api',
                         'http://127.0.0.2/api','http://[::ffff:127.0.0.1]/api'):
            self.env['FMC_API'] = endpoint
            for command in ('network','online','offline','checkin','me','ping','doctor'):
                result = self.run_cli(command,'--json')
                self.assertNotEqual(result.returncode,0,(endpoint,command))
                self.assertIn('error',json.loads(result.stdout))
        self.assertFalse(self.log.exists())
    def test_remote_flags_and_secret_channel(self):
        for command in ('network','checkin','me','offline','online','ping','doctor','update'):
            result = self.run_cli(command,'--json')
            self.assertEqual(result.returncode,0,result.stderr+result.stdout)
        token = (self.p/'config/founder-mode-coffee/identity').read_text().strip()
        for call in map(json.loads,self.log.read_text().splitlines()):
            args = call['args']
            self.assertEqual(args[0],'--disable')
            self.assertEqual(args[args.index('--proto')+1],'=https')
            self.assertEqual(args[args.index('--proto-redir')+1],'=https')
            self.assertIn('--tlsv1.2',args)
            for forbidden in ('--insecure','-k','--location-trusted'):self.assertNotIn(forbidden,args)
            self.assertNotIn(token,json.dumps(call))
            self.assertTrue(args[-1].startswith('https://'))
            if '/network/' in args[-1] and not args[-1].endswith('/health'):
                self.assertTrue(call['has_auth'])
                self.assertNotIn('--location',args)
        self.assertNotIn(token,result.stdout+result.stderr)
    def test_hostile_reflection_and_contract_filter(self):
        self.assertEqual(self.run_cli('checkin','--json').returncode,0)
        token = (self.p/'config/founder-mode-coffee/identity').read_text().strip()
        for mode in ('error','status','timestamp','extra'):
            self.env['MOCK_HOSTILE'] = mode
            for command in ('checkin','me','online','network'):
                result = self.run_cli(command,'--json')
                self.assertNotIn(token,result.stdout+result.stderr)
                body = json.loads(result.stdout)
                self.assertNotIn('private',body)
                self.assertNotIn('command',body)
                if mode!='extra':
                    self.assertNotEqual(result.returncode,0)
                    self.assertIn('error',body)
    def test_private_identity_guards(self):
        self.run_cli('checkin','--json')
        identity = self.p/'config/founder-mode-coffee/identity'
        for command in ('me','checkin','online','offline'):
            identity.chmod(0o644)
            self.assertNotEqual(self.run_cli(command,'--json').returncode,0)
            identity.chmod(0o600)
        target = self.p/'private-test-only'
        identity.rename(target); identity.symlink_to(target)
        self.assertNotEqual(self.run_cli('me','--json').returncode,0)
        identity.unlink(); os.link(target,identity)
        self.assertNotEqual(self.run_cli('me','--json').returncode,0)

if __name__=='__main__':unittest.main(verbosity=2)
