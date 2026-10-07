#!/usr/bin/env python3
"""Create the deterministic, hash-inventoried public dependency bundle."""

import gzip
import hashlib
import json
import os
from pathlib import Path
import stat
import tarfile
import tempfile


APP = Path(__file__).resolve().parents[1]
EPOCH = int(os.environ.get("SOURCE_DATE_EPOCH", "1790899200"))
SQLCIPHER_SHA256 = (
    "cd09126c9e85191f2b4f57e6c0bcd232c7481f56fb1d659b79374ccad21bfef9"
)


def regular_files(root: Path) -> list[Path]:
    if root.is_symlink() or not root.is_dir():
        raise ValueError(f"Dependency input directory is unavailable: {root}")
    result = []
    for directory, folders, files in os.walk(root, followlinks=False):
        folders.sort()
        files.sort()
        for name in folders:
            path = Path(directory) / name
            if path.is_symlink():
                raise ValueError(f"Dependency input symlink is forbidden: {path}")
        for name in files:
            path = Path(directory) / name
            info = path.stat(follow_symlinks=False)
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                raise ValueError(f"Dependency input must be one regular file: {path}")
            result.append(path)
    return result


def add_directory(archive: tarfile.TarFile, name: str) -> None:
    item = tarfile.TarInfo(name)
    item.type = tarfile.DIRTYPE
    item.mode = 0o755
    item.mtime = EPOCH
    item.uid = item.gid = 0
    item.uname = item.gname = ""
    archive.addfile(item)


def add_file(archive: tarfile.TarFile, source: Path, name: str) -> None:
    item = archive.gettarinfo(str(source), name)
    if not item.isfile():
        raise ValueError(f"Dependency input must be a regular file: {source}")
    item.uid = item.gid = 0
    item.uname = item.gname = ""
    item.mtime = EPOCH
    item.mode = 0o755 if source.stat().st_mode & 0o111 else 0o644
    with source.open("rb") as stream:
        archive.addfile(item, stream)


def main() -> None:
    pub_cache = Path(os.environ.get("PUB_CACHE", APP / "validation/pub-cache"))
    inputs = {
        "pub-cache/hosted": pub_cache / "hosted",
        "pub-cache/hosted-hashes": pub_cache / "hosted-hashes",
        "maven-repository": APP / "validation/helper-maven-repository",
        "maven-wrapper": APP / "native/microsoft_auth_helper/target/wrapper",
    }
    native = (
        APP
        / ".dart_tool/hooks_runner/shared/sqlite3/build/"
        "download-cd09126c/libsqlcipher.so"
    )
    if hashlib.sha256(native.read_bytes()).hexdigest() != SQLCIPHER_SHA256:
        raise ValueError("Upstream SQLCipher hash mismatch")

    inventory: dict[str, str] = {}
    members: list[tuple[Path, str]] = []
    for prefix, root in inputs.items():
        for source in regular_files(root):
            name = str(Path(prefix) / source.relative_to(root))
            inventory[name] = hashlib.sha256(source.read_bytes()).hexdigest()
            members.append((source, name))
    native_name = "native/libsqlcipher.x64.linux.so"
    inventory[native_name] = SQLCIPHER_SHA256
    members.append((native, native_name))

    output = APP / "validation/artifacts"
    temporary_root = APP / "validation/tmp"
    output.mkdir(parents=True, exist_ok=True)
    temporary_root.mkdir(parents=True, exist_ok=True)
    destination = output / "busycards-0.1.0-offline-inputs.tar.gz"
    with tempfile.TemporaryDirectory(dir=temporary_root) as temporary:
        temporary_path = Path(temporary)
        manifest = temporary_path / "manifest.json"
        pending_archive = temporary_path / destination.name
        manifest.write_text(
            json.dumps({"schema": 1, "files": inventory}, indent=2) + "\n"
        )
        with pending_archive.open("wb") as raw, gzip.GzipFile(
            filename="", mode="wb", fileobj=raw, mtime=EPOCH
        ) as zipped, tarfile.open(fileobj=zipped, mode="w") as archive:
            directories = {"inputs"}
            for _, name in members:
                parts = Path("inputs", name).parts
                directories.update(
                    str(Path(*parts[:index]))
                    for index in range(2, len(parts))
                )
            for name in sorted(directories):
                add_directory(archive, name)
            add_file(archive, manifest, "inputs/manifest.json")
            for source, name in sorted(members, key=lambda value: value[1]):
                add_file(archive, source, str(Path("inputs") / name))
        digest = hashlib.sha256(pending_archive.read_bytes()).hexdigest()
        size = pending_archive.stat().st_size
        os.replace(pending_archive, destination)
    print(
        json.dumps(
            {
                "file": destination.name,
                "inputs": len(inventory),
                "bytes": size,
                "sha256": digest,
            }
        )
    )


if __name__ == "__main__":
    main()
