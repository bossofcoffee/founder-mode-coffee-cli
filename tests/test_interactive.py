#!/usr/bin/env python3
"""Real readline PTYs and a local HTTP contract fixture; stdlib only."""
import json
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]
CLI = str(ROOT / 'founder-mode-coffee')
CLI_BASH = os.environ.get('CLI_BASH', '/bin/bash')


class Terminal:
    def __init__(self, env, args=('interactive',), ready=True):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.execve(CLI_BASH, [CLI_BASH, CLI, *args], env)
        self.output = b''
        self.closed = False
        if ready:
            try:
                self.until(b'fmc> ')
            except Exception:
                self.close()
                raise

    def drain(self, duration=.1):
        end = time.monotonic() + duration
        chunk = b''
        while time.monotonic() < end:
            ready, _, _ = select.select([self.fd], [], [], max(0, end-time.monotonic()))
            if ready:
                try:
                    data = os.read(self.fd, 65536)
                except OSError:
                    break
                if not data:
                    break
                chunk += data
        self.output += chunk
        return chunk

    def until(self, needle, timeout=6):
        data = b''
        end = time.monotonic() + timeout
        while needle not in data and time.monotonic() < end:
            data += self.drain(.05)
        if needle not in data:
            raise AssertionError(f'No {needle!r} in {data!r}; full={self.output!r}')
        return data

    def send(self, text):
        os.write(self.fd, text.encode() if isinstance(text, str) else text)

    def command(self, text):
        self.send(text + '\n')
        return self.until(b'fmc> ')

    def finish(self, text='quit\n', sig=None):
        if sig:
            os.kill(self.pid, sig)
        elif text is not None:
            self.send(text)
        end = time.monotonic() + 6
        while time.monotonic() < end:
            self.drain(.05)
            pid, status = os.waitpid(self.pid, os.WNOHANG)
            if pid:
                self.closed = True
                os.close(self.fd)
                return os.waitstatus_to_exitcode(status)
        raise AssertionError('session did not exit')

    def close(self):
        if not self.closed:
            os.kill(self.pid, signal.SIGKILL)
            os.waitpid(self.pid, 0)
            os.close(self.fd)
            self.closed = True


