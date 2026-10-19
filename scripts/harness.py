#!/usr/bin/env python3
"""Portable configuration export and installation (Python 3.11+)."""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parents[1]
LOCATIONS = {'codex': '.codex', 'claude': '.claude', 'opencode': '.config/opencode', 'shared': '.agents'}
LOCATIONS.update({'antigravity': '.gemini/antigravity-cli', 'antigravity-global': '.gemini/config'})
FILES = {
    'codex': ['AGENTS.md', 'config.toml', 'rules', 'agents'],
    'claude': ['CLAUDE.md', 'settings.json', 'statusline-command.sh', 'hooks', 'agents', 'commands'],
    'opencode': ['AGENTS.md', 'opencode.json', 'opencode.jsonc', 'cli.json', 'package.json',
                 'package-lock.json', 'bun.lock', 'bun.lockb', 'agents', 'commands', 'plugins', 'tools', 'themes'],
    'shared': ['AGENTS.md'],
    'antigravity': ['AGENTS.md', 'settings.json', 'statusline.sh'],
    'antigravity-global': ['GEMINI.md', 'AGENTS.md', 'agents', 'rules', 'workflows'],
}
TESTKIT_SOURCE = {'url': 'https://github.com/winhok/testkit.git',
                  'ref': '0c80ac38944bb70c6a60305c174dbc2a6a9767f2', 'subdir': 'skills'}


def is_testkit(plugin):
    return plugin['id'].split('@', 1)[0].lower() == 'testkit'


IGNORE = {'.git', '.DS_Store', '__pycache__', 'node_modules', '.venv', '.cache'}
SECRET = re.compile(r'(?i)(api[_-]?key|auth[_-]?token|access[_-]?token|refresh[_-]?token|password|secret|authorization|bearer|http_headers|env_http_headers)$')


def config_dir(repo, harness):
    layout = read_json(repo / '.harness.json')
    if harness in layout.get('roots', {}):
        return repo / layout['roots'][harness]
    return repo if harness == 'codex' else repo / 'harness' / harness


def clean(value, home):
    if isinstance(value, dict):
        return {k: clean(v, home) for k, v in value.items() if not SECRET.search(k)
                or (isinstance(v, str) and v.startswith(('$', '{env:')))}
    if isinstance(value, list):
        return [clean(v, home) for v in value]
    if isinstance(value, str):
        value = value.replace(str(home) + '/', '~/')
        if re.search(r'(?i)https?://[^/\s]+:[^/@\s]+@|\bsk-(?:ant-)?[A-Za-z0-9_-]{16,}', value):
            raise ValueError('疑似内联凭据，请先改为环境变量引用')
    return value


def portable_toml(text, home):
    result, skip = [], False
    for line in text.splitlines():
        if line.lstrip().startswith('#'):
            try:
                clean(line, home)
            except ValueError:
                continue
        if line.startswith('['):
            skip = bool(re.match(r'\[projects(?:\.|\])', line))
            skip = skip or bool(re.match(r'\[marketplaces\.(?:openai-bundled|openai-primary-runtime)\]', line))
        if skip or ('=' in line and SECRET.search(line.split('=', 1)[0].strip().strip('"'))):
            continue
        result.append(clean(line, home))
    output = '\n'.join(result) + '\n'
    tomllib.loads(output)
    return output


