"""Safety and lifecycle checks. Run: python3 -m unittest discover -s bin/tests."""
import contextlib
import importlib.util
import importlib.machinery
import io
import os
from pathlib import Path
import signal
import tempfile
import types
import unittest
from unittest.mock import patch

source = Path(__file__).resolve().parents[1] / 'ropen'
if not source.exists():
    source = Path(__file__).with_name('ropen')
loader = importlib.machinery.SourceFileLoader('ropen', str(source))
spec = importlib.util.spec_from_loader(loader.name, loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)


class RopenTests(unittest.TestCase):
    def test_reset_only_selects_owned_ssh_listeners(self):
        uid = os.getuid()
        rows = [({'pid': 11, 'uid': uid, 'name': 'sshd'}, 'tcp'),
                ({'pid': 11, 'uid': uid, 'name': 'sshd'}, 'unix'),
                ({'pid': 12, 'uid': uid, 'name': 'python3'}, 'tcp'),
                ({'pid': 13, 'uid': uid + 1, 'name': 'sshd'}, 'tcp')]
        with patch.object(m.Path, 'glob', return_value=[]):
            self.assertEqual([p['pid'] for p in m.reset_targets(rows)], [11])

    def test_recycled_pid_is_never_signalled(self):
        original = {'pid': 11, 'start': '123', 'uid': os.getuid(), 'name': 'sshd'}
        with patch.object(m, 'process', return_value={**original, 'start': '456'}), \
                patch.object(m.os, 'kill') as kill:
            m.stop_targets([original])
            kill.assert_not_called()

    def test_stop_signals_verified_transport(self):
        original = {'pid': 11, 'start': '123', 'uid': os.getuid(), 'name': 'sshd'}
        with patch.object(m, 'process', return_value=original), patch.object(m.os, 'kill') as kill:
            m.stop_targets([original])
            kill.assert_called_once_with(11, signal.SIGTERM)

    def test_dry_run_does_not_spawn_cleanup(self):
        with patch.object(m, 'listeners', return_value=[]), \
                patch.object(m, 'reset_targets', return_value=[{'pid': 11, 'name': 'sshd'}]), \
                patch.object(m.subprocess, 'Popen') as popen, contextlib.redirect_stdout(io.StringIO()):
            m.reset(True)
            popen.assert_not_called()

    def test_tunnel_failure_still_cancels(self):
        result = types.SimpleNamespace(returncode=0, stdout='34567\n', stderr='')
        with tempfile.TemporaryDirectory() as home, \
                patch.dict(os.environ, {}, clear=True), patch.object(m.Path, 'home', return_value=Path(home)), \
                patch.object(m, 'control_socket', return_value='/tmp/test.sock'), \
                patch.object(m, 'mux', return_value=result) as mux:
            with self.assertRaisesRegex(RuntimeError, 'transfer failed'):
                with m.tunnel() as (port, identity):
                    self.assertEqual(port, 34567)
                    raise RuntimeError('transfer failed')
            self.assertEqual([c.args[1] for c in mux.call_args_list], ['forward', 'cancel'])


if __name__ == '__main__':
    unittest.main()
