#!/usr/bin/env python3
"""Deterministic local source/release archives; no install or publication."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import tarfile

APP = Path(__file__).resolve().parents[1]
TARGETS = ('busystack_dav', 'busystack_graph', 'busystack_contacts', 'busycards')
EXCLUDED = {'.git', '.dart_tool', '.flutter-plugins-dependencies', 'build', 'validation', 'target', '__pycache__', '.idea', '.vscode'}
EPOCH = int(os.environ.get('SOURCE_DATE_EPOCH', '1790899200'))

def archive(destination, roots):
    with destination.open('wb') as raw, gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=EPOCH) as zipped:
        with tarfile.open(fileobj=zipped, mode='w') as tar:
            for root, prefix, source in roots:
                paths = [root]
                for directory, folders, files in os.walk(root, followlinks=False):
                    if source:
                        folders[:] = [name for name in folders if name not in EXCLUDED and name != 'ephemeral']
                    for name in folders + files:
                        if source and name in EXCLUDED:
                            continue
                        path = Path(directory) / name
                        if not source or path.suffix != '.pyc':
                            paths.append(path)
                for path in sorted(paths):
                    relative = path.relative_to(root)
                    if source and (EXCLUDED.intersection(relative.parts) or 'ephemeral' in relative.parts or path.suffix == '.pyc'):
                        continue
                    if path.is_symlink() and not path.resolve().is_relative_to(root):
                        raise ValueError('Archive symlink escapes target: ' + str(relative))
                    item = tar.gettarinfo(str(path), str(Path(prefix) / relative))
                    item.uid = item.gid = 0
                    item.uname = item.gname = ''
                    item.mtime = EPOCH
                    if item.isdir():
                        item.mode = 0o755
                    elif item.isfile():
                        item.mode = 0o755 if item.mode & 0o100 else 0o644
                    elif item.issym():
                        item.mode = 0o777
                    if item.isfile():
                        with path.open('rb') as stream:
                            tar.addfile(item, stream)
                    else:
                        tar.addfile(item)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--source-only', action='store_true');args=parser.parse_args()
    output=APP / 'validation/artifacts';output.mkdir(parents=True,exist_ok=True)
    roots=[]
    for name in TARGETS:
        root=APP.parent/name
        if root.is_symlink() or root.resolve().parent != APP.parent: raise ValueError('Invalid sibling layout')
        roots.append((root,name,True))
    source=output/'busycards-0.1.0-source.tar.gz';archive(source,roots)
    files=[source]
    portable=output/'busycards-0.1.0-offline-inputs.tar.gz'
    if portable.is_file(): files.append(portable)
    if not args.source_only:
        bundle=APP/'build/linux/x64/release/bundle'
        if not (bundle/'busycards').is_file() or not (bundle/'microsoft-auth/runtime/bin/java').is_file():
            raise ValueError('Build the release with its own helper/runtime first')
        release=output/'busycards-0.1.0-linux-x64.tar.gz';archive(release,[(bundle,'busycards-0.1.0',False)])
        files.append(release)
    manifest=[]
    for path in files:
        digest=hashlib.file_digest(path.open('rb'),'sha256').hexdigest()
        manifest.append({'file':path.name,'bytes':path.stat().st_size,'sha256':digest})
    (output/'manifest.json').write_text(json.dumps({'epoch':EPOCH,'artifacts':manifest},indent=2)+'\n')
    (output/'SHA256SUMS').write_text(''.join(item['sha256']+'  '+item['file']+'\n' for item in manifest))
    print(json.dumps(manifest))

if __name__=='__main__':main()
