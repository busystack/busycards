#!/usr/bin/env bash
set -euo pipefail
helper=$(realpath "$1")
dist=$(dirname "$helper")
test -x "$dist/microsoft-auth/runtime/bin/java"
test -s "$dist/microsoft-auth/jars/busycards-microsoft-auth.jar"
(cd "$dist" && sha256sum --check --quiet distribution.sha256)
if find "$dist" -type f \( -name '*.dll' -o -name '*.pdb' -o -name '*.cs' -o -name '*.dart' -o -name '*.class' -o -name '*.deps.json' -o -name '*.runtimeconfig.json' \) | read -r forbidden; then
  printf 'Unexpected delivered source/debug/.NET payload.\n' >&2; exit 1
fi
for binary in "$dist/microsoft-auth/runtime/bin/java" "$dist/microsoft-auth/runtime/lib/server/libjvm.so"; do
  if ldd "$binary" | rg 'not found'; then exit 1; fi
  if readelf -d "$binary" | rg 'RPATH|RUNPATH' | rg '/home/|/tmp/|/snap/'; then exit 1; fi
done
if rg -a -l '/home/albert/|/home/runner/work/|/tmp/busycards-|CRAFT_PART_(BUILD|SRC|INSTALL)' "$dist/microsoft-auth/runtime"; then
  printf 'Build-host path leaked into delivered runtime.\n' >&2; exit 1
fi
temporary=$(mktemp -d "${TMPDIR:-/tmp}/busycards-java-relocation.XXXXXX")
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1])" "$temporary"' EXIT
cp -a "$helper" "$dist/distribution.sha256" "$dist/microsoft-auth" "$temporary/"
"$temporary/microsoft-auth/runtime/bin/java" --version
python3 - "$temporary/busycards-microsoft-auth" <<'PY'
import json, pathlib, struct, subprocess, sys, zipfile
helper = pathlib.Path(sys.argv[1])
expected_jars = {line.split('  ', 1)[1] for line in (helper.parent/'microsoft-auth/dependency-checksums.sha256').read_text().splitlines()}
expected_jars.add('busycards-microsoft-auth.jar')
assert {p.name for p in (helper.parent/'microsoft-auth/jars').glob('*.jar')} == expected_jars, 'Unexpected or missing runtime dependency'
request = json.dumps({'version': 1, 'requestId': 'relocation', 'method': 'version'}).encode()
result = subprocess.run([str(helper)], input=struct.pack('>I', len(request))+request, capture_output=True, timeout=15)
assert result.returncode == 0 and result.stderr == b''
size, = struct.unpack('>I', result.stdout[:4])
assert size == len(result.stdout)-4
response = json.loads(result.stdout[4:])
assert response['ok'] and response['requestId'] == 'relocation' and response['result']['version'] == 1
for jar in (helper.parent/'microsoft-auth/jars').glob('*.jar'):
    with zipfile.ZipFile(jar) as archive:
        for name in archive.namelist():
            assert not name.endswith(('.java', '.cs', '.dart', '.pdb')), 'Source/debug entry in jar'
            if name.endswith('.dll'):
                # The checksum-pinned JNA dependency carries its upstream JNI
                # resources. These are native libraries, not the retired CLR.
                assert jar.name == 'jna-5.19.1.jar' and name.endswith('/jnidispatch.dll')
            assert not name.startswith('io/busystack/busycards/auth/CacheFixtures')
            assert not name.startswith('io/busystack/busycards/auth/MsalFlowTest')
            assert not name.startswith('io/busystack/busycards/auth/RuntimeProbe')
            for test_class in ('CacheWorker', 'InitializationWorker', 'InitializationTest', 'SecureCacheTest', 'ProtocolTest'):
                assert not name.startswith('io/busystack/busycards/auth/' + test_class), 'Fixture class in runtime jar'
            data = archive.read(name)
            assert b'synthetic-refresh' not in data and b'synthetic-access-' not in data, 'Fixture secret in jar'
            assert b'/home/albert/' not in data and b'/tmp/busycards-' not in data, 'Build-host path in jar'
PY
printf 'Java helper distribution checks passed.\n'