def export_file(source, dest, home, ancestors=()):
    if source.name in IGNORE or '.bak' in source.name:
        return
    if not source.exists():
        if source.is_symlink():
            raise ValueError(f'失效软链接：{source}')
        return
    real = source.resolve()
    if real in ancestors:
        raise ValueError(f'循环软链接：{source}')
    if source.is_dir():
        for item in sorted(source.iterdir()):
            export_file(item, dest / item.name, home, (*ancestors, real))
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    data = source.read_bytes()
    if 'skills' in source.parts:
        # Skill fixtures may intentionally contain fake credentials; keep the package intact.
        dest.write_bytes(data)
        shutil.copymode(source, dest)
        return
    if source.name in ('settings.json', 'opencode.json', 'cli.json'):
        parsed = clean(json.loads(data), home)
        if source.parent.name == 'antigravity-cli':
            parsed.pop('trustedWorkspaces', None)
        data = (json.dumps(parsed, ensure_ascii=False, indent=2) + '\n').encode()
    elif source.name == 'config.toml' or source.name.endswith('.config.toml'):
        data = portable_toml(data.decode(), home).encode()
    else:
        try:
            text = data.decode()
            clean(text, home)  # Validate text assets without rewriting examples or instructions.
            if source.suffix in ('.sh', '.rules'):
                data = text.replace(str(home) + '/', '~/').encode()
        except UnicodeDecodeError:
            pass
        except ValueError as error:
            raise ValueError(f'{source}: {error}') from error
    dest.write_bytes(data)
    shutil.copymode(source, dest)


def read_json(path):
    return json.loads(path.read_text()) if path.exists() else {}


def catalog(home):
    path = home / '.codex/config.toml'
    config = tomllib.loads(path.read_text()) if path.exists() else {}
    markets = config.get('marketplaces', {})
    plugins = dict(config.get('plugins', {}))
    for path in (home / '.codex/plugins/cache').glob('*/*/*/.codex-plugin/plugin.json'):
        market, name = path.parts[-5:-3]
        plugins.setdefault(f'{name}@{market}', {})
    codex = []
    for selector, state in sorted(plugins.items()):
        source = markets.get(selector.rsplit('@', 1)[-1], {})
        codex.append({'id': selector, 'enabled': state.get('enabled'),
                      'source': source.get('source') if source.get('source_type') == 'git' else None})
    markets = read_json(home / '.claude/plugins/known_marketplaces.json')
    claude = []
    for selector, installs in read_json(home / '.claude/plugins/installed_plugins.json').get('plugins', {}).items():
        if any(i.get('scope') == 'user' for i in installs):
            source = markets.get(selector.rsplit('@', 1)[-1], {}).get('source', {})
            claude.append({'id': selector, 'source': source.get('repo') or source.get('url')})
    return clean({'version': 1, 'codex': [p for p in codex if is_testkit(p)],
                  'claude': [p for p in claude if is_testkit(p)]}, home)


def sync(repo, home, selected=None):
    selected = selected or list(LOCATIONS)
    # A failed export must not copy a partial configuration into the repository.
    with tempfile.TemporaryDirectory(prefix='harness-sync-') as temporary:
        staging = Path(temporary)
        manifest = catalog(home)
        manifest = {key: value for key, value in manifest.items() if key == 'version' or key in selected}
        previous = read_json(repo / 'plugins.json')
        legacy = previous.get('opencode_skill_sources', [])
        manifest['testkit_skill_source'] = previous.get('testkit_skill_source') or (legacy[0] if legacy else dict(TESTKIT_SOURCE))
        layout = repo / '.harness.json'
        if layout.exists():
            shutil.copy2(layout, staging / layout.name)
        for harness in selected:
            names = FILES[harness]
            for name in names:
                source = home / LOCATIONS[harness] / name
                export_file(source, config_dir(staging, harness) / name, home)
        if 'codex' in selected:
            for path in (home / '.codex').glob('*.config.toml'):
                export_file(path, staging / 'profiles' / path.name, home)
        defaults = {
            'codex': [{'id': 'testkit@testkit-marketplace', 'source': TESTKIT_SOURCE['url'], 'enabled': True}],
            'claude': [{'id': 'testkit@testkit', 'source': 'winhok/testkit'}],
            'antigravity': [{'id': 'testkit', 'source': TESTKIT_SOURCE['url']}],
        }
        for harness in selected:
            if harness in defaults and not manifest.get(harness):
                manifest[harness] = defaults[harness]
        (staging / 'plugins.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
        for source in sorted(staging.rglob('*')):
            if source.is_file():
                dest = repo / source.relative_to(staging)
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, dest)
    print('已同步：' + ', '.join(selected) + '，技能安装仅保留 Testkit。')


