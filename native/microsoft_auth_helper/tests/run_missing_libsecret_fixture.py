#!/usr/bin/env python3
"""Hide libsecret inside a disposable mount namespace; never alter host libs."""
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

helper = str(Path(sys.argv[1]).resolve())
library = Path("/usr/lib/x86_64-linux-gnu/libsecret-1.so.0").resolve(strict=True)
with tempfile.TemporaryDirectory(prefix="busycards-missing-libsecret-") as temporary:
    root = Path(temporary)
    empty = root / "empty-library"
    empty.write_bytes(b"")
    for name in ("data", "config", "runtime", "cache"):
        (root / name).mkdir(mode=0o700)
    namespace = ["bwrap", "--ro-bind", "/", "/", "--bind", temporary, temporary,
                 "--ro-bind", str(empty), str(library), "--unshare-user",
                 "--unshare-pid", "--proc", "/proc", "--dev", "/dev"]
    env = dict(os.environ, XDG_DATA_HOME=str(root / "data"),
               XDG_CONFIG_HOME=str(root / "config"), XDG_CACHE_HOME=str(root / "cache"),
               XDG_RUNTIME_DIR=str(root / "runtime"),
               DBUS_SESSION_BUS_ADDRESS="unix:path=" + str(root / "absent-bus"))
    env.pop("GNOME_KEYRING_CONTROL", None)
    env.pop("DISPLAY", None)
    env.pop("WAYLAND_DISPLAY", None)
    hidden = subprocess.run(namespace + ["stat", "-c", "%s", str(library)],
                            env=env, capture_output=True, timeout=10, check=True)
    assert hidden.stdout.strip() == b"0"
    for method in ("version", "listAccounts"):
        request = json.dumps({"version": 1, "requestId": "missing-libsecret",
                              "method": method,
                              "clientId": "00000000-0000-0000-0000-000000000001"}).encode()
        result = subprocess.run(namespace + [helper],
                                input=struct.pack(">I", len(request)) + request,
                                env=env, capture_output=True, timeout=20)
        assert result.stderr == b"" and len(result.stdout) >= 4
        size, = struct.unpack(">I", result.stdout[:4])
        assert size == len(result.stdout) - 4
        response = json.loads(result.stdout[4:])
        assert response["requestId"] == "missing-libsecret" and response["version"] == 1
        if method == "version":
            assert result.returncode == 0 and response["ok"]
        else:
            assert result.returncode == 2 and response["error"]["code"] == "secure-storage-failed"
        print("PASS missing libsecret:", method)
    assert not any(p.name.endswith((".json", ".cache")) and p.stat().st_size
                   for p in (root / "data").rglob("*") if p.is_file())
    print("PASS no plaintext cache; host library unchanged")
