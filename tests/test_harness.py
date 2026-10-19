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

    def test_export_redacts_secrets_and_excludes_unrelated_skills(self):
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
        self.assertFalse((self.repo / 'harness/shared/skills/example/SKILL.md').exists())
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
        self.write('config.toml', '[plugins."testkit@example"]\nenabled=false\n[marketplaces.example]\nsource_type="git"\nsource="owner/repo"\n', self.repo)
        self.write('plugins.json', json.dumps({'codex': [{'id': 'testkit@example', 'source': 'owner/repo'}]}), self.repo)
        calls = []
        def fake_run(command, **kwargs):
            calls.append((command, kwargs))
            if command[2] == 'add':
                (self.home / '.codex/config.toml').write_text('[plugins."testkit@example"]\nenabled=true\n')
        with patch.object(harness.shutil, 'which', return_value='/fake/codex'), patch.object(harness.subprocess, 'run', side_effect=fake_run):
            self.quiet(harness.install, self.repo, self.home, ['codex'])
        self.assertEqual(calls[0][0], ['codex', 'plugin', 'marketplace', 'add', 'owner/repo'])
        self.assertEqual(calls[1][0], ['codex', 'plugin', 'add', 'testkit@example'])
        self.assertEqual(calls[1][1]['env']['CODEX_HOME'], str(self.home / '.codex'))
        self.assertIn('enabled=false', (self.home / '.codex/config.toml').read_text())

    def test_failed_plugin_returns_failure_and_restores_settings(self):
        self.write('config.toml', '[plugins."testkit@example"]\nenabled=false\n', self.repo)
        self.write('plugins.json', json.dumps({'codex': [{'id': 'testkit@example', 'source': 'owner/repo'}]}), self.repo)
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

    def test_unrelated_skills_are_not_deployed(self):
        content = 'https://user:fake@api.example.invalid/fixture'
        self.write('.agents/skills/example/SKILL.md', content)
        self.quiet(harness.sync, self.repo, self.home, ['shared'])
        self.quiet(harness.install, self.repo, self.home, ['claude', 'opencode', 'antigravity-global', 'shared'], offline=True)
        for name in ('.claude', '.config/opencode', '.gemini/config'):
            self.assertFalse((self.home / name / 'skills/example/SKILL.md').exists())

    def test_antigravity_uses_actual_plugin_installer(self):
        self.write('plugins.json', json.dumps({'antigravity': [{'id': 'testkit', 'source': 'https://example.invalid/testkit.git'}]}), self.repo)
        with patch.object(harness.shutil, 'which', return_value='/fake/agy'), patch.object(harness.subprocess, 'run') as run:
            self.quiet(harness.install, self.repo, self.home, ['antigravity'])
        self.assertEqual(run.call_args.args[0], ['agy', 'plugin', 'install', 'https://example.invalid/testkit.git'])

    def test_grok_uses_actual_plugin_installer(self):
        self.write('plugins.json', json.dumps({'grok': [{'id': 'testkit', 'source': 'winhok/testkit'}]}), self.repo)
        with patch.object(harness.shutil, 'which', return_value='/fake/grok'), patch.object(harness.subprocess, 'run') as run:
            self.quiet(harness.install, self.repo, self.home, ['grok'])
        self.assertEqual(run.call_args.args[0], ['grok', 'plugin', 'install', 'winhok/testkit', '--trust'])

    def test_legacy_opencode_link_is_backed_up_before_migration(self):
        legacy = self.home / '.config/opencode/skills/testkit'
        legacy.parent.mkdir(parents=True)
        legacy.symlink_to('../vendor/testkit/skills')
        self.quiet(harness.install, self.repo, self.home, ['opencode'], offline=True)
        self.assertFalse(legacy.is_symlink())
        saved = list((self.home / '.harness-backups').glob('*/.config/opencode/skills/testkit'))
        self.assertEqual(os.readlink(saved[0]), '../vendor/testkit/skills')

    def test_sync_preserves_external_skill_sources_after_link_migration(self):
        sources = [{'url': 'https://github.com/winhok/testkit.git', 'ref': 'commit', 'subdir': 'skills'}]
        self.write('plugins.json', json.dumps({'opencode_skill_sources': sources}), self.repo)
        self.quiet(harness.sync, self.repo, self.home, ['opencode'])
        self.assertEqual(json.loads((self.repo / 'plugins.json').read_text())['testkit_skill_source'], sources[0])


    def test_plugin_catalog_contains_only_testkit_and_figma(self):
        self.write('.claude/plugins/installed_plugins.json', json.dumps({'plugins': {
            'testkit@testkit': [{'scope': 'user'}],
            'frontend-design@official': [{'scope': 'user'}]}}))
        self.quiet(harness.sync, self.repo, self.home, ['claude', 'antigravity', 'codex'])
        manifest = json.loads((self.repo / 'plugins.json').read_text())
        for name in ('claude', 'antigravity', 'codex'):
            self.assertEqual({p['id'].split('@')[0].lower() for p in manifest[name]}, {'testkit', 'figma'})
            self.assertTrue(all(harness.is_supported_plugin(plugin) for plugin in manifest[name]))

    def test_legacy_unrelated_plugin_is_not_installed(self):
        self.write('plugins.json', json.dumps({'claude': [
            {'id': 'frontend-design@official', 'source': 'owner/repo'}]}), self.repo)
        with patch.object(harness.subprocess, 'run') as run:
            self.quiet(harness.install, self.repo, self.home, ['claude'])
        run.assert_not_called()

    def test_testkit_skills_install_into_codex_and_opencode(self):
        source = dict(harness.TESTKIT_SOURCE)
        self.write('plugins.json', json.dumps({'testkit_skill_source': source}), self.repo)
        checkout = self.home / '.cache/harness-skills' / source['ref']
        self.write('skills/testspec-plan/SKILL.md', 'Testkit', checkout)
        with patch.object(harness.subprocess, 'run') as run:
            self.quiet(harness.install, self.repo, self.home, ['codex', 'opencode'])
        for name in ('.codex', '.config/opencode'):
            self.assertEqual((self.home / name / 'skills/testspec-plan/SKILL.md').read_text(), 'Testkit')
        self.assertEqual(run.call_args.args[0], ['git', '-C', str(checkout), 'checkout', '--detach', source['ref']])



    def test_remote_codex_figma_does_not_register_a_fake_git_marketplace(self):
        self.write('plugins.json', json.dumps({'codex': [
            {'id': 'figma@openai-curated', 'source': None, 'remote': True}]}), self.repo)
        with patch.object(harness.shutil, 'which', return_value='/fake/codex'), patch.object(harness.subprocess, 'run') as run:
            self.quiet(harness.install, self.repo, self.home, ['codex'])
        self.assertEqual(run.call_args.args[0], ['codex', 'plugin', 'add', 'figma@openai-curated'])


if __name__ == '__main__':
    unittest.main()