def merge_dict(old, new):
    result = dict(old)
    for key, value in new.items():
        result[key] = merge_dict(result[key], value) if isinstance(value, dict) and isinstance(result.get(key), dict) else value
    return result


def install(repo, home, selected, dry=False, offline=False):
    backup = home / '.harness-backups' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    pending, registered, saved_configs = [], set(), {}
    failures = []
    env = dict(os.environ, HOME=str(home), CODEX_HOME=str(home / '.codex'),
               CLAUDE_CONFIG_DIR=str(home / '.claude'), XDG_CONFIG_HOME=str(home / '.config'))
    count = 0

    def run(command):
        print('执行：' + ' '.join(map(str, command)), flush=True)
        if not dry:
            subprocess.run(command, env=env, check=True, timeout=300)

    def deploy(source, dest):
        nonlocal count
        if source.name == 'testkit' and source.is_symlink() and not source.exists() and 'opencode' in selected:
            return  # Migrated from the legacy link to directly discoverable skill directories.
        current = dest
        while current != home:
            if current.is_symlink():
                raise ValueError(f'目标含软链接，拒绝覆盖：{current}')
            current = current.parent
        if source.is_dir():
            for child in sorted(source.iterdir()):
                deploy(child, dest / child.name)
            return
        if not source.is_file():
            return
        count += 1
        if dry:
            return
        if dest.exists():
            saved = backup / dest.relative_to(home)
            saved.parent.mkdir(parents=True, exist_ok=True)
            backup.chmod(0o700)
            if not saved.exists():
                shutil.copy2(dest, saved)
        dest.parent.mkdir(parents=True, exist_ok=True)
        data = source.read_bytes()
        try:
            data = data.decode().replace('~/', str(home) + '/').encode()
        except UnicodeDecodeError:
            pass
        if source.name in ('settings.json', 'opencode.json', 'cli.json'):
            data = (json.dumps(merge_dict(read_json(dest), json.loads(data)), ensure_ascii=False, indent=2) + '\n').encode()
        elif source.name == 'config.toml' and dest.exists():
            # Preserve host-specific project trust and runtime marketplace tables.
            extra, keep = [], False
            for line in dest.read_text().splitlines():
                if line.startswith('['):
                    keep = bool(re.match(r'\[projects(?:\.|\])|\[marketplaces\.(?:openai-bundled|openai-primary-runtime)\]', line))
                if keep:
                    extra.append(line)
            data += ('\n' + '\n'.join(extra) + '\n').encode()
            tomllib.loads(data.decode())
        dest.write_bytes(data)
        shutil.copymode(source, dest)
        if source.name in ('config.toml', 'settings.json', 'opencode.json'):
            dest.chmod(0o600)
        if source.name in ('config.toml', 'settings.json'):
            saved_configs[dest] = data

    if 'opencode' in selected:
        legacy = home / LOCATIONS['opencode'] / 'skills/testkit'
        if legacy.is_symlink() and os.readlink(legacy) in ('../vendor/testkit/skills', '../../../.claude/plugins/marketplaces/testkit/skills'):
            print('迁移旧 Testkit 软链接为 skills/<name>/SKILL.md')
            if not dry:
                saved = backup / legacy.relative_to(home)
                saved.parent.mkdir(parents=True, exist_ok=True)
                backup.chmod(0o700)
                shutil.copy2(legacy, saved, follow_symlinks=False)
                legacy.unlink()
    for harness in selected:
        for name in FILES[harness]:
            deploy(config_dir(repo, harness) / name, home / LOCATIONS[harness] / name)
        if harness == 'codex':
            for path in sorted((repo / 'profiles').glob('*.config.toml')):
                deploy(path, home / '.codex' / path.name)
    manifest = read_json(repo / 'plugins.json')
    for harness in ('codex', 'claude'):
        if harness not in selected:
            continue
        for plugin in manifest.get(harness, []):
            if not is_testkit(plugin):
                continue
            if not plugin['source']:
                pending.append(f"{plugin['id']}：由客户端或账号管理，无可移植安装源")
                continue
            if offline or (not shutil.which(harness) and not dry):
                pending.append(f"{plugin['id']}：离线模式或未找到 {harness} CLI")
                continue
            source = plugin['source']
            market = plugin['id'].rsplit('@', 1)[-1]
            known = (tomllib.loads((home / '.codex/config.toml').read_text()).get('marketplaces', {})
                     if harness == 'codex' and (home / '.codex/config.toml').exists()
                     else read_json(home / '.claude/plugins/known_marketplaces.json'))
            try:
                # A config table alone is not an installed Codex marketplace snapshot.
                if (harness, source) not in registered and (harness == 'codex' or market not in known):
                    run([harness, 'plugin', 'marketplace', 'add', source])
                    registered.add((harness, source))
                run([harness, 'plugin', 'add' if harness == 'codex' else 'install', plugin['id']])
            except subprocess.SubprocessError:
                failures.append(plugin['id'])
    # Registration/installation can alter enable flags; retain the exported settings.
    for path, data in saved_configs.items():
        path.write_bytes(data)

    if 'antigravity' in selected:
        for plugin in manifest.get('antigravity', []):
            if not is_testkit(plugin):
                continue
            if offline or not plugin['source'] or (not shutil.which('agy') and not dry):
                pending.append(f"{plugin['id']}：离线模式、无来源或未找到 agy")
                continue
            try:
                run(['agy', 'plugin', 'install', plugin['source']])
            except subprocess.SubprocessError:
                failures.append(plugin['id'])
        target = home / LOCATIONS['antigravity'] / 'statusline.sh'
        if target.exists() and not dry:
            text = target.read_text().splitlines(keepends=True)
            text[0] = '#!' + sys.executable + '\n'
            target.write_text(''.join(text))

    source = manifest.get('testkit_skill_source')
    targets = [name for name in ('codex', 'opencode') if name in selected]
    if source and targets:
        if offline:
            pending.append('Testkit skills：离线模式未安装')
        else:
            checkout = home / '.cache/harness-skills' / source['ref']
            if not checkout.exists():
                if not dry:
                    checkout.parent.mkdir(parents=True, exist_ok=True)
                run(['git', 'clone', source['url'], str(checkout)])
            run(['git', '-C', str(checkout), 'checkout', '--detach', source['ref']])
            if not dry:
                for harness in targets:
                    deploy(checkout / source['subdir'], home / LOCATIONS[harness] / 'skills')
    if 'opencode' in selected:
        target = home / LOCATIONS['opencode']
        if (config_dir(repo, 'opencode') / 'package.json').exists():
            if offline or (not shutil.which('npm') and not dry):
                pending.append('OpenCode npm 依赖：离线模式或未找到 npm')
            else:
                locked = (config_dir(repo, 'opencode') / 'package-lock.json').exists()
                run(['npm', '--prefix', str(target), 'ci' if locked else 'install', '--no-audit', '--no-fund'])
        print('OpenCode 配置中的 npm 插件由 OpenCode 下次启动时自动安装。')
    print(f"{'预览' if dry else '已部署'} {count} 个文件；备份目录：{backup}")
    if pending:
        print('以下项目未由本次脚本安装：\n' + '\n'.join('  - ' + item for item in pending))
    if failures:
        raise ValueError('插件安装失败：' + ', '.join(failures))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['sync', 'install'])
    parser.add_argument('--home', type=Path, default=Path.home())
    parser.add_argument('--repo', type=Path, default=ROOT)
    parser.add_argument('--only', nargs='+', choices=list(LOCATIONS))
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--offline', action='store_true', help='只部署仓库文件，不拉取插件和依赖')
    args = parser.parse_args()
    args.only = args.only or read_json(args.repo / '.harness.json').get('selected', list(LOCATIONS))
    if args.command == 'sync':
        if args.dry_run:
            parser.error('sync 不支持 --dry-run；导出只修改配置仓库')
        sync(args.repo.resolve(), args.home.resolve(), args.only)
    else:
        install(args.repo.resolve(), args.home.resolve(), args.only, args.dry_run, args.offline)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f'失败：{error}', file=sys.stderr)
        sys.exit(1)
