#!/usr/bin/env python3
"""Verify and copy a portable public dependency bundle into this extraction."""
import hashlib
import json
import os
from pathlib import Path
from pathlib import PurePosixPath
import re
import stat
import sys
import tempfile

APP=Path(__file__).resolve().parents[1]
SQLCIPHER_SHA256='cd09126c9e85191f2b4f57e6c0bcd232c7481f56fb1d659b79374ccad21bfef9'
INPUT_DIRECTORIES={'pub-cache','maven-repository','maven-wrapper','native'}

def verify_inputs(inputs):
    """Validate the complete extracted inventory before touching destinations."""
    actual=set()
    def inventory(directory):
        with os.scandir(directory) as entries:
            for entry in entries:
                path=Path(entry.path)
                info=entry.stat(follow_symlinks=False)
                if stat.S_ISLNK(info.st_mode):raise ValueError('Input symlinks are forbidden')
                if stat.S_ISDIR(info.st_mode):
                    inventory(path)
                elif stat.S_ISREG(info.st_mode):
                    if info.st_nlink != 1:raise ValueError('Input hardlinks are forbidden')
                    actual.add(path.relative_to(inputs).as_posix())
                else:raise ValueError('Input special files are forbidden')
    if inputs.is_symlink() or not inputs.is_dir():raise ValueError('Inputs must be an ordinary directory')
    inventory(inputs)
    if 'manifest.json' not in actual:raise ValueError('Input manifest missing')
    manifest=json.loads((inputs/'manifest.json').read_text())
    if not isinstance(manifest,dict):raise ValueError('Invalid input manifest')
    files=manifest.get('files')
    if not isinstance(files,dict):raise ValueError('Invalid input manifest')
    for name,expected in files.items():
        if not isinstance(name,str):raise ValueError('Invalid manifest input path')
        path=PurePosixPath(name)
        if (not name or '\\' in name or '\0' in name or path.is_absolute()
                or '..' in path.parts or path.as_posix()!=name
                or len(path.parts)<2 or path.parts[0] not in INPUT_DIRECTORIES
                or (path.parts[0]=='native' and name!='native/libsqlcipher.x64.linux.so')
                or not isinstance(expected,str) or not re.fullmatch('[0-9a-f]{64}',expected)):
            raise ValueError('Invalid manifest input path or checksum')
    if actual != set(files)|{'manifest.json'}:
        raise ValueError('Input inventory does not match manifest')
    for name,expected in files.items():
        file=inputs/name
        with file.open('rb') as stream:actual_hash=hashlib.file_digest(stream,'sha256').hexdigest()
        if actual_hash!=expected:raise ValueError('Input checksum mismatch: '+name)
    native_name='native/libsqlcipher.x64.linux.so'
    if files.get(native_name)!=SQLCIPHER_SHA256:
        raise ValueError('Upstream SQLCipher hash mismatch')
    return files

def copy_verified(source,destination,expected):
    """Copy independent, hash-checked bytes; preserve required execute bits."""
    info=source.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        raise ValueError('Input changed after verification')
    destination.parent.mkdir(parents=True,exist_ok=True)
    temporary=None
    try:
        with source.open('rb') as original,tempfile.NamedTemporaryFile(dir=destination.parent,delete=False) as output:
            temporary=Path(output.name)
            digest=hashlib.sha256()
            while chunk:=original.read(2*1024*1024):
                digest.update(chunk);output.write(chunk)
        if digest.hexdigest()!=expected:raise ValueError('Input changed after verification')
        temporary.chmod(info.st_mode&0o777)
        os.replace(temporary,destination)
    finally:
        if temporary is not None:temporary.unlink(missing_ok=True)

def main():
    if len(sys.argv)!=2:raise SystemExit('Usage: prepare_offline.py <extracted-inputs-directory>')
    input_path=Path(sys.argv[1]).absolute()
    if input_path.is_symlink():raise ValueError('Input symlinks are forbidden')
    inputs=input_path.resolve(strict=True)
    files=verify_inputs(inputs)
    cache=Path(os.environ.get('PUB_CACHE',APP/'validation/pub-cache')).resolve()
    destinations={
        'pub-cache':cache,
        'maven-repository':APP/'validation/helper-maven-repository',
        'maven-wrapper':APP/'native/microsoft_auth_helper/target/wrapper',
    }
    for name,expected in sorted(files.items()):
        parts=PurePosixPath(name).parts
        if parts[0]=='native':
            target=APP/'.dart_tool/hooks_runner/shared/sqlite3/build/download-cd09126c/libsqlcipher.so'
        else:target=destinations[parts[0]].joinpath(*parts[1:])
        copy_verified(inputs/name,target,expected)
    print(f'Verified {len(files):,} dependency inputs plus one manifest; copied independent bytes. '
          'Set BUSYCARDS_MAVEN_REPOSITORY to validation/helper-maven-repository.')

if __name__=='__main__':main()
