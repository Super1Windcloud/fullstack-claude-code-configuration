import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('harness', Path(__file__).parents[1] / 'scripts/harness.py')
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)


class HarnessTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='harness-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.repo = self.root / 'repo'
        self.home.mkdir()
        self.repo.mkdir()

    def write(self, relative, content, base=None):
        path = (base or self.home) / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def quiet(self, function, *args, **kwargs):
        with contextlib.redirect_stdout(io.StringIO()):
            return function(*args, **kwargs)

    def test_export_redacts_secrets_and_materializes_skills(self):
        self.write('.codex/config.toml', '# key=sk-' + 'a' * 30 + '\nmodel="example"\n[projects."/host"]\ntrust_level="trusted"\n')
        self.write('.claude/settings.json', json.dumps({'env': {'ANTHROPIC_AUTH_TOKEN': 'private', 'FEATURE': '1'}}))
        self.write('.config/opencode/opencode.json', json.dumps({'provider': {'x': {'apiKey': 'private'}}}))
        self.write('.codex/auth.json', '{"token":"never-export"}')
        skill = self.write('original/SKILL.md', 'skill').parent
        (self.home / '.agents/skills').mkdir(parents=True)
        (self.home / '.agents/skills/example').symlink_to(skill)
        self.quiet(harness.sync, self.repo, self.home)
        self.assertNotIn('private', (self.repo / 'harness/claude/settings.json').read_text())
        self.assertNotIn('private', (self.repo / 'harness/opencode/opencode.json').read_text())
        self.assertNotIn('projects', (self.repo / 'config.toml').read_text())
        self.assertFalse((self.repo / 'auth.json').exists())
        self.assertEqual((self.repo / 'harness/shared/skills/example/SKILL.md').read_text(), 'skill')
        self.assertFalse((self.repo / 'harness/shared/skills/example').is_symlink())

    def test_dry_run_makes_no_changes(self):
        self.write('config.toml', 'model="example"\n', self.repo)
        before = list(self.home.rglob('*'))
        self.quiet(harness.install, self.repo, self.home, ['codex'], dry=True)
        self.assertEqual(before, list(self.home.rglob('*')))

    def test_install_backs_up_and_preserves_local_credentials_and_trust(self):
        original = '{"env":{"ANTHROPIC_AUTH_TOKEN":"private"},"language":"en"}'
        self.write('.claude/settings.json', original)
        self.write('harness/claude/settings.json', '{"language":"zh"}', self.repo)
        self.write('.codex/config.toml', '[projects."/local"]\ntrust_level="trusted"\n')
        self.write('config.toml', 'model="example"\n', self.repo)
        self.quiet(harness.install, self.repo, self.home, ['codex', 'claude'], offline=True)
        current = json.loads((self.home / '.claude/settings.json').read_text())
        self.assertEqual(current['env']['ANTHROPIC_AUTH_TOKEN'], 'private')
        self.assertEqual(current['language'], 'zh')
        self.assertEqual((self.home / '.claude/settings.json').stat().st_mode & 0o777, 0o600)
        self.assertIn('/local', (self.home / '.codex/config.toml').read_text())
        backup = list((self.home / '.harness-backups').glob('*/.claude/settings.json'))
        self.assertEqual(backup[0].read_text(), original)

    def test_destination_symlink_is_never_followed(self):
        outside = self.root / 'outside'
        outside.mkdir()
        (self.home / '.codex').symlink_to(outside)
        self.write('AGENTS.md', 'instructions', self.repo)
        with self.assertRaises(ValueError):
            self.quiet(harness.install, self.repo, self.home, ['codex'], offline=True)
        self.assertEqual(list(outside.iterdir()), [])

    def test_cli_installs_actual_plugin_and_restores_enable_flags(self):
        self.write('config.toml', '[plugins."demo@example"]\nenabled=false\n[marketplaces.example]\nsource_type="git"\nsource="owner/repo"\n', self.repo)
        self.write('plugins.json', json.dumps({'codex': [{'id': 'demo@example', 'source': 'owner/repo'}]}), self.repo)
        calls = []
        def fake_run(command, **kwargs):
            calls.append((command, kwargs))
            if command[2] == 'add':
                (self.home / '.codex/config.toml').write_text('[plugins."demo@example"]\nenabled=true\n')
        with patch.object(harness.shutil, 'which', return_value='/fake/codex'), patch.object(harness.subprocess, 'run', side_effect=fake_run):
            self.quiet(harness.install, self.repo, self.home, ['codex'])
        self.assertEqual(calls[0][0], ['codex', 'plugin', 'marketplace', 'add', 'owner/repo'])
        self.assertEqual(calls[1][0], ['codex', 'plugin', 'add', 'demo@example'])
        self.assertEqual(calls[1][1]['env']['CODEX_HOME'], str(self.home / '.codex'))
        self.assertIn('enabled=false', (self.home / '.codex/config.toml').read_text())

    def test_failed_plugin_returns_failure_and_restores_settings(self):
        self.write('config.toml', '[plugins."demo@example"]\nenabled=false\n', self.repo)
        self.write('plugins.json', json.dumps({'codex': [{'id': 'demo@example', 'source': 'owner/repo'}]}), self.repo)
        def fail(command, **kwargs):
            (self.home / '.codex/config.toml').write_text('changed=true\n')
            raise harness.subprocess.CalledProcessError(1, command)
        with patch.object(harness.shutil, 'which', return_value='/fake/codex'), patch.object(harness.subprocess, 'run', side_effect=fail):
            with self.assertRaises(ValueError):
                self.quiet(harness.install, self.repo, self.home, ['codex'])
        self.assertIn('enabled=false', (self.home / '.codex/config.toml').read_text())

    def test_standalone_layout_exports_only_its_harness(self):
        self.write('.harness.json', json.dumps({'roots': {'claude': '.'}, 'selected': ['claude', 'shared']}), self.repo)
        self.write('.claude/CLAUDE.md', 'guide')
        self.write('.codex/config.toml', 'model="unrelated"\n')
        self.quiet(harness.sync, self.repo, self.home, ['claude', 'shared'])
        self.assertEqual((self.repo / 'CLAUDE.md').read_text(), 'guide')
        self.assertFalse((self.repo / 'config.toml').exists())
        self.assertNotIn('codex', json.loads((self.repo / 'plugins.json').read_text()))

    def test_shared_skills_are_installed_into_native_paths(self):
        content = 'https://user:fake@api.example.invalid/fixture'
        self.write('.agents/skills/example/SKILL.md', content)
        self.quiet(harness.sync, self.repo, self.home, ['shared'])
        self.quiet(harness.install, self.repo, self.home, ['claude', 'opencode', 'antigravity-global', 'shared'], offline=True)
        for name in ('.claude', '.config/opencode', '.gemini/config'):
            self.assertEqual((self.home / name / 'skills/example/SKILL.md').read_text(), content)

    def test_antigravity_uses_actual_plugin_installer(self):
        self.write('plugins.json', json.dumps({'antigravity': [{'id': 'demo', 'source': 'https://example.invalid/demo.git'}]}), self.repo)
        with patch.object(harness.shutil, 'which', return_value='/fake/agy'), patch.object(harness.subprocess, 'run') as run:
            self.quiet(harness.install, self.repo, self.home, ['antigravity'])
        self.assertEqual(run.call_args.args[0], ['agy', 'plugin', 'install', 'https://example.invalid/demo.git'])

    def test_legacy_opencode_link_is_backed_up_before_migration(self):
        legacy = self.home / '.config/opencode/skills/testkit'
        legacy.parent.mkdir(parents=True)
        legacy.symlink_to('../vendor/testkit/skills')
        self.quiet(harness.install, self.repo, self.home, ['opencode'], offline=True)
        self.assertFalse(legacy.is_symlink())
        saved = list((self.home / '.harness-backups').glob('*/.config/opencode/skills/testkit'))
        self.assertEqual(os.readlink(saved[0]), '../vendor/testkit/skills')

    def test_sync_preserves_external_skill_sources_after_link_migration(self):
        sources = [{'url': 'https://example.invalid/skills.git', 'ref': 'commit', 'subdir': 'skills'}]
        self.write('plugins.json', json.dumps({'opencode_skill_sources': sources}), self.repo)
        self.quiet(harness.sync, self.repo, self.home, ['opencode'])
        self.assertEqual(json.loads((self.repo / 'plugins.json').read_text())['opencode_skill_sources'], sources)


if __name__ == '__main__':
    unittest.main()
