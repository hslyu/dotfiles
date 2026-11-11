"""Regression checks for rscp's shared tunnel and scp invocation."""
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch

from test_ropen import m as ropen

loader = importlib.machinery.SourceFileLoader(
    'rscp', str(Path(__file__).resolve().parents[1] / 'rscp'))
spec = importlib.util.spec_from_loader(loader.name, loader)
rscp = importlib.util.module_from_spec(spec)
loader.exec_module(rscp)


class RscpTests(unittest.TestCase):
    def transfer(self, arguments, environment=None, status=0, error=None):
        allocated = types.SimpleNamespace(returncode=0, stdout='34567\n', stderr='')
        with tempfile.TemporaryDirectory() as home, \
                patch.dict(os.environ, environment or {}, clear=True), \
                patch.object(ropen.Path, 'home', return_value=Path(home)), \
                patch.object(ropen, 'control_socket', return_value='/tmp/test.sock'), \
                patch.object(ropen, 'mux', return_value=allocated) as mux, \
                patch.object(rscp.runpy, 'run_path', return_value=vars(ropen)), \
                patch.object(rscp.sys, 'argv', ['rscp'] + arguments), \
                patch.object(rscp.subprocess, 'run', return_value=types.SimpleNamespace(returncode=status),
                             side_effect=error) as run:
            if error:
                with self.assertRaises(type(error)):
                    rscp.main()
            else:
                self.assertEqual(rscp.main(), status)
            return run.call_args.args[0], [call.args[1] for call in mux.call_args_list]

    def test_file_uses_allocated_port_and_cancels(self):
        command, actions = self.transfer(['~/Downloads/a file.pdf', 'result:name'])
        self.assertEqual(actions, ['forward', 'cancel'])
        self.assertEqual(command[:5], ['scp', '-F', '/dev/null', '-P', '34567'])
        self.assertEqual(command[-3:], ['--', 'localhost:~/Downloads/a file.pdf', './result:name'])
        self.assertIn('StrictHostKeyChecking=accept-new', command)
        self.assertIn('ControlPath=none', command)

    def test_recursive_failure_preserves_status_and_cancels(self):
        command, actions = self.transfer(['-r', '~/my folder', '/tmp/destination'], status=7)
        self.assertEqual(command[-4:], ['-r', '--', 'localhost:~/my folder', '/tmp/destination'])
        self.assertEqual(actions, ['forward', 'cancel'])

    def test_exception_cancels(self):
        _, actions = self.transfer(['file', '.'], error=OSError('scp failed'))
        self.assertEqual(actions, ['forward', 'cancel'])

    def test_manual_port_and_ipv6(self):
        command, actions = self.transfer(['file', '.'], {
            'ROPEN_PORT': '45678', 'ROPEN_HOST': '::1', 'ROPEN_USER': 'localuser'})
        self.assertEqual(actions, [])
        self.assertEqual(command[:5], ['scp', '-F', '/dev/null', '-P', '45678'])
        self.assertEqual(command[-2], 'localuser@[::1]:file')


if __name__ == '__main__':
    unittest.main()
