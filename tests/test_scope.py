"""Exercise the real shell entrypoints without modifying the user's configuration."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
OWNED = json.loads((REPO / '.harness.json').read_text())['selected']
LOCATIONS = {'codex': '.codex', 'claude': '.claude', 'opencode': '.config/opencode',
             'antigravity': '.gemini/antigravity-cli', 'antigravity-global': '.gemini/config',
             'grok': '.grok', 'shared': '.agents'}


class ScopeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='harness-scope-')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / 'home'
        self.home.mkdir()

    def run_script(self, script, *args):
        return subprocess.run(['bash', str(REPO / script), '--home', str(self.home), *args],
                              capture_output=True, text=True, timeout=30)

    def snapshot(self, root):
        return {str(path.relative_to(root)): path.read_bytes()
                for path in root.rglob('*') if path.is_file()}

    def test_offline_install_preserves_every_other_agent_and_runtime(self):
        protected = []
        for name, relative in LOCATIONS.items():
            if name in OWNED:
                continue
            path = self.home / relative
            path.mkdir(parents=True)
            (path / 'AGENTS.md').write_text('keep ' + name)
            # Invalid foreign configurations must never be read or rewritten.
            (path / 'config.toml').write_text('invalid [')
            (path / 'settings.json').write_text('invalid {')
            protected.append(path)
            runtime = self.home / '.local/share/harness-testkit' / name
            runtime.mkdir(parents=True)
            (runtime / 'env.sh').write_text('keep runtime ' + name)
            protected.append(runtime)
        legacy = self.home / '.local/share/harness-testkit/env.sh'
        legacy.write_text('keep legacy shared runtime')
        claude_user = self.home / '.claude.json'
        if 'claude' not in OWNED:
            claude_user.write_text('invalid {')
            protected.append(claude_user)
        before = {path: self.snapshot(path) if path.is_dir() else path.read_bytes() for path in protected}
        result = self.run_script('install.sh', '--offline')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for path, original in before.items():
            self.assertEqual(self.snapshot(path) if path.is_dir() else path.read_bytes(), original, str(path))
        self.assertEqual(legacy.read_text(), 'keep legacy shared runtime')
        for name in OWNED:
            self.assertTrue((self.home / LOCATIONS[name]).exists(), name)
        if (REPO / 'runtime-dependencies.json').exists():
            self.assertTrue((self.home / '.local/share/harness-testkit' / OWNED[0] / 'env.sh').exists())

    def test_cross_agent_selection_is_rejected_before_any_operation(self):
        export = Path(self.temp.name) / 'export'
        export.mkdir()
        (export / '.harness.json').write_text(json.dumps({'selected': list(LOCATIONS)}))
        for script in ('install.sh', 'sync.sh'):
            for other in LOCATIONS.keys() - set(OWNED):
                with self.subTest(script=script, other=other):
                    result = self.run_script(script, '--repo', str(export), '--only', OWNED[0], other)
                    self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                    self.assertIn('invalid choice', result.stderr)
        self.assertEqual(list(self.home.iterdir()), [])
        self.assertEqual([path.name for path in export.iterdir()], ['.harness.json'])

    def test_sync_ignores_foreign_configs_and_legacy_selection(self):
        export = Path(self.temp.name) / 'export'
        export.mkdir()
        layout = json.loads((REPO / '.harness.json').read_text())
        layout['selected'] = list(LOCATIONS)
        (export / '.harness.json').write_text(json.dumps(layout))
        for name, relative in LOCATIONS.items():
            folder = self.home / relative
            folder.mkdir(parents=True)
            (folder / 'AGENTS.md').write_text('guide ' + name)
            (folder / 'CLAUDE.md').write_text('guide ' + name)
            if name in OWNED:
                (folder / 'config.toml').write_text('model="example"\n')
                (folder / 'settings.json').write_text('{}')
                (folder / 'opencode.json').write_text('{}')
            else:
                (folder / 'config.toml').write_text('invalid [')
                (folder / 'plugins').mkdir()
                (folder / 'plugins/installed_plugins.json').write_text('invalid {')
        before = self.snapshot(self.home)
        result = self.run_script('sync.sh', '--repo', str(export))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.snapshot(self.home), before)
        manifest = json.loads((export / 'plugins.json').read_text())
        self.assertFalse(set(manifest) & (LOCATIONS.keys() - set(OWNED)))
        self.assertFalse((export / 'harness').exists())
        if OWNED[0] == 'grok':
            self.assertEqual((export / 'config.toml').read_text(), 'model="example"\n')
        else:
            guide = 'CLAUDE.md' if OWNED[0] == 'claude' else 'AGENTS.md'
            self.assertIn('guide ' + OWNED[0], (export / guide).read_text())

    def test_default_dry_run_uses_only_own_plugin_cli_without_writes(self):
        foreign = self.home / '.claude/plugins/known_marketplaces.json'
        if 'claude' not in OWNED:
            foreign.parent.mkdir(parents=True)
            foreign.write_text('invalid {')
        before = self.snapshot(self.home)
        result = self.run_script('install.sh', '--dry-run', '--dependencies', 'none')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        clis = {'codex': 'codex', 'claude': 'claude', 'grok': 'grok', 'antigravity': 'agy'}
        for owner, cli in clis.items():
            if owner not in OWNED:
                self.assertNotIn('执行：' + cli + ' ', result.stdout)
        self.assertEqual(self.snapshot(self.home), before)
