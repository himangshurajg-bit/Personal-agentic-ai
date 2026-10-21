"""Exercise the real shell harness with fake tools; never needs a device."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class AndroidHarnessTest(unittest.TestCase):
    def test_restart_preserves_install_and_runs_in_mobile(self):
        source = Path(__file__).with_name('android16-checks.sh').read_text()
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / 'mobile').mkdir()
            tools = root / 'bin'
            tools.mkdir()
            for name in ('adb', 'flutter', 'sleep'):
                tool = tools / name
                tool.write_text('''#!/usr/bin/env python3
import os, sys
with open(os.environ['CALL_LOG'], 'a') as f:
    f.write(os.path.basename(sys.argv[0]) + '|' + os.getcwd() + '|' + ' '.join(sys.argv[1:]) + '\\n')
if sys.argv[1:] == ['shell', 'getprop', 'ro.build.version.sdk']: print('36')
if sys.argv[1:3] == ['shell', 'pm'] and 'path' in sys.argv: print('package:/data/app/test/base.apk')
''')
                tool.chmod(0o755)
            log = root / 'calls'
            subprocess.run(['bash', '-c', source], cwd=root, check=True,
                           env={**os.environ, 'PATH': f'{tools}:' + os.environ['PATH'], 'CALL_LOG': str(log)},
                           capture_output=True)
            calls = log.read_text().splitlines()
            tests = [c for c in calls if c.startswith('flutter|') and '|test ' in c]
            self.assertEqual(len(tests), 2)
            self.assertTrue(all(f'|{root}/mobile|' in c for c in tests))
            self.assertTrue(all('|test --no-uninstall integration_test/' in c for c in tests))
            check = next(i for i, c in enumerate(calls) if '|shell pm path ' in c)
            stop = next(i for i, c in enumerate(calls) if '|shell am force-stop ' in c)
            self.assertLess(calls.index(tests[0]), check)
            self.assertLess(check, stop)
            self.assertLess(stop, calls.index(tests[1]))


if __name__ == '__main__':
    unittest.main()
