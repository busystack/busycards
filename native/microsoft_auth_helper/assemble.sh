#!/usr/bin/env bash
set -euo pipefail
module_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
selected_jdk="$1"
dist="$module_dir/target/dist"
test -x "$selected_jdk/bin/jlink"
mkdir -p "$dist/microsoft-auth/jars"
install -m755 "$module_dir/launcher" "$dist/busycards-microsoft-auth"
install -m644 "$module_dir/target/busycards-microsoft-auth.jar" "$dist/microsoft-auth/jars/"
(cd "$dist/microsoft-auth/jars" && sha256sum --check --quiet "$module_dir/dependency-checksums.sha256")
if test -d "$dist/microsoft-auth/runtime"; then
  mv "$dist/microsoft-auth/runtime" "$module_dir/target/runtime-previous-$(date +%s%N)"
fi
mkdir -p "$module_dir/target/jlink-tmp"
"$selected_jdk/bin/jlink" -J-Djava.io.tmpdir="$module_dir/target/jlink-tmp" \
  --limit-modules java.base,java.desktop,java.net.http,java.management,java.naming,java.security.jgss,jdk.httpserver,jdk.crypto.ec,jdk.unsupported,jdk.naming.dns,jdk.localedata,jdk.charsets \
  --add-modules java.base,java.desktop,java.net.http,java.management,java.naming,java.security.jgss,jdk.httpserver,jdk.crypto.ec,jdk.unsupported,jdk.naming.dns,jdk.localedata,jdk.charsets \
  --bind-services --strip-debug --no-header-files --no-man-pages \
  --output "$dist/microsoft-auth/runtime"
cp "$module_dir/target/dependency-graph.txt" "$dist/microsoft-auth/dependency-graph.txt"
cp "$module_dir/dependency-checksums.sha256" "$dist/microsoft-auth/dependency-checksums.sha256"
cp "$module_dir/licenses/BusyCards-LICENSE.txt" "$dist/microsoft-auth/LICENSE"
mkdir -p "$dist/microsoft-auth/licenses"
cp "$module_dir/licenses/"*.txt "$dist/microsoft-auth/licenses/"
cd "$dist"
find busycards-microsoft-auth microsoft-auth -type f -print0 | sort -z | xargs -0 sha256sum > distribution.sha256
bash "$module_dir/tests/test_distribution.sh" "$dist/busycards-microsoft-auth"
