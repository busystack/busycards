# Milestone 2 final local results

Date: **2026-10-06**, Ubuntu host, Flutter 3.47.5 / Dart 3.13.4. Commands used
explicit repository working directories and workspace-backed temporary storage
where `/tmp` quota was insufficient. Provider fixtures used synthetic data; no
live account, registration or remote resource was used.

## Shared packages and BusyCards

`python3 tool/verify.py --output-dir validation/milestone-2/final-verify-online`
from BusyCards ran 34 commands in 312.144 seconds with zero failures. Its logs
and machine-readable results are under the named directory (generated evidence,
excluded from source archives).

| Gate | Result |
|---|---|
| `busystack_dav` locked resolution / format / analyze / test / example | pass; 74 tests |
| `busystack_graph` locked resolution / format / analyze / test / example | pass; 44 tests |
| `busystack_contacts` locked resolution / format / analyze / test / example | pass; 95 tests |
| BusyCards locked resolution / localization / format / analyze / full standard Flutter suite | pass; 183 tests |
| Maven helper verify, packaged-helper protocol and release path | pass |
| SQLCipher store contract | pass; 50,000 records, 1,020 checks, restart/wrong-key/rollback/concurrency, 45,326,336-byte sampled RSS growth |
| 512 MiB Graph/DAV download/upload stream contract | pass; largest sampled RSS growth 21,090,304 bytes |
| Linux debug/release builds, metadata and native CTest | pass; 3 native tests |
| positive helper cache/Secret Service fixture | pass; real MSAL4J portable-cache isolation, concurrent processes and removal, with no plaintext fallback |

The first offline verifier attempt recorded cache misses for DAV `uuid 4.6.0`
and Maven artifacts. The capable online run populated only public locked inputs
and then passed completely. A real release remained alive for the full
10-second isolated X11/DBus smoke and was terminated by the test timeout
(exit 124); Impeller and accessibility services initialized. Portal prompt
warnings occurred because Xvfb has no user session. No screenshot utility or
Wayland compositor is installed, so this is startup evidence, not rendered
parity.

Fresh source testing then found and corrected two packaging-only defects. The
offline archive had still contained UUID 4.5.2, so deterministic input
regeneration is now part of normal packaging; two consecutive generations
produced the same archive hash. The clean-tree verifier also built the Java
helper after a Flutter test that needs it, so helper verification/distribution
now precedes the Flutter suite. From the corrected clean extraction, all package
gates, 183 Flutter tests, store/stream contracts, both Linux builds, metadata
and native tests passed. The final helper-cache command initially exceeded the
Unix socket path limit under the deeply nested extraction; using its intended
short disposable `/tmp` socket base passed all positive and negative keyring
assertions. The exact final source archive was then re-extracted: gzip safety,
18,364-input checksum import, all package gates and BusyCards enforced locked
resolution pass.

The final Linux archive has 109 distribution-manifest entries, all checksum
verified; executable modes, helper handshake, desktop/AppStream metadata and
dynamic-library resolution pass. Its AOT library retains one generated
`dart_plugin_registrant.dart` diagnostic URI containing the build prefix; no
loader or runtime resource resolves through that prefix, so no cross-prefix
byte-identity claim is made.

## BusyBox

- `flutter pub get --enforce-lockfile`: pass after intentionally resolving the
  direct DAV edge and `uuid 4.6.0` in `pubspec.lock`.
- `tool/test-build-release.sh`: pass.
- Focused contacts/Graph/auth/storage/composer/settings command: **162 passed**.
- The complete suite before the final one-line test-harness correction reached
  **1,126 passed, 3 existing skips, 1 failure**. The failure was an existing
  mailbox UI test tapping an off-screen `Continue` text; no provider callback
  ran. Adding the same `ensureVisible` step used elsewhere made that isolated
  test pass. The entire 4m49s suite was not repeated after this test-only fix;
  all integration-focused tests were repeated and pass.
- Deterministic source archive rebuilt after the lock correction; fresh
  extraction resolves with `--enforce-lockfile --offline`.

## BusyFiles

- Pinned Dart 3.13.4 analysis of `busyfiles_provider_nextcloud`: pass.
- `dart test --concurrency=1 packages/busyfiles_provider_nextcloud/test`:
  **100 passed, 1 live-server case skipped**. This exercises streamed shared
  transport, large upload backpressure, multistatus completion, SEARCH and
  file-ID recovery through the actual provider.
- `scripts/verify.sh` completed source/presentation checks, then stopped with
  exit 69 because `actionlint`, `rpmbuild` and `rpm2cpio` are absent. The
  host does support Bubblewrap namespaces.
- `scripts/flutter-busyfiles --version` correctly refused to use stock Flutter:
  no isolated `BUSYFILES_ENGINE_SRC_PATH` is present. No corrected-engine
  build, Debian/RPM release qualification or native Wayland payload pass is
  claimed.
- Source archive creation and fresh sibling-layout locked resolution pass.

## BusyMax

- Locked resolution, analysis and platform-boundary check: pass.
- Focused final suites: contacts 5; calendar/To Do Graph 45; Google OAuth 32;
  Microsoft OAuth 33; Android authorization 18; Linux attendee editor 80;
  Windows attendee preservation 17; DAV 345; native attachment 43;
  localization 36; task details 83; Android/cloud-sharing 109.
- The complete suite reached **3,440 passed, 10 existing skips, 2 failures**;
  both failures were workflow-contract assertions after the new source artifact
  temporarily replaced the existing Snap artifact. The workflow was corrected
  to retain both artifacts and that complete workflow test file then passed
  **4/4**. The entire approximately eight-minute suite was not repeated after
  this YAML-only correction.
- Whole-repository non-mutating format reports 246 pre-existing/unrelated
  unformatted files. Touched implementation files were formatted. A broad
  unrelated rewrite was not made, so the repository-wide formatting gate
  remains open.
- Source archive creation and fresh sibling-layout locked resolution pass.
  Windows and Android builds/packaging were not executed on this Linux host.

## Unavailable or unauthorized gates

No live Google People, Microsoft Graph, CardDAV, CalDAV or Nextcloud resource
was authorized. No OAuth application was registered or published. There is no
Wayland compositor, screenshot tool, Windows host, Android SDK/device acceptance
session or physical IME matrix. BusyCards rendered visual comparison, BusyFiles
corrected-engine release qualification, BusyMax Windows/Android packaging and
all live-provider gates therefore remain explicitly unverified.
