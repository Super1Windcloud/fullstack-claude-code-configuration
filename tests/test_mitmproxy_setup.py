import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import tomllib
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('mitmproxy_setup', ROOT / 'scripts/mitmproxy_setup.py')
mcp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mcp)
OWNER = next(name for name in json.loads((ROOT / '.harness.json').read_text())['selected'] if name in mcp.LOCATIONS)


class MitmproxySetupTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='harness-mitmproxy-test-')
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.path = self.home / mcp.LOCATIONS[OWNER]
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if self.path.suffix == '.toml':
            self.original = '[projects."/local"]\ntrust_level="trusted"\n[mcp_servers.custom]\ncommand="keep"\n'
        elif OWNER == 'opencode':
            self.original = json.dumps({'provider': {'apiKey': 'private'}, 'mcp': {'servers': {'custom': {'url': 'https://example.invalid'}}}})
        else:
            self.original = json.dumps({'token': 'private', 'mcpServers': {'custom': {'url': 'https://example.invalid'}}})
        self.path.write_text(self.original)

    def call(self, **kwargs):
        with contextlib.redirect_stdout(io.StringIO()), patch.object(mcp.shutil, 'which', return_value='/opt/uvx'):
            mcp.setup(ROOT, self.home, **kwargs)

    def test_incremental_merge_backup_and_repeat(self):
        self.call(offline=True)
        first = self.path.read_bytes()
        if self.path.suffix == '.toml':
            value = tomllib.loads(first.decode())
            self.assertEqual(value['projects']['/local']['trust_level'], 'trusted')
            servers = value['mcp_servers']
        else:
            value = json.loads(first)
            servers = value['mcp']['servers'] if OWNER == 'opencode' else value['mcpServers']
            self.assertEqual(value.get('token', value.get('provider', {}).get('apiKey')), 'private')
        self.assertIn('custom', servers)
        entry = servers[mcp.NAME]
        command = entry['command'] if isinstance(entry['command'], list) else [entry['command'], *entry['args']]
        self.assertIn(mcp.PACKAGE, command)
        self.assertIn('mcp<2', command)
        self.assertIn(str(self.home / ('.grok/runtime/mitmproxy' if OWNER == 'grok' else '.local/share/harness-mitmproxy/' + OWNER)), command)
        backups = list((self.home / '.harness-backups').glob('mitmproxy-*/' + mcp.LOCATIONS[OWNER]))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), self.original)
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        self.call(offline=True)
        self.assertEqual(self.path.read_bytes(), first)
        self.assertEqual(len(list((self.home / '.harness-backups').iterdir())), 1)

    def test_dry_run_has_no_side_effects(self):
        before = sorted(self.home.rglob('*'))
        with patch.object(mcp.subprocess, 'run') as run:
            self.call(dry=True)
        run.assert_not_called()
        self.assertEqual(before, sorted(self.home.rglob('*')))
        self.assertEqual(self.path.read_text(), self.original)

    def test_failed_dependency_check_preserves_config(self):
        with patch.object(mcp.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, ['uvx'])):
            with self.assertRaises(subprocess.CalledProcessError):
                self.call()
        self.assertEqual(self.path.read_text(), self.original)
        self.assertFalse((self.home / '.harness-backups').exists())

    def test_rejects_symlink_config(self):
        target = self.home / 'external'
        target.write_text(self.original)
        self.path.unlink()
        self.path.symlink_to(target)
        with self.assertRaises(ValueError):
            self.call(offline=True)
        self.assertEqual(target.read_text(), self.original)

    def test_rejects_symlink_state_parent(self):
        local = self.home / ('.grok/runtime' if OWNER == 'grok' else '.local')
        local.symlink_to(self.home / 'other')
        with self.assertRaises(ValueError):
            self.call(offline=True)
        self.assertEqual(self.path.read_text(), self.original)

    def test_missing_uvx_does_not_modify_config(self):
        with patch.object(mcp.shutil, 'which', return_value=None), self.assertRaises(ValueError):
            mcp.setup(ROOT, self.home)
        self.assertEqual(self.path.read_text(), self.original)

    def test_other_client_selection_is_ignored(self):
        self.call(selected=['not-this-client'], offline=True)
        self.assertEqual(self.path.read_text(), self.original)
        self.assertFalse((self.home / '.local').exists())
