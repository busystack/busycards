#!/usr/bin/env python3
"""Verify exactly the four new sibling targets. Never discover a root workspace."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

APP = Path(__file__).resolve().parents[1]
NAMES = ('busystack_dav', 'busystack_graph', 'busystack_contacts', 'busycards')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--offline', action='store_true')
    parser.add_argument('--packages-only', action='store_true')
    parser.add_argument('--flutter', default=os.environ.get('FLUTTER', 'flutter'))
    parser.add_argument('--output-dir', default='validation/commands',
        help='Evidence directory below this application\'s validation directory')
    args = parser.parse_args()
    flutter = Path(shutil.which(args.flutter) or args.flutter).resolve(strict=True)
    dart = flutter.parent / 'cache/dart-sdk/bin/dart'
    if not dart.is_file():
        parser.error('Supply the Flutter SDK bin/flutter executable')
    targets = {name: (APP.parent / name).resolve(strict=True) for name in NAMES}
    for name, directory in targets.items():
        if directory.name != name or directory.parent != APP.parent or directory.is_symlink():
            parser.error('Targets must be independent ordinary sibling directories')
        if not (directory / 'pubspec.yaml').read_text().startswith('name: ' + name + '\n'):
            parser.error('Unexpected package identity: ' + name)
    output = (APP / args.output_dir).resolve()
    if not output.is_relative_to((APP / 'validation').resolve()):
        parser.error('Command evidence must remain below BusyCards validation/')
    output.mkdir(parents=True, exist_ok=True)
    (APP / 'validation/tmp').mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, TMPDIR=str(APP / 'validation/tmp'))
    env.setdefault('PUB_CACHE', str(APP / 'validation/pub-cache'))
    results = []
    def run(label, name, command):
        if name not in targets:
            raise ValueError('Unauthorized command target')
        log = output / (label + '.log')
        start = datetime.now(timezone.utc)
        with log.open('w') as stream:
            try:
                completed = subprocess.run([str(x) for x in command], cwd=targets[name], env=env,
                    stdout=stream, stderr=subprocess.STDOUT, timeout=1800)
                code = completed.returncode
            except (OSError, subprocess.TimeoutExpired) as error:
                stream.write(str(error) + '\n')
                code = 124 if isinstance(error, subprocess.TimeoutExpired) else 127
        results.append({'label': label, 'target': name, 'command': [str(x) for x in command],
            'exit': code, 'startedUtc': start.isoformat(), 'elapsedSeconds': (datetime.now(timezone.utc)-start).total_seconds(),
            'log': str(log.relative_to(APP))})
        print(label + ': exit ' + str(code), flush=True)
        (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    resolution = ['pub', 'get', '--enforce-lockfile'] + (['--offline'] if args.offline else [])
    run('official-sdk', 'busycards', [sys.executable, 'tool/verify_upstream_packages.py', '--sdk', flutter.parent.parent, '--sdk-only'])
    if results[-1]['exit']:
        return 1
    run('toolchain', 'busycards', [flutter, '--version'])
    for name in NAMES[:3]:
        run(name + '-pub', name, [dart, *resolution])
        run(name + '-format', name, [dart, 'format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'example'])
        run(name + '-analyze', name, [dart, 'analyze'])
        run(name + '-test', name, [dart, 'test', '--reporter', 'expanded'])
        run(name + '-example', name, [dart, 'run', 'example/main.dart'])
    if not args.packages_only:
        run('offline-input-contract', 'busycards', [sys.executable, '-W', 'error::ResourceWarning', 'tool/test_prepare_offline.py', '-v'])
        run('busycards-pub', 'busycards', [flutter, *resolution])
        run('official-dependencies', 'busycards', [sys.executable, 'tool/verify_upstream_packages.py', '--sdk', flutter.parent.parent])
        if results[-1]['exit']:
            return 1
        run('official-dependency-tests', 'busycards', [sys.executable, '-m', 'unittest', 'discover', '-s', 'tool', '-p', 'test_upstream_packages.py'])
        run('localization', 'busycards', [flutter, 'gen-l10n'])
        run('busycards-format', 'busycards', [dart, 'format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'tool'])
        run('busycards-analyze', 'busycards', [flutter, 'analyze', '--no-pub'])
        helper = './native/microsoft_auth_helper/mvnw'
        # Java does not use TMPDIR for Files.createTempDirectory. Forward its
        # explicit system property to Maven/Surefire, including fresh builds.
        maven = ['-B', '-Djava.io.tmpdir=' + str(APP / 'validation/tmp')] + (['-o'] if args.offline else [])
        run('helper-verify', 'busycards', [helper, *maven, 'verify'])
        # Produce a reviewable artifact even when an independent online audit or
        # platform test gate is unavailable. This does not make verify pass.
        run('helper-artifact', 'busycards', [helper, *maven, '-DskipTests', 'package', 'dependency:tree', 'exec:exec@runtime-distribution'])
        run('helper-protocol', 'busycards', [dart, 'run', 'tool/helper_protocol_contract.dart', 'native/microsoft_auth_helper/target/dist/busycards-microsoft-auth'])
        # The standard Flutter suite includes lifecycle tests against the
        # packaged helper, so a clean extraction must build it first.
        # Serialize encrypted-store/helper fixtures to avoid competing with
        # widget animation polling within the existing real-time timeouts.
        run('busycards-test', 'busycards', [flutter, 'test', '--no-pub', '--reporter=expanded', '--concurrency=1'])
        run('store-contract', 'busycards', [dart, 'run', 'tool/store_contract.dart', '50000'])
        run('stream-contract', 'busycards', [dart, 'run', 'tool/stream_contract.dart'])
        for mode in ('debug', 'release'):
            run('linux-' + mode, 'busycards', [flutter, 'build', 'linux', '--' + mode, '--no-pub'])
        run('helper-release-path', 'busycards', [dart, 'run', 'tool/helper_release_path_contract.dart', 'build/linux/x64/release/bundle'])
        run('desktop-metadata', 'busycards', ['desktop-file-validate', 'linux/io.busystack.busycards.desktop'])
        run('appstream-metadata', 'busycards', ['appstreamcli', 'validate', '--no-net', 'linux/io.busystack.busycards.metainfo.xml'])
        run('native-tests', 'busycards', ['dbus-run-session', '--', 'xvfb-run', '-a', 'ctest', '--test-dir', 'build/linux/x64/debug', '--output-on-failure'])
        # This fixture creates D-Bus/Secret Service Unix sockets. Keep its
        # disposable socket path below the platform limit even when the source
        # archive is extracted under a deeply nested directory.
        run('helper-cache', 'busycards', ['env', 'TMPDIR=/tmp', 'bash', 'native/microsoft_auth_helper/tests/run_cache_fixtures.sh', 'native/microsoft_auth_helper/target/dist/busycards-microsoft-auth'])
    return 1 if any(item['exit'] for item in results) else 0

if __name__ == '__main__':
    sys.exit(main())
