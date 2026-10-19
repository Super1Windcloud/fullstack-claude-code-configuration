"""Install Testkit host dependencies and register MCP servers without starting device sessions."""
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tempfile


def read_json(path):
    return json.loads(path.read_text()) if path.exists() else {}


def toml_server(text, name, entry):
    pattern = re.compile(r'^\[mcp_servers\.(?:"' + re.escape(name) + r'"|' + re.escape(name) + r')(?:\.|\])')
    sections = re.split(r'(?m)(?=^\[)', text)
    text = ''.join(section for section in sections if not pattern.match(section))
    text += '\n[mcp_servers.' + json.dumps(name) + ']\n'
    for key in ('command', 'args', 'url'):
        if key in entry:
            text += key + ' = ' + json.dumps(entry[key], ensure_ascii=False) + '\n'
    if entry.get('env'):
        text += '[mcp_servers.' + json.dumps(name) + '.env]\n'
        for key, value in entry['env'].items():
            text += key + ' = ' + json.dumps(value, ensure_ascii=False) + '\n'
    return text


def setup(repo, home, selected, run, deploy, env, pending, failures, dry=False, offline=False, mode='full'):
    declaration = repo / 'runtime-dependencies.json'
    if not declaration.exists() or mode == 'none':
        return
    data = read_json(declaration)
    initial_failures = len(failures)
    owner = next((name for name in selected if name != 'antigravity-global'), 'antigravity')
    runtime = home / '.local/share/harness-testkit' / owner
    for directory in (runtime, runtime / 'node', runtime / 'venv', runtime / 'appium', runtime / 'browsers'):
        current = directory
        while current != home:
            if current.is_symlink():
                raise ValueError(f'运行环境目录含软链接，拒绝写入：{current}')
            current = current.parent
    python = runtime / 'venv/bin/python'
    npm_bin = runtime / 'node/node_modules/.bin'
    sdk = env.get('ANDROID_HOME') or env.get('ANDROID_SDK_ROOT')
    if not sdk:
        adb = shutil.which('adb', path=env.get('PATH'))
        if adb and (Path(adb).parent.parent / 'build-tools').exists():
            sdk = str(Path(adb).parent.parent)
        else:
            sdk = str(home / 'Library/Android/sdk')
    sdk_paths = [str(Path(sdk) / 'platform-tools'), str(Path(sdk) / 'cmdline-tools/latest/bin')]
    build_tools = sorted((Path(sdk) / 'build-tools').glob('*'), reverse=True)
    if build_tools:
        sdk_paths.append(str(build_tools[0]))
    own_env = {
        'PATH': os.pathsep.join([*sdk_paths, str(runtime / 'venv/bin'), str(npm_bin),
                                '/opt/homebrew/opt/llvm/bin', '/usr/local/opt/llvm/bin', env.get('PATH', '')]),
        'ANDROID_HOME': sdk,
        'ANDROID_SDK_ROOT': sdk,
        'APPIUM_HOME': str(runtime / 'appium'),
        'PLAYWRIGHT_BROWSERS_PATH': str(runtime / 'browsers'),
        'PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD': '1',
        'PUPPETEER_SKIP_DOWNLOAD': '1',
    }
    if mode == 'full':
        own_env['PUPPETEER_EXECUTABLE_PATH'] = str(runtime / 'chromium.sh')
    env.update(own_env)
    status = {'profile': mode, 'offline': offline, 'commands': [], 'failed': [], 'manual': data['manual']}

    def execute(command):
        status['commands'].append(list(map(str, command)))
        try:
            run(list(map(str, command)))
            return True
        except (OSError, subprocess.SubprocessError):
            label = ' '.join(map(str, command[:3]))
            failures.append(label)
            status['failed'].append(label)
            return False

    def write(path, value, executable=False):
        if dry:
            print('配置预览：' + str(path))
            return
        with tempfile.TemporaryDirectory(prefix='harness-runtime-config-') as temporary:
            source = Path(temporary) / path.name
            source.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n' if isinstance(value, dict) else value)
            source.chmod(0o755 if executable else 0o600)
            deploy(source, path)

    def which(command):
        return shutil.which(command, path=env['PATH'])

    if not offline:
        node = which('node')
        minimum = 24 if mode == 'full' else 20
        if node and not dry:
            version = subprocess.check_output([node, '--version'], text=True, timeout=15)
            if int(version.lstrip('v').split('.')[0]) < minimum:
                node = None
        npm = which('npm')
        if npm and not dry:
            npm_version = subprocess.check_output([npm, '--version'], text=True, timeout=15)
            if int(npm_version.split('.')[0]) < 10:
                npm = None
        if not node or not npm:
            if platform.system() == 'Darwin' and which('brew'):
                execute(['brew', 'install', 'node'])
                node_bin = Path(which('brew')).parent.parent / 'opt/node/bin'
                own_env['PATH'] = str(node_bin) + os.pathsep + own_env['PATH']
                env.update(own_env)
            else:
                failures.append(f'Node.js >= {minimum} 和 npm：请先安装')
        for tool in data['native']:
            if mode not in tool['profiles'] or which(tool['command']):
                continue
            if platform.system() == 'Darwin' and which('brew'):
                execute(['brew', 'install', *(['--cask'] if tool.get('cask') else []), tool['package']])
            else:
                label = f"系统依赖 {tool['command']}：缺少 Homebrew 或当前平台不支持自动安装"
                failures.append(label)
                status['failed'].append(label)

    if not offline and mode == 'full' and not which('aapt'):
        sdkmanager = which('sdkmanager')
        if sdkmanager or dry:
            execute([sdkmanager or 'sdkmanager', '--sdk_root=' + sdk, 'platform-tools',
                     'build-tools;' + data['android_build_tools']])
            own_env['PATH'] = str(Path(sdk) / 'build-tools' / data['android_build_tools']) + os.pathsep + own_env['PATH']
            env.update(own_env)
        else:
            failures.append('Android SDK build-tools：缺少 sdkmanager；需先准备命令行工具和 SDK 许可')

    if not dry:
        for name in ('package.json', 'package-lock.json'):
            deploy(repo / 'runtime' / mode / name, runtime / 'node' / name)
        deploy(repo / 'runtime' / mode / 'requirements.txt', runtime / 'requirements.txt')
    shell_env = '#!/usr/bin/env bash\n' + '\n'.join('export ' + key + '=' + shlex.quote(value) for key, value in own_env.items()) + '\n'
    write(runtime / 'env.sh', shell_env, executable=True)

    if offline:
        pending.append('Testkit 外部依赖：离线模式只登记 MCP 和环境配置，不下载依赖')
    else:
        if not python.exists():
            execute([sys.executable, '-m', 'venv', runtime / 'venv'])
        uv = which('uv')
        installer = [uv, 'pip', 'install', '--python', python] if uv else [python, '-m', 'pip', 'install']
        execute([*installer, '-r', runtime / 'requirements.txt'])
        execute([python, '-m', 'pip', 'check'])
        npm_ok = execute(['npm', '--prefix', runtime / 'node', 'ci', '--no-audit', '--no-fund'])
        if mode == 'full' and npm_ok:
            execute([npm_bin / 'playwright', 'install', 'chromium'])
            execute([npm_bin / 'agent-browser', 'install'])
            drivers = ['uiautomator2'] + (['xcuitest'] if platform.system() == 'Darwin' else [])
            for driver in drivers:
                package = 'appium-' + driver + '-driver'
                if not (runtime / 'appium/node_modules' / package / 'package.json').exists():
                    execute([npm_bin / 'appium', 'driver', 'install', driver])

    sdk = env.get('ANDROID_HOME') or env.get('ANDROID_SDK_ROOT')
    if not sdk:
        adb = which('adb')
        if adb and (Path(adb).parent.parent / 'build-tools').exists():
            sdk = str(Path(adb).parent.parent)
        elif (home / 'Library/Android/sdk').exists():
            sdk = str(home / 'Library/Android/sdk')
    mcp_env = dict(own_env)
    if sdk:
        mcp_env.update(ANDROID_HOME=sdk, ANDROID_SDK_ROOT=sdk)
        directories = sorted((Path(sdk) / 'build-tools').glob('*'), reverse=True)
        additions = [str(Path(sdk) / 'platform-tools')] + ([str(directories[0])] if directories else [])
        mcp_env['PATH'] = os.pathsep.join(additions + [own_env['PATH']])
    servers = {'mobile-mcp': {'command': str(npm_bin / 'mcp-server-mobile'), 'args': [], 'env': mcp_env}}
    if mode == 'full':
        # Use the installed Playwright browser revision instead of the MCP package's different revision.
        wrapper = runtime / 'playwright-mcp.sh'
        browser_api = runtime / 'node/node_modules/@playwright/test'
        script = '#!/usr/bin/env bash\nset -euo pipefail\nsource ' + shlex.quote(str(runtime / 'env.sh')) + '\n'
        script += 'BROWSER_PATH="$(node -e '\
                  + shlex.quote('console.log(require(process.argv[1]).chromium.executablePath())')\
                  + ' ' + shlex.quote(str(browser_api)) + ')"\n'
        prefix = script
        script += 'exec ' + shlex.quote(str(npm_bin / 'playwright-mcp')) + ' --executable-path "$BROWSER_PATH" "$@"\n'
        write(wrapper, script, executable=True)
        chromium = prefix + 'exec "$BROWSER_PATH" "$@"\n'
        write(runtime / 'chromium.sh', chromium, executable=True)
        servers['playwright'] = {'command': str(wrapper), 'args': [], 'env': mcp_env}
    if 'codex' in selected:
        path = home / '.codex/config.toml'
        text = path.read_text() if path.exists() else ''
        for name, entry in servers.items():
            text = toml_server(text, name, entry)
        write(path, text)
    if 'claude' in selected:
        # Both normal HOME discovery and an explicit CLAUDE_CONFIG_DIR are supported.
        for path in (home / '.claude.json', home / '.claude/.claude.json'):
            value = read_json(path)
            value.setdefault('mcpServers', {}).update(servers)
            write(path, value)
    if 'antigravity' in selected or 'antigravity-global' in selected:
        path = home / '.gemini/config/mcp_config.json'
        value = read_json(path)
        value.setdefault('mcpServers', {}).update(servers)
        write(path, value)
    if 'opencode' in selected:
        path = home / '.config/opencode/opencode.json'
        value = read_json(path)
        for name, entry in servers.items():
            value.setdefault('mcp', {})[name] = {'type': 'local', 'command': [entry['command'], *entry['args']],
                                                'environment': entry['env'], 'enabled': True}
        value.setdefault('mcp', {})['figma'] = {'type': 'remote', 'url': 'https://mcp.figma.com/mcp', 'enabled': True}
        write(path, value)

    guides = {'codex': '.codex/AGENTS.md', 'claude': '.claude/CLAUDE.md',
              'antigravity': '.gemini/config/GEMINI.md', 'opencode': '.config/opencode/AGENTS.md'}
    start, end = '<!-- harness-testkit-runtime:start -->', '<!-- harness-testkit-runtime:end -->'
    for name, relative in guides.items():
        if name not in selected:
            continue
        path = home / relative
        original = path.read_text() if path.exists() else ''
        original = re.sub(re.escape(start) + r'.*?' + re.escape(end), '', original, flags=re.S).rstrip()
        block = f'\n\n{start}\n执行 Testkit 工具前先 `source {runtime}/env.sh`；Python 使用 `{python}`。\n运行环境只代表工具已准备；设备授权、Xcode/WDA 签名、Midscene 模型凭据和 Figma OAuth 仍按本机实际状态检查。\n{end}\n'
        write(path, original + block)
    pending.extend(data['manual'])
    status['failed'] = list(dict.fromkeys(failures[initial_failures:]))
    write(runtime / 'installation-report.json', status)
    print('Testkit 依赖配置：' + mode + '；运行报告：' + str(runtime / 'installation-report.json'))
