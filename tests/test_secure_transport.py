#!/usr/bin/env python3
import json,os,pathlib,subprocess,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='fmc-security-',dir=os.environ.get('TMPDIR')) as tmp:
 p=pathlib.Path(tmp).resolve();(p/'bin').mkdir();log=p/'calls.jsonl'
 mock=p/'bin'/'curl'
 mock.write_text('''#!/usr/bin/env python3
import json,os,sys,pathlib
args=sys.argv[1:]; auth=sys.stdin.read() if '--config' in args else ''
with open(os.environ['MOCK_SEC_LOG'],'a') as f:f.write(json.dumps({'args':args,'has_auth':'Authorization: Bearer ' in auth})+'\\n')
url=args[-1]
body={'status':'ok','total_checkins':1,'first_seen':'2026-10-10T00:00:00.000Z','last_seen':'2026-10-10T00:00:00.000Z'}
if url.endswith('/network'):body={'status':'ok','online_users':1,'checked_in_users':1,'total_users':1,'total_checkins':1,'online_window_seconds':300,'timestamp':'2026-10-10T00:00:00.000Z'}
if '--output' in args:
 pathlib.Path(args[args.index('--output')+1]).write_text(json.dumps(body));print('200',end='')
else:print(json.dumps(body))
''');mock.chmod(0o755)
 env={**os.environ,'PATH':str(p/'bin')+os.pathsep+os.environ['PATH'],'XDG_CONFIG_HOME':str(p/'config'),'XDG_DATA_HOME':str(p/'data'),'MOCK_SEC_LOG':str(log),'NO_COLOR':'1','FMC_API':'http://example.com/api'}
 result=subprocess.run([str(ROOT/'founder-mode-coffee'),'network','--json'],env=env,text=True,capture_output=True,timeout=30)
 assert result.returncode!=0,'Off-machine HTTP must be rejected'
 assert not log.exists() or not log.read_text(),'No credential or API call may use off-machine HTTP'
 env['FMC_API']='https://example.com/api'
 result=subprocess.run([str(ROOT/'founder-mode-coffee'),'network','--json'],env=env,text=True,capture_output=True,timeout=30)
 assert result.returncode==0,result.stdout+result.stderr
 calls=[json.loads(x) for x in log.read_text().splitlines()]
 for c in calls:
  a=c['args'];assert a[0]=='--disable','Ignore potentially insecure ~/.curlrc'
  assert '--proto' in a and a[a.index('--proto')+1]=='=https','HTTPS-only transport'
  assert '--proto-redir' in a and a[a.index('--proto-redir')+1]=='=https','No downgrade redirect'
  assert '--tlsv1.2' in a and '--insecure' not in a and '-k' not in a
 identity=(p/'config'/'founder-mode-coffee'/'identity').read_text().strip()
 assert all(identity not in json.dumps(c['args']) for c in calls)
 assert identity not in result.stdout+result.stderr
 print('PASS: remote HTTP blocked before traffic, curlrc disabled, verified HTTPS and no downgrade, bearer absent from argv/output')