class UX(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='.ux-test-', dir=ROOT)
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.env = dict(os.environ, HOME=str(self.base), XDG_CONFIG_HOME=str(self.base/'config'),
                        XDG_DATA_HOME=str(self.base/'data'), TMPDIR=str(self.base), TERM='xterm',
                        INPUTRC='/dev/null')
        for key in ('NO_COLOR', 'FMC_FORCE_COLOR', 'FMC_FORCE_INTERACTIVE', 'FMC_API', 'FMC_AI_RUNNER'):
            self.env.pop(key, None)
        runner = self.base/'runner'
        runner.write_text('#!/bin/bash\ncat >> "$HOME/ai.log"\nprintf "AI RESPONSE\\n"\n')
        runner.chmod(0o700)
        self.env['FMC_AI_RUNNER'] = str(runner)

    def terminal(self, args=('interactive',)):
        term = Terminal(self.env, args)
        self.addCleanup(term.close)
        return term

    def test_bare_commands_and_ai_escape(self):
        term = self.terminal()
        self.assertIn(b'Captured #1: literal $(touch nope); text', term.command('capture literal $(touch nope); text'))
        self.assertIn(b'Focus set: Ship it', term.command('focus set Ship it'))
        self.assertIn(b'Ship it', term.command('focus show'))
        self.assertIn(b'capture TEXT', term.command('help'))
        self.assertIn(b'version', term.command('status'))
        self.assertIn(b'AI RESPONSE', term.command('unknown words'))
        self.assertIn(b'AI RESPONSE', term.command('ask help'))
        self.assertIn('Request:\nhelp', (self.base/'ai.log').read_text())
        self.assertFalse((ROOT/'nope').exists())
        self.assertEqual(term.finish(), 0)

    def test_readline_history_up_down_and_persistence(self):
        term = self.terminal()
        term.command('capture first')
        term.command('focus set second')
        term.send(b'\x1b[A\x1b[A\n')
        self.assertIn(b'Captured #2: first', term.until(b'fmc> '))
        term.send(b'\x1b[A\x1b[A\x1b[B\n')
        self.assertIn(b'Captured #3: first', term.until(b'fmc> '))
        self.assertEqual(term.finish(), 0)
        term = self.terminal()
        term.send(b'\x1b[A\x1b[A\n')  # skip persisted quit
        self.assertIn(b'Captured #4: first', term.until(b'fmc> '))
        term.finish()
        history = self.base/'data/founder-mode-coffee/.history/commands'
        self.assertEqual(history.stat().st_mode & 0o777, 0o600)
        self.assertNotIn('run_capture', history.read_text())
        self.assertFalse((self.base/'.bash_history').exists())


    def api(self):
        owner = self
        self.requests = []
        self.api_code = 200
        self.response_override = None
        self.delay_path = None
        self.delay_started = threading.Event()
        self.delay_release = threading.Event()
        self.addCleanup(self.delay_release.set)
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format, *args):
                pass

            def do_POST(self):
                self.respond()

            def do_GET(self):
                self.respond()

            def respond(self):
                owner.requests.append((self.command, self.path, self.headers.get('Authorization')))
                if self.path == owner.delay_path:
                    owner.delay_started.set()
                    owner.delay_release.wait(10)
                if self.path == '/api/network':
                    body = dict(status='ok', timestamp='2026-10-11T00:00:00Z', online_users=1,
                                checked_in_users=1, total_users=1, total_checkins=1, online_window_seconds=300)
                else:
                    body = dict(status='offline' if self.path.endswith('/offline') else 'ok',
                                total_checkins=1, first_seen='2026-10-11T00:00:00Z', last_seen='2026-10-11T00:00:00Z')
                if owner.response_override is not None:
                    body = owner.response_override
                if owner.api_code != 200:
                    body = {'error': 'fixture unavailable'}
                data = json.dumps(body).encode()
                self.send_response(owner.api_code)
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                try:
                    self.wfile.write(data)
                except (BrokenPipeError, ConnectionResetError):
                    pass
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        self.env['FMC_API'] = f'http://127.0.0.1:{server.server_port}/api'
        self.env['FMC_TEST_HEARTBEAT_SECONDS'] = '1'

    def run_cli(self, *args, input=None):
        return subprocess.run([CLI_BASH, CLI, *args], env=self.env, input=input,
                              text=True, capture_output=True, timeout=8)

    def test_network_refresh_json_and_failures(self):
        self.api()
        result = self.run_cli('network', '--json')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['online_users'], 1)
        self.assertEqual([r[:2] for r in self.requests], [('POST', '/api/network/presence'), ('GET', '/api/network')])
        token = (self.base/'config/founder-mode-coffee/identity').read_text().strip()
        self.assertEqual(len(token), 64)
        self.assertEqual(self.requests[0][2], 'Bearer ' + token)
        self.assertEqual((self.base/'config/founder-mode-coffee/identity').stat().st_mode & 0o777, 0o600)
        for code in (503, 429):
            self.api_code = code
            self.requests.clear()
            result = self.run_cli('network', '--json')
            self.assertEqual(result.returncode, 1)
            self.assertIn('error', json.loads(result.stdout))
            self.assertEqual(len(self.requests), 1)

    def test_online_quiet_worker_offline_and_prompt(self):
        self.api()
        term = self.terminal()
        self.assertFalse(self.requests, 'startup joined without permission')
        self.assertIn(b'\x1b[38;2;245;158;11m', term.output)
        output = term.command('online')
        self.assertIn(b'\x1b[38;2;34;197;94m', output)
        term.send('capture clean')
        term.drain(.2)  # readline echo is expected, heartbeat output is not
        self.assertEqual(term.drain(2.2), b'')
        self.assertGreaterEqual(len(self.requests), 3)
        term.send(' input\n')
        self.assertIn(b'Captured #1: clean input', term.until(b'fmc> '))
        output = term.command('offline')
        self.assertIn(b'\x1b[38;2;245;158;11m', output)
        self.assertEqual(self.requests[-1][:2], ('POST', '/api/network/offline'))
        count = len(self.requests)
        term.drain(1.3)
        self.assertEqual(len(self.requests), count)
        term.finish()


    def group_processes(self, pid):
        result = subprocess.check_output(['ps', '-eo', 'pid=,pgid=,args='], text=True)
        return [line for line in result.splitlines() if len(line.split()) >= 3 and line.split()[1] == str(pid)]

    def test_exit_cleanup_after_ai_for_eof_int_term_and_quit(self):
        self.api()
        for how, expected in [('quit', 0), ('eof', 0), ('int', 130), ('term', 143)]:
            with self.subTest(how=how):
                term = self.terminal()
                term.command('online')
                term.command('ask help')
                processes = self.group_processes(term.pid)
                self.assertGreaterEqual(len(processes), 3, processes)
                if how == 'term':
                    code = term.finish(sig=signal.SIGTERM)
                else:
                    code = term.finish({'quit': 'quit\n', 'eof': '\x04', 'int': '\x03'}[how])
                self.assertEqual(code, expected)
                self.assertEqual(self.requests[-1][:2], ('POST', '/api/network/offline'))
                self.assertFalse(self.group_processes(term.pid), 'orphan worker/curl/sleep')
                self.assertFalse(list(self.base.rglob('fmc-session.*')))
                self.assertFalse(list(self.base.rglob('fmc-presence.*')))
                self.assertFalse(list(self.base.rglob('fmc-private.*')))

    def test_inflight_ai_pid_only_signal_cleanup(self):
        self.api()
        runner = self.base/'blocking-runner'
        runner.write_text('#!/bin/bash\ncat > "$HOME/ai.log"\nprintf "%s\\n" "$$" > "$HOME/runner.pid"\nexec /usr/bin/yes > /dev/null\n')
        runner.chmod(0o700)
        self.env['FMC_AI_RUNNER'] = str(runner)
        for command in ('ask private request', 'unknown private request'):
            for sig, expected in ((signal.SIGTERM, 143), (signal.SIGINT, 130)):
                with self.subTest(command=command, signal=sig):
                    marker = self.base/'runner.pid'
                    marker.unlink(missing_ok=True)
                    term = self.terminal()
                    term.command('online')
                    term.send(command+'\n')
                    end = time.monotonic()+4
                    while not marker.exists() and time.monotonic() < end:
                        term.drain(.05)
                    self.assertTrue(marker.exists(), 'blocking local runner never started')
                    tracked = [int(line.split()[0]) for line in self.group_processes(term.pid)]
                    runner_pid = int(marker.read_text())
                    self.assertIn(runner_pid, tracked)
                    self.assertTrue(list(self.base.rglob('fmc-ai-prompt.*')))
                    try:
                        self.assertEqual(term.finish(sig=sig), expected)
                        self.assertEqual(self.requests[-1][:2], ('POST', '/api/network/offline'))
                        self.assertFalse(self.group_processes(term.pid), 'owned AI/worker children survived')
                        live = {int(line.split()[0]) for line in subprocess.check_output(['ps', '-eo', 'pid='], text=True).splitlines()}
                        self.assertFalse(live.intersection(tracked), 'tracked owned child survived')
                        for pattern in ('fmc-ai-prompt.*', 'fmc-session.*', 'fmc-presence.*', 'fmc-private.*'):
                            self.assertFalse(list(self.base.rglob(pattern)), pattern)
                    finally:
                        # Failed red runs must not leave the blocking fixture behind.
                        if not term.closed:
                            term.close()
                            for pid in tracked:
                                if pid != term.pid:
                                    try:
                                        os.kill(pid, signal.SIGKILL)
                                    except ProcessLookupError:
                                        pass

    def test_fresh_session_explicit_offline_existing_identity(self):
        self.api()
        for command in ('network', 'online'):
            with self.subTest(command=command):
                self.assertEqual(self.run_cli(command, '--json').returncode, 0)
                identity = self.base/'config/founder-mode-coffee/identity'
                before = identity.read_bytes()
                self.requests.clear()
                term = self.terminal()
                self.assertFalse(self.requests)
                term.finish()
                self.assertFalse(self.requests, 'local exit removed an unowned lease')
                self.env['NO_COLOR'] = '1'
                term = self.terminal()
                self.assertIn(b'Offline locally.', term.command('offline'))
                self.assertEqual([r[:2] for r in self.requests], [('POST', '/api/network/offline')])
                term.finish()
                self.assertEqual(len(self.requests), 1, 'exit repeated explicit removal')
                self.assertEqual(identity.read_bytes(), before)
                # Readline may emit terminal input-mode controls on macOS; NO_COLOR prohibits SGR styling, not line editing.
                self.assertNotRegex(term.output, rb'\x1b\[[0-9;]*m')
                self.env.pop('NO_COLOR')

    def test_offline_without_identity_stays_local(self):
        self.api()
        term = self.terminal()
        self.assertIn(b'Offline locally.', term.command('offline'))
        term.finish()
        self.assertFalse(self.requests)
        self.assertFalse((self.base/'config/founder-mode-coffee/identity').exists())
        result = self.run_cli('offline', '--json')
        self.assertEqual(result.returncode, 1)
        self.assertIn('error', json.loads(result.stdout))
        self.assertFalse(self.requests)
        self.assertFalse((self.base/'config/founder-mode-coffee/identity').exists())

    def test_outage_expiry_and_initial_failure(self):
        self.api()
        self.api_code = 503
        result = self.run_cli('online', input='')
        self.assertEqual(result.returncode, 1)
        term = self.terminal()
        output = term.command('online')
        self.assertIn(b'unavailable', output)
        self.assertNotIn(b'\x1b[38;2;34;197;94m', output)
        self.api_code = 200
        term.command('online')
        self.api_code = 503
        term.drain(1.5)
        session = next(self.base.rglob('fmc-session.*'))
        (session/'confirmed').write_text(str(int(time.time())-301)+'\n')
        output = term.command('status')
        self.assertIn(b'presence unavailable', output)
        self.assertNotIn(b'\x1b[38;2;34;197;94m', output)
        term.finish()
        self.assertFalse(self.group_processes(term.pid))

    def test_standalone_online_json_no_color_and_network_once(self):
        self.api()
        result = self.run_cli('online', '--json')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(set(json.loads(result.stdout)), {'status', 'total_checkins', 'first_seen', 'last_seen'})
        self.assertEqual(len(self.requests), 1)
        term = self.terminal(('online',))
        self.assertIn(b'\x1b[38;2;34;197;94m', term.output)
        term.finish()
        for args in [('interactive',), ('--no-color', 'interactive')]:
            if args == ('interactive',):
                self.env['NO_COLOR'] = '1'
            term = self.terminal(args)
            term.command('online')
            term.command('clear')
            term.command('offline')
            term.finish()
            # Readline may emit terminal input-mode controls on macOS; NO_COLOR prohibits SGR styling, not line editing.
            self.assertNotRegex(term.output, rb'\x1b\[[0-9;]*m')
            self.env.pop('NO_COLOR', None)
        term = self.terminal()
        self.requests.clear()
        self.assertIn(b'FMC NETWORK', term.command('network'))
        self.assertEqual([r[:2] for r in self.requests], [('POST', '/api/network/presence'), ('GET', '/api/network')])
        term.drain(1.3)
        self.assertEqual(len(self.requests), 2)
        output = term.command('network --json')
        self.assertIn(b'"online_users": 1', output)
        self.assertNotIn(b'YOUR FMC CONNECTION', output)
        term.finish()

    def test_history_unsafe_paths_and_permissions(self):
        for unsafe in ('symlink-file', 'symlink-parent', 'mode', 'hardlink', 'directory'):
            with self.subTest(unsafe=unsafe):
                data = self.base/unsafe
                history_dir = data/'founder-mode-coffee/.history'
                history_dir.mkdir(parents=True, mode=0o700)
                history = history_dir/'commands'
                target = self.base/(unsafe+'-target')
                target.write_text('untouched\n')
                target.chmod(0o600)
                if unsafe == 'symlink-file':
                    history.symlink_to(target)
                elif unsafe == 'symlink-parent':
                    history_dir.rmdir()
                    history_dir.symlink_to(self.base, target_is_directory=True)
                elif unsafe == 'mode':
                    history.write_text('untouched\n')
                    history.chmod(0o644)
                elif unsafe == 'hardlink':
                    os.link(target, history)
                else:
                    history.mkdir()
                self.env['XDG_DATA_HOME'] = str(data)
                term = Terminal(self.env, ready=False)
                self.addCleanup(term.close)
                self.assertIn(b'unsafe history', term.until(b'unsafe history'))
                self.assertEqual(term.finish(None), 1)
                self.assertEqual(target.read_text(), 'untouched\n')

    def test_inflight_network_and_heartbeat_signal_cleanup(self):
        self.api()
        for command in ('online', 'network', 'checkin', 'heartbeat'):
            for sig in ('ctrl-c', 'term'):
                with self.subTest(command=command, signal=sig):
                    self.delay_path = None
                    term = self.terminal()
                    if command == 'heartbeat':
                        term.command('online')
                    self.delay_started.clear()
                    self.delay_release.clear()
                    self.delay_path = '/api/network/checkin' if command == 'checkin' else '/api/network/presence'
                    if command != 'heartbeat':
                        term.send(command+'\n')
                    self.assertTrue(self.delay_started.wait(4), 'delayed fixture was not reached')
                    tracked = [int(line.split()[0]) for line in self.group_processes(term.pid)]
                    self.assertGreaterEqual(len(tracked), 3)
                    if sig == 'ctrl-c':
                        code = term.finish('\x03')
                    else:
                        code = term.finish(sig=signal.SIGTERM)
                    self.assertEqual(code, 130 if sig == 'ctrl-c' else 143)
                    self.delay_release.set()
                    self.assertFalse(self.group_processes(term.pid), 'orphan worker/curl/sleep')
                    live = {int(line.split()[0]) for line in subprocess.check_output(['ps','-eo','pid='],text=True).splitlines()}
                    self.assertFalse(live.intersection(tracked), 'tracked child survived session exit')
                    self.assertFalse(list(self.base.rglob('fmc-private.*')))
                    self.assertFalse(list(self.base.rglob('fmc-presence.*')))
                    self.assertTrue(os.kill(os.getpid(), 0) is None, 'test parent must survive')

    def test_no_history_keeps_session_recall(self):
        self.env['FMC_NO_HISTORY'] = '1'
        term = self.terminal()
        term.command('capture session-only')
        term.send(b'\x1b[A\n')
        self.assertIn(b'Captured #2: session-only', term.until(b'fmc> '))
        term.finish()
        self.assertFalse(list(self.base.rglob('commands')))
        self.assertFalse((self.base/'.bash_history').exists())

    def test_invalid_contract_and_test_interval(self):
        self.api()
        for body in ({}, {'status': 'ok', 'total_checkins': 0, 'first_seen': 'bad', 'last_seen': 'bad'},
                     {'status': 'offline', 'total_checkins': 1, 'first_seen': '2026-10-11T00:00:00Z', 'last_seen': '2026-10-11T00:00:00Z'}):
            self.response_override = body
            result = self.run_cli('network', '--json')
            self.assertEqual(result.returncode, 1)
            self.assertIn('error', json.loads(result.stdout))
        for interval in ('0', '61', '-1', '1; touch nope', '01'):
            self.env['FMC_TEST_HEARTBEAT_SECONDS'] = interval
            result = self.run_cli('interactive', input='quit\n')
            self.assertEqual(result.returncode, 2, result)


if __name__ == '__main__':
    unittest.main(verbosity=2)
