#!/usr/bin/env python3
"""Read-only donor audit. Writes only BusyCards validation evidence."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'busycards' / 'validation' / 'baselines'
DONORS = ('busymax', 'busybox', 'busyfiles')

def git(path, *args):
    env = dict(os.environ, GIT_OPTIONAL_LOCKS='0')
    result = subprocess.run(['git', '--no-optional-locks', '-C', str(path), *args],
                            env=env, capture_output=True, text=True)
    return {'exit': result.returncode, 'output': result.stdout,
            'error': result.stderr}

def snapshot(name):
    path = ROOT / name
    files = {}
    for directory, dirs, names in os.walk(path, followlinks=False):
        for name_ in sorted(dirs + names):
            item = Path(directory) / name_
            s = item.lstat()
            entry = {'mode': stat.S_IMODE(s.st_mode), 'kind': stat.S_IFMT(s.st_mode)}
            if stat.S_ISLNK(s.st_mode):
                entry['link'] = os.readlink(item)
            elif stat.S_ISREG(s.st_mode):
                digest = hashlib.sha256()
                fd = os.open(item, os.O_RDONLY | os.O_NOFOLLOW)
                with os.fdopen(fd, 'rb') as stream:
                    for block in iter(lambda: stream.read(1024 * 1024), b''):
                        digest.update(block)
                entry.update(size=s.st_size, sha256=digest.hexdigest())
                after = item.lstat()
                if (s.st_size, s.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
                    raise RuntimeError(f'Concurrent write while hashing: {item}')
            files[str(item.relative_to(path))] = entry
    return {'name': name, 'utc': datetime.now(timezone.utc).isoformat(),
            'head': git(path, 'rev-parse', 'HEAD'),
            'branch': git(path, 'symbolic-ref', '--short', 'HEAD'),
            'status': git(path, 'status', '--porcelain=v2', '--untracked-files=all', '--ignored'),
            'files': files}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('label')
    args = parser.parse_args()
    if not args.label.replace('-', '').replace('_', '').isalnum():
        parser.error('Label must contain letters, digits, hyphens, underscores')
    OUT.mkdir(parents=True, exist_ok=True)
    changed = False
    for name in DONORS:
        current = snapshot(name)
        target = OUT / f'{name}-{args.label}.json'
        if target.exists():
            raise RuntimeError(f'Refusing to overwrite evidence: {target}')
        target.write_text(json.dumps(current, sort_keys=True, separators=(',', ':')) + '\n')
        initial = OUT / f'{name}-before.json'
        differences = []
        if args.label != 'before':
            old = json.loads(initial.read_text())
            for key in sorted(old['files'].keys() | current['files'].keys()):
                if old['files'].get(key) != current['files'].get(key):
                    differences.append(key)
            for key in ('head', 'branch', 'status'):
                if old[key] != current[key]:
                    differences.append('git:' + key)
            (OUT / f'{name}-{args.label}-differences.json').write_text(json.dumps(differences, indent=2) + '\n')
        changed |= bool(differences)
        print(json.dumps({'donor': name, 'entries': len(current['files']),
                          'head': current['head']['output'].strip(),
                          'branch': current['branch']['output'].strip(),
                          'differences': len(differences)}), flush=True)
    raise SystemExit(2 if changed else 0)

if __name__ == '__main__':
    main()
