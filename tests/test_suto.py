"""Offline regression tests: no target requests, installations, or browser launches."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'suto.sh'
STUB = r'''#!/usr/bin/python3
import os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
empty = os.environ.get('SUTO_EMPTY') == '1'
if name in ('assetfinder', 'subfinder'):
    if not empty:
        print('my-app.example.com\nother.example.com\nMY-APP.EXAMPLE.COM\nevil-example.com\nappXexample.com')
elif name == 'curl':
    print('[]')
elif name == 'jq':
    sys.stdin.read()
elif name == 'httpx':
    if '-h' in args:
        print('-ports -no-fallback')
    else:
        assert args[args.index('-ports') + 1] == os.environ.get('EXPECTED_PORTS', '80,443')
        assert '-follow-redirects' not in args
        if os.environ.get('SUTO_HTTP_FAIL'):
            print('probe failed', file=sys.stderr)
            sys.exit(2)
        output = '' if empty else 'https://my-app.example.com:8443 [404]\nhttp://my-app.example.com:8080 [200]\n'
        Path(args[args.index('-o') + 1]).write_text(output)
elif name == 'dig':
    if args[-1] == 'my-app.example.com':
        print('my-project.herokuapp.com.')
    elif args[-1] == 'other.example.com':
        print('notgithub.io.')
elif name == 'parallel':
    import subprocess
    command = args[-1]
    for line in sys.stdin:
        result = subprocess.run(command.replace('{}', line.strip()), shell=True)
        if result.returncode:
            sys.exit(result.returncode)
elif name == 'subjack':
    hosts = Path(args[args.index('-w') + 1]).read_text()
    assert empty or 'other.example.com' in hosts
    Path(args[args.index('-o') + 1]).write_text('' if empty else '<script>alert("x")</script>\n')
elif name == 'xdg-open':
    pass
else:
    sys.exit(3)
'''


class SutoTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        bindir = self.root / 'bin'
        bindir.mkdir()
        for name in ('assetfinder', 'subfinder', 'curl', 'jq', 'httpx', 'dig', 'parallel', 'subjack', 'xdg-open'):
            tool = bindir / name
            tool.write_text(STUB)
            tool.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.root), GOPATH=str(self.root / 'go'), PATH=f'{bindir}:/usr/bin:/bin')
        self.output = self.root / 'output'

    def run_script(self, *args, **env):
        return subprocess.run(['/bin/bash', str(SCRIPT), *args], cwd=self.root,
                              env=dict(self.env, **env), text=True, capture_output=True)

    def test_alternate_ports_and_report(self):
        result = self.run_script('example.com', '--ports', '80,443,8080,8443', '--output', str(self.output),
                                 EXPECTED_PORTS='80,443,8080,8443')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.output / 'alive_subdomains.txt').read_text(), 'my-app.example.com\n')
        self.assertIn(':8443', (self.output / 'alive_urls.txt').read_text())
        self.assertEqual((self.output / 'dead_subdomains.txt').read_text(), 'other.example.com\n')
        self.assertEqual((self.output / 'takeover_candidates.txt').read_text(),
                         'my-app.example.com -> my-project.herokuapp.com.\n')
        report = (self.output / 'report.html').read_text()
        self.assertIn('my-project.herokuapp.com.', report)
        self.assertIn('&lt;script&gt;', report)
        self.assertNotIn('<script>', report)
        self.assertIn('Mode:   Standard', (self.output / 'summary.txt').read_text())
        second = self.run_script('example.com', '--output', str(self.output))
        self.assertNotEqual(second.returncode, 0)
        self.assertIn('must be empty', second.stderr)

    def test_empty_discovery(self):
        result = self.run_script('example.com', '--output', str(self.output), SUTO_EMPTY='1')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.output / 'all_subdomains.txt').read_text(), '')
        self.assertTrue((self.output / 'report.html').exists())

    def test_http_failure_is_not_success(self):
        result = self.run_script('example.com', '--output', str(self.output), SUTO_HTTP_FAIL='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('HTTP probe failed', result.stderr)
        self.assertFalse((self.output / 'report.html').exists())

    def test_invalid_arguments(self):
        for args in [[], ['--output'], ['--threads'], ['--ports'], ['https://example.com'],
                     ['example.com', 'other.com'], ['example.com', '--threads', '0'],
                     ['example.com', '--ports', '65536'], ['example.com', '--ports', '0'],
                     ['example.com', '--ports', '80;id'], ['-bad.example.com'],
                     ['bad..example.com'], ['a-.example.com']]:
            with self.subTest(args=args):
                result = self.run_script(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('unbound variable', result.stderr)

    def test_full_mode_without_optional_tools(self):
        result = self.run_script('example.com', '--full', '--output', str(self.output))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Mode:   Extended', (self.output / 'summary.txt').read_text())


if __name__ == '__main__':
    unittest.main()
