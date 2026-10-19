import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).parents[1] / 'scripts'
spec = importlib.util.spec_from_file_location('runtime_setup', SCRIPTS / 'runtime_setup.py')
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)
hspec = importlib.util.spec_from_file_location('harness_runtime_test', SCRIPTS / 'harness.py')
harness = importlib.util.module_from_spec(hspec)
hspec.loader.exec_module(harness)


class RuntimeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='testkit-runtime-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.home = self.root / 'home'
        self.repo.mkdir()
        self.home.mkdir()
        data = {'native': [], 'manual': ['设备签名需按目标准备'], 'android_build_tools': '36.0.0'}
        (self.repo / 'runtime-dependencies.json').write_text(json.dumps(data))
        for mode in ('core', 'full'):
            folder = self.repo / 'runtime' / mode
            folder.mkdir(parents=True)
            for name in ('package.json', 'package-lock.json'):
                (folder / name).write_text('{}')
            (folder / 'requirements.txt').write_text('pytest\n')
        self.commands, self.pending, self.failures = [], [], []
        self.env = {'PATH': '/usr/bin:/bin'}

    def deploy(self, source, dest):
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, dest)

    def call(self, selected, **kwargs):
        with contextlib.redirect_stdout(io.StringIO()):
            runtime.setup(self.repo, self.home, selected, self.commands.append, self.deploy,
                          self.env, self.pending, self.failures, **kwargs)

    def test_offline_registers_all_clients_without_downloads_and_preserves_secrets(self):
        path = self.home / '.claude.json'
        path.write_text(json.dumps({'token': 'private', 'mcpServers': {'custom': {'url': 'https://example.invalid'}}}))
        self.call(['codex', 'claude', 'opencode', 'antigravity'], offline=True, mode='core')
        self.assertEqual(self.commands, [])
        config = json.loads(path.read_text())
        self.assertEqual(config['token'], 'private')
        self.assertIn('custom', config['mcpServers'])
        self.assertTrue(config['mcpServers']['mobile-mcp']['command'].endswith('/mcp-server-mobile'))
        self.assertIn('mobile-mcp', tomllib.loads((self.home / '.codex/config.toml').read_text())['mcp_servers'])
        self.assertIn('mobile-mcp', json.loads((self.home / '.gemini/config/mcp_config.json').read_text())['mcpServers'])
        opencode = json.loads((self.home / '.config/opencode/opencode.json').read_text())['mcp']
        self.assertEqual(opencode['figma']['url'], 'https://mcp.figma.com/mcp')
        self.assertEqual(opencode['mobile-mcp']['type'], 'local')
        self.assertTrue(any('离线' in item for item in self.pending))

    def test_dry_run_does_not_create_files(self):
        before = list(self.home.rglob('*'))
        with patch.object(runtime.shutil, 'which', return_value=None), patch.object(runtime.platform, 'system', return_value='Darwin'):
            self.call(['antigravity'], dry=True, mode='full')
        self.assertEqual(before, list(self.home.rglob('*')))
        self.assertTrue(any('ci' in command for command in self.commands))
        self.assertTrue(any('chromium' in command for command in self.commands))
        self.assertTrue(any('xcuitest' in command for command in self.commands))

    def test_failures_are_reported_instead_of_being_declared_ready(self):
        def fail(command):
            raise subprocess.CalledProcessError(1, command)
        with patch.object(runtime.shutil, 'which', return_value=None):
            with contextlib.redirect_stdout(io.StringIO()):
                runtime.setup(self.repo, self.home, ['opencode'], fail, self.deploy, self.env,
                              self.pending, self.failures, mode='core')
        self.assertTrue(self.failures)
        report = json.loads((self.home / '.local/share/harness-testkit/opencode/installation-report.json').read_text())
        self.assertTrue(report['failed'])

    def test_toml_replacement_is_idempotent_and_keeps_unrelated_servers(self):
        text = '[mcp_servers.mobile-mcp]\ncommand="old"\n[mcp_servers.mobile-mcp.env]\nOLD="1"\n[mcp_servers.other]\ncommand="keep"\n'
        entry = {'command': '/new/bin', 'args': [], 'env': {'PATH': '/runtime/bin'}}
        once = runtime.toml_server(text, 'mobile-mcp', entry)
        twice = runtime.toml_server(once, 'mobile-mcp', entry)
        value = tomllib.loads(twice)
        self.assertEqual(value['mcp_servers']['other']['command'], 'keep')
        self.assertEqual(value['mcp_servers']['mobile-mcp']['command'], '/new/bin')
        self.assertNotIn('OLD', value['mcp_servers']['mobile-mcp']['env'])

    def test_install_keeps_project_trust_without_duplicating_toml_tables(self):
        (self.repo / 'scripts').mkdir()
        shutil.copy2(SCRIPTS / 'runtime_setup.py', self.repo / 'scripts/runtime_setup.py')
        config = self.home / '.codex/config.toml'
        config.parent.mkdir()
        config.write_text('[projects."/local"]\ntrust_level="trusted"\n')
        with contextlib.redirect_stdout(io.StringIO()):
            harness.install(self.repo, self.home, ['codex'], offline=True, dependencies='core')
        value = tomllib.loads(config.read_text())
        self.assertEqual(value['projects']['/local']['trust_level'], 'trusted')
        self.assertIn('mobile-mcp', value['mcp_servers'])
        self.assertTrue(list((self.home / '.harness-backups').glob('*/.codex/config.toml')))

    def test_generated_browser_wrapper_has_valid_shell_syntax(self):
        self.call(['opencode'], offline=True, mode='full')
        wrapper = self.home / '.local/share/harness-testkit/opencode/playwright-mcp.sh'
        result = subprocess.run(['bash', '-n', str(wrapper)], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--executable-path', wrapper.read_text())

    def test_runtime_none_does_not_modify_configs(self):
        self.call(['antigravity'], mode='none')
        self.assertEqual(list(self.home.iterdir()), [])
        self.assertFalse(self.commands)



    def test_existing_runtime_directory_symlink_is_rejected(self):
        runtime_dir = self.home / '.local/share/harness-testkit/antigravity'
        runtime_dir.mkdir(parents=True)
        outside = self.root / 'outside'
        outside.mkdir()
        (runtime_dir / 'venv').symlink_to(outside)
        with self.assertRaises(ValueError):
            self.call(['antigravity'], offline=True)
        self.assertEqual(list(outside.iterdir()), [])



    def test_install_replaces_managed_mcp_entry_without_reviving_legacy_url(self):
        (self.repo / 'scripts').mkdir()
        shutil.copy2(SCRIPTS / 'runtime_setup.py', self.repo / 'scripts/runtime_setup.py')
        config = self.home / '.config/opencode/opencode.json'
        config.parent.mkdir(parents=True)
        config.write_text(json.dumps({'mcp': {'mobile-mcp': {'type': 'remote', 'url': 'https://old.invalid'}}, 'custom': 'keep'}))
        with contextlib.redirect_stdout(io.StringIO()):
            harness.install(self.repo, self.home, ['opencode'], offline=True, dependencies='core')
        value = json.loads(config.read_text())
        self.assertEqual(value['custom'], 'keep')
        self.assertEqual(value['mcp']['mobile-mcp']['type'], 'local')
        self.assertNotIn('url', value['mcp']['mobile-mcp'])


if __name__ == '__main__':
    unittest.main()
