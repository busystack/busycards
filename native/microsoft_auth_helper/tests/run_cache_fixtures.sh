#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -x "$1" ]; then
printf 'Usage: run_cache_fixtures.sh <published-or-packaged-helper>\n' >&2
  exit 64
fi
python3 native/microsoft_auth_helper/tests/run_missing_libsecret_fixture.py "$1"
busycards_fixture_root=$(mktemp -d ${TMPDIR:-/tmp}/busycards-msal-cache-fixtures.XXXXXX)
trap 'rm -rf -- "$busycards_fixture_root"' EXIT
mkdir -m 700 "$busycards_fixture_root/data" "$busycards_fixture_root/runtime" \
  "$busycards_fixture_root/config" "$busycards_fixture_root/cache"
export XDG_DATA_HOME="$busycards_fixture_root/data"
export XDG_RUNTIME_DIR="$busycards_fixture_root/runtime"
export XDG_CONFIG_HOME="$busycards_fixture_root/config"
export XDG_CACHE_HOME="$busycards_fixture_root/cache"
unset GNOME_KEYRING_CONTROL
unset DISPLAY WAYLAND_DISPLAY
helper=$(realpath "$1")
helper_root=$(dirname "$helper")
keytool -genkeypair -alias runtime -keyalg EC -groupname secp256r1 -validity 1 \
  -dname CN=localhost -ext SAN=dns:localhost \
  -storetype PKCS12 -keystore "$busycards_fixture_root/tls.p12" \
  -storepass synthetic-runtime-password -keypass synthetic-runtime-password \
  >/dev/null 2>&1
"$helper_root/microsoft-auth/runtime/bin/java" \
  -cp "$(realpath native/microsoft_auth_helper/target/test-classes):$helper_root/microsoft-auth/jars/*" \
  io.busystack.busycards.auth.RuntimeProbe "$busycards_fixture_root/tls.p12"
# A disposable D-Bus and keyring prevent fixture credentials from entering the
# desktop session. All values are synthetic and no provider requests are made.
dbus-run-session -- bash -euo pipefail -c '
  printf "%s" "synthetic-fixture-password" | gnome-keyring-daemon --unlock --components=secrets >/dev/null
  helper=$(realpath "$1")
  helper_root=$(dirname "$helper")
  # Runtime classes/jars are from the supplied distribution, not target/classes.
  "$helper_root/microsoft-auth/runtime/bin/java" --enable-native-access=ALL-UNNAMED \
    -cp "$2:$helper_root/microsoft-auth/jars/*" \
    io.busystack.busycards.auth.CacheFixtures "$helper"
' busycards-cache-fixtures "$1" "$(realpath native/microsoft_auth_helper/target/test-classes)"
