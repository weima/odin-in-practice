"""Loopback HTTP and CLI integration checks; standard-library-only Linux lab."""
from __future__ import annotations

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import ClassVar, cast
import json
import os
import shutil
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parent
HTTP = ROOT / '17-networking/http-client/.build/http-client'
BIN = ROOT / '21-capstone/.build'

class Fixture(BaseHTTPRequestHandler):
    redirect: ClassVar[bool] = False
    def log_message(self, format: str, *args: object) -> None:
        pass
    def do_GET(self) -> None:
        if self.path == '/slow':
            time.sleep(3)
        body = b'x' * 65_537 if self.path == '/oversize' else b'hello\n'
        code = 404 if self.path == '/missing' else 200
        if self.path == '/ok' and self.redirect:
            code = 302
        self.send_response(code)
        if code == 302:
            self.send_header('Location', '/missing')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass  # The deliberately timed-out client has already closed.

checks = 0

def run(command: list[str], *, data: bytes | None = None,
        env: dict[str, str] | None = None) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(command, input=data, capture_output=True, timeout=20, env=env, check=False)

def expect(result: subprocess.CompletedProcess[bytes], code: int,
           output: bytes | None = None) -> None:
    global checks
    assert result.returncode == code, (result.returncode, result.stderr)
    if output is not None:
        assert result.stdout == output, result.stdout
    checks += 1

def main() -> None:
    assert HTTP.is_file() and all((BIN / name).is_file() for name in ['inspect', 'select', 'summarize', 'run-pipeline']), 'Build the companions first'
    with tempfile.TemporaryDirectory(prefix='odin-systems-') as name:
        temporary = Path(name)
        environment = dict(os.environ)
        environment['http_proxy'] = 'http://127.0.0.1:1'
        environment['CURL_HOME'] = str(temporary)
        side_effect = temporary / 'unexpected-curl-output'
        (temporary / '.curlrc').write_text(f'output = "{side_effect}"\n')
        server = ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
        server.daemon_threads = True
        serving = threading.Thread(target=server.serve_forever, daemon=True)
        serving.start()
        try:
            command = [str(HTTP), str(server.server_port)]
            expect(run([*command, '/ok'], env=environment), 0, b'hello\n')
            assert not side_effect.exists(), 'curl config was not disabled'
            expect(run([*command, '/missing'], env=environment), 3, b'')
            expect(run([*command, '/oversize'], env=environment), 1, b'')
            expect(run([*command, '/slow'], env=environment), 1, b'')
            Fixture.redirect = True
            expect(run([*command, '/ok'], env=environment), 3, b'')
            expect(run([str(HTTP), 'not-a-port', '/ok']), 2, b'')
            expect(run([*command, '/not-allowed']), 2, b'')
        finally:
            server.shutdown()
            server.server_close()
            serving.join()
            Fixture.redirect = False

        small, large, empty = temporary / 'small file', temporary / 'line\nname', temporary / 'empty'
        small.write_bytes(b'abc')
        large.write_bytes('café'.encode('utf-8'))
        empty.write_bytes(b'')
        inspected = run([str(BIN / 'inspect'), '--', str(small), str(large), str(empty)])
        expect(inspected, 0)
        selected = run([str(BIN / 'select'), '4'], data=inspected.stdout)
        expect(selected, 0)
        summarized = run([str(BIN / 'summarize')], data=selected.stdout)
        expect(summarized, 0)
        assert cast(object, json.loads(summarized.stdout)) == {'files': 1, 'bytes': 5}
        composed = run([str(BIN / 'run-pipeline'), str(BIN), '4', str(small), str(large), str(empty)])
        expect(composed, 0)
        assert cast(object, json.loads(composed.stdout)) == {'files': 1, 'bytes': 5}
        expect(run([str(BIN / 'run-pipeline'), str(BIN), '0', str(small), str(temporary / 'missing')]), 1, b'')
        expect(run([str(BIN / 'run-pipeline'), str(temporary), '0', str(small)]), 1, b'')
        expect(run([str(BIN / 'summarize')], data=b'{"path":"a","bytes":"wrong"}\n'), 3, b'')
        expect(run([str(BIN / 'summarize')], data=b'x' * 65_537 + b'\n'), 1, b'')
        oversize = temporary / 'oversize'
        oversize.write_bytes(b'x' * 1_048_577)
        expect(run([str(BIN / 'inspect'), '--', str(oversize)]), 1, b'')
        expect(run([str(BIN / 'select'), 'bad']), 2, b'')

        # Exercise the parent's wait budget without introducing descendants.
        slow_bin = temporary / 'slow-bin'
        slow_bin.mkdir()
        for stage in ['select', 'summarize']:
            shutil.copy2(BIN / stage, slow_bin / stage)
        pid_file = temporary / 'slow.pid'
        slow = slow_bin / 'inspect'
        slow.write_text('#!/usr/bin/python3\nfrom pathlib import Path\nimport os,time\n'
                        f'Path({str(pid_file)!r}).write_text(str(os.getpid()))\ntime.sleep(30)\n')
        slow.chmod(0o700)
        expect(run([str(BIN / 'run-pipeline'), str(slow_bin), '0', str(small)]), 1, b'')
        pid = int(pid_file.read_text())
        assert not Path(f'/proc/{pid}').exists(), 'timed-out direct child was not reaped'
    print(f'{checks} loopback HTTP and CLI scenarios passed; no Docker daemon was used')

if __name__ == '__main__':
    main()
