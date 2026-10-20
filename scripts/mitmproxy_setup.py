"""Install this repository's mitmproxy MCP entry without replacing other settings."""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import tomllib

NAME = 'mitmproxy-mcp'
PACKAGE = 'mitmproxy-mcp==0.6.1'
LOCATIONS = {
    'codex': '.codex/config.toml',
    'grok': '.grok/config.toml',
    'claude': '.claude.json',
    'antigravity': '.gemini/config/mcp_config.json',
    'opencode': '.config/opencode/opencode.json',
}


def safe_path(path, home):
    path.relative_to(home)
    current = path
    while current != home.parent:
        if current.is_symlink():
            raise ValueError(f'目标含软链接，拒绝写入：{current}')
        current = current.parent


def render(text, owner, command, args):
    if owner in ('codex', 'grok'):
        pattern = re.compile(r'^\[mcp_servers\.(?:"mitmproxy-mcp"|mitmproxy-mcp)(?:\.|\])')
        sections = re.split(r'(?m)(?=^\[)', text)
        result = ''.join(section for section in sections if not pattern.match(section)).rstrip()
        result += '\n\n[mcp_servers."mitmproxy-mcp"]\n'
        result += 'command = ' + json.dumps(command) + '\n'
        result += 'args = ' + json.dumps(args) + '\n'
        result += 'enabled = true\nstartup_timeout_sec = 120\n'
        if owner == 'grok':
            cache = str(Path(args[1]) / 'uv-cache')
            result += '[mcp_servers."mitmproxy-mcp".env]\nUV_CACHE_DIR = ' + json.dumps(cache) + '\n'
            result += 'UV_TOOL_DIR = ' + json.dumps(str(Path(args[1]) / 'uv-tools')) + '\n'
        tomllib.loads(result)
        return result
    value = json.loads(text) if text else {}
    if owner == 'opencode':
        value.setdefault('mcp', {}).setdefault('servers', {})[NAME] = {
            'type': 'local', 'command': [command, *args], 'disabled': False,
        }
    else:
        value.setdefault('mcpServers', {})[NAME] = {
            'type': 'stdio', 'command': command, 'args': args,
        }
    return json.dumps(value, ensure_ascii=False, indent=2) + '\n'


def atomic_write(path, data):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir='/tmp', prefix='harness-' + path.name, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(data)
        temporary.chmod(0o600)
        temporary.replace(path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def setup(repo, home, selected=None, dry=False, offline=False):
    layout = json.loads((repo / '.harness.json').read_text())
    owners = [name for name in layout['selected'] if name in LOCATIONS]
    if len(owners) != 1:
        raise ValueError('仓库必须只负责一个 Harness')
    owner = owners[0]
    if selected is not None and owner not in selected:
        return
    path = home / LOCATIONS[owner]
    state = home / '.local/share/harness-mitmproxy' / owner
    if owner == 'grok':
        state = home / '.grok/runtime/mitmproxy'
    backup_root = home / '.harness-backups'
    for target in (path, state, backup_root):
        safe_path(target, home)
    command = shutil.which('uvx')
    if command is None and not (dry or offline):
        raise ValueError('缺少 uvx；请先安装 uv：https://docs.astral.sh/uv/getting-started/installation/')
    command = command or 'uvx'
    args = ['--directory', str(state), '--no-config', '--python', '3.13',
            '--with', 'mcp<2', '--from', PACKAGE, NAME]
    original = path.read_bytes() if path.exists() else None
    result = render(original.decode() if original is not None else '', owner, command, args).encode()
    if dry:
        print(f'配置预览：{owner} {NAME}（Python 3.13、{PACKAGE}、mcp<2）')
        return
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    state.chmod(0o700)
    if not offline:
        # Prime the shared uv cache and check imports before touching the client configuration.
        subprocess.run([command, *args, '--help'], check=True, timeout=300,
                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       env=dict(os.environ, UV_CACHE_DIR=str(state / 'uv-cache'), UV_TOOL_DIR=str(state / 'uv-tools')) if owner == 'grok' else None)
    if result == original:
        print(f'{owner}：{NAME} 配置已是最新')
        return
    if original is not None:
        backup = backup_root / ('mitmproxy-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
        backup_root.mkdir(parents=True, exist_ok=True, mode=0o700)
        backup.mkdir(mode=0o700)
        saved = backup / path.relative_to(home)
        saved.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        saved.write_bytes(original)
        saved.chmod(0o600)
    path.parent.mkdir(parents=True, exist_ok=True)
    atomic_write(path, result)
    print(f'{owner}：已接入 {NAME}' + ('（离线，未验证依赖）' if offline else ''))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--home', type=Path, default=Path.home())
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--offline', action='store_true')
    args = parser.parse_args()
    setup(Path(__file__).resolve().parents[1], args.home.absolute(), dry=args.dry_run, offline=args.offline)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(f'失败：{error}')
