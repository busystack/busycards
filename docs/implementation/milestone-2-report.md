# Milestone 2 corrective implementation and acceptance

Final lifecycle corrections C1–C3, including the C2 preparation-failure follow-up, **11 October 2026**. This report supersedes the
6 October status, preserved beside it as dated historical documents. The
seven repositories remain independent. Application databases, credentials,
authentication, UI and lifecycle remain application-owned. BusyFiles has no
contacts functionality. No external account, OAuth registration, push,
publication or installation over an owner's application was performed.

This follow-up newly builds BusyMax source/Linux/symbol payloads and an actual evidence archive. It builds no current Android or BusyBox Snap payload. The successor delivery guide, manifest and checksums are under `.m2-correction/delivery/c2-preparation-final`; byte-identical inspectable payloads are included in `docs/implementation/delivery/c2-preparation`. Historical Android/Snap successes remain tied to their original source revisions.


## C2 preparation-failure follow-up — 11 October 2026

The reviewed `40b3ab6c` preparation removed the in-memory provider before its mutation journal and disabled-account transactions. A rolled-back write left the durable account enabled but `changed` null, so recovery skipped rebinding. The new deterministic BEFORE/AFTER SQL-trigger regression fails in all four Google/Microsoft cases with `account-not-connected` on ordinary synchronization. Parent deletion and credentials remain healthy.

The existing removal receipt now records original account/binding state and partial detachment separately from a committed disable. `changed` is set after the awaited store transaction commits. Recovery retains C1 ordering and checks ownership, parent identity/grants/authorization generation and exact contact state; it finishes existing uncertain-mutation journal handling before restoring the prior binding. A failed journal recovery retains pending/uncertain work, exposes `contacts-removal-recovery-required`, blocks replay and returns the original preparation failure. No consent, permission upgrade, credential copying, unconditional enabled repair, production timeout or shared-package change was added.

BusyMax commit `788e8a8e4be563eecddc45f8f783e02e315ae0e2`; tree `bba83dd5c534ab05ed1c28a24d85de22942821a2`; complete final suite **3,579 passed / 10 existing live-provider skips / zero failures**. The 67-case lifecycle suite and 345 focused authorization/contacts/database/shutdown cases pass. Touched-file format, analysis and platform-boundary checks pass. Exact commands, initial HEAD, stable file fingerprints, exits, counts and log hashes are in machine results.

Fresh corrected-source Linux release/debug builds, the workflow GTK bridge integration test, native clock/weekday/GTK checks, registration-helper and registration-reader tests, desktop/AppStream metadata and runtime asset checks pass. The corrected release and normal debug application each start and close with exit 0 under private Xvfb/default and explicitly requested Mesa rendering, after schedule startup settles. Exact binary/asset hashes and captures are delivered. These checks do not qualify physical drivers or complete interactive Wayland comparison. Historical reference debug default/Mesa exit 139 remains failed/unresolved despite later passing exact-binary retests.

The affected contract was checked against resolved Drift 2.35.0 and its [transaction guidance](https://drift.simonbinder.eu/dart_api/transactions/): awaited SQL transaction completion determines durable success; rollback does not restore an in-memory provider binding. Existing provider/OAuth references are unchanged.

| Current receipt | Exit | Log in delivered archive |
|---|---:|---|
| `busymax-c2-preparation-red` | 1 | `current/commands/busymax-c2-preparation-red.log` |
| `busymax-c2-preparation-red-observed` | 1 | `current/commands/busymax-c2-preparation-red-observed.log` |
| `busymax-locked-prerequisites-complete` | 0 | `current/commands/busymax-locked-prerequisites-complete.log` |
| `busymax-c2-preparation-green` | 0 | `current/commands/busymax-c2-preparation-green.log` |
| `busymax-c2-format-analysis-platform` | 1 | `current/commands/busymax-c2-format-analysis-platform.log` |
| `busymax-c2-focused` | 0 | `current/commands/busymax-c2-focused.log` |
| `busymax-c2-final-checks` | 0 | `current/commands/busymax-c2-final-checks.log` |
| `busymax-c2-sdk-contract` | 0 | `current/commands/busymax-c2-sdk-contract.log` |
| `busymax-locked-prerequisites` | 1 | `current/commands/busymax-locked-prerequisites.log` |
| `busymax-c2-source-archive` | 1 | `current/commands/busymax-c2-source-archive.log` |
| `busymax-c2-fresh-prerequisites` | 1 | `current/commands/busymax-c2-fresh-prerequisites.log` |
| `busymax-c2-full-captured-final` | 0 | `current/commands/busymax-c2-full-captured-final.log` |
| `busymax-c2-source-archive-final` | 0 | `current/commands/busymax-c2-source-archive-final.log` |
| `busymax-c2-fresh-prerequisites-final` | 0 | `current/commands/busymax-c2-fresh-prerequisites-final.log` |
| `busymax-c2-linux-fresh-final` | 1 | `current/commands/busymax-c2-linux-fresh-final.log` |
| `busymax-c2-linux-fresh-verified` | 1 | `current/commands/busymax-c2-linux-fresh-verified.log` |
| `busymax-c2-release-archive` | 0 | `current/commands/busymax-c2-release-archive.log` |
| `busymax-c2-linux-fresh-completed` | 0 | `current/commands/busymax-c2-linux-fresh-completed.log` |
| `busymax-c2-symbols-archive` | 0 | `current/commands/busymax-c2-symbols-archive.log` |
| `busymax-c2-candidate-release-default-settled` | 241 | `current/commands/busymax-c2-candidate-release-default-settled.log` |
| `busymax-c2-candidate-release-default-settled-captured` | 0 | `current/commands/busymax-c2-candidate-release-default-settled-captured.log` |
| `busymax-c2-candidate-release-mesa-settled-captured` | 0 | `current/commands/busymax-c2-candidate-release-mesa-settled-captured.log` |
| `busymax-c2-candidate-debug-default-settled-captured` | 0 | `current/commands/busymax-c2-candidate-debug-default-settled-captured.log` |
| `busymax-c2-candidate-debug-mesa-settled-captured` | 0 | `current/commands/busymax-c2-candidate-debug-mesa-settled-captured.log` |

The initial complete suite reported 3,579 passes / ten skips, but its wrapper exited 143 before sealing the subprocess result. That interrupted receipt is retained and is not used as a zero-exit gate; a captured final run supplies the authoritative result. The pre-build location guard initially refused a localization output directory created by fresh generation. A follow-up harness attempt exposed a shadowed Python import. Both failed before application build; the harness was corrected and those task-owned generated prerequisites preserved on the private temporary filesystem. The initial native-close QA job was terminal-stopped in `stty size` before launching the application; the stopped task-owned job was explicitly terminated, and corrected capture runs use noninteractive stdin. This was not an observed app or driver crash. Pre-commit source/fresh-prerequisite packaging attempts were rejected before artifact creation while commit eligibility remained unsealed; final committed-source packaging passes. The first test compile error and test-only lint findings remain recorded, followed by corrected passing gates. The isolated SDK bootstrap was interrupted once after a clone timestamp mismatch; exact pinned cache metadata was restored. No shared SDK/driver/runtime was changed. The Android cache probe still lacks a resolvable AGP 4.1.0 POM/closure; no repeated unavailable-prerequisite Gradle run or current Android package is claimed. BusyBox Snap remains blocked at its prior GNOME SDK install failure; BusyBox is unchanged.

## Historical 10 October C1–C3 verification (exact tested inputs)

| Item | Root cause and changed production boundary | Final regression outcome |
|---|---|---|
| C1 | Parent removal held authorization serialization while its contacts hook awaited enrollment queued behind that same boundary. Browser cancellation could not interrupt the later persistence await. Claim one removal attempt synchronously, fence and invalidate enrollment, capture identity/generation under serialization, release it to cancel/drain, then reacquire and validate before coherent removal. No serialization, cleanup, staged rollback or late-write validation was detached or bypassed. No production timeout was added. | Actual repository/controller/hooks, desktop broker, Google/Microsoft OAuth services and one AuthorizationPersistence; real Drift store; only external provider/secret interactions mocked. Deterministic removal-boundary pauses, already-granted/fresh consent, before/after staging, coalescing/fence, reversible failure, replacement generation, unrelated account and shutdown. Durable account/credential/contact absence and denied stale commits asserted. Passing complete final affected suite; receipts below. |
| C2 | Preparation disabled only enabled contacts, while failure recovery enabled any surviving disabled linked account without recording what that removal attempt changed. The same removal receipt owns its changed contact row, parent identity, authorization generation and recovery authority. Recovery compares the exact changed row/generation and parent authorization state; newer disable/removal/replacement revokes authority. Only complete reversible rollback can restore. Retained journals, committed removal and successful remote revocation cannot restore. | Actual parent removal with enabled/disabled/absent contacts; Google/Microsoft secret-store and database failures; runtime binding and whether provider synchronization was scheduled; successful/irreversible removal; newer user/account/authorization changes while recovery waits; real file-database restart. Originally disabled/absent contacts remain so; unrelated accounts remain usable. Passing complete final affected suite; receipts below. |
| C3 | The initial account read preceded completion cleanup inside putIfAbsent, leaving its failed future in _synchronizing and poisoning later manual/scheduled attempts. The entire operation, including initial read, enters try/catch/finally. Active work coalesces; completion removes only its own entry. Explicit callers retain the original failure, scheduled observers report it, and status updates require a captured valid generation. Initial failure cannot invent a record or overwrite status. | Real controller and Drift store with an interceptor failing exactly the target account initial read. First original error, shared active future, later discovery/provider success, manual/scheduled observation, second account, overlapping cancellation/removal, durable absence and shutdown asserted. Contacts cleanup leaves the mail database open; filtering and post-commit notifications retained. Passing complete final affected suite; receipts below. |

Google/Microsoft fresh-consent positive regressions also exposed the omitted parent grant metadata and qualified Graph contacts grants. The existing OAuth commit now stores returned parent grants and contacts atomically; the contacts adapter stores its expected scope names. Candidate validation, identity, authorization generation and registration binding remain at the actual persistence boundary. Shared packages and pins are unchanged.

| Complete corrected gate | Committed tested content | Actual result |
|---|---|---|
| busymax `flutter test --no-pub --reporter expanded --concurrency 2` | `40b3ab6c89fe30cf8580be61ab0f44eb60a99788`; tree `86ed99acc0b8c866513259b5e3224648507584cb` | 3,559 passed; 10 existing skips; exit 0. |
| busybox `flutter test --no-pub --reporter expanded --concurrency 1` | `5aeba272bde4f6798fadaa394c037e8b7aaf74e6`; tree `83584bf02e4d6d0638ce4057b8b812aef060906c` | 1,186 passed; 3 existing skips; exit 0. |

Complete-suite receipts record the live initial HEAD plus the corrected uncommitted tree fingerprint. After explicit staging/commit, the same file-union fingerprint proves the delivered commit has exactly the tested content. No source change followed the passing full gates.

BusyMax: 47 lifecycle cases and 325 focused authorization/removal/enrollment/database cases passed. BusyBox: 15 final storage/controller cases passed; its broader 186-case focused run had one existing helper-gated skip. Final touched-file formatting, analysis and BusyMax platform-boundary checks pass. Exact locked/generation prerequisites were run and their hashes remain identical. The existing provider references and current [Dart Future documentation](https://api.dart.dev/dart-async/Future-class.html) and [Drift transaction guidance](https://drift.simonbinder.eu/dart_api/transactions/) were checked only for the asynchronous-operation and transaction contracts affected here.

The first complete runs remain visible: BusyMax 3,558 passed / 10 skipped / one DAV fixture failure; BusyBox 1,185 passed / 3 skipped / one migration-startup fixture failure. Neither was counted as a passing gate. The diagnosed fixture corrections are: An early timeout could leave a delayed response fault unconsumed; the following drop request received its empty 207. A zero-deadline probe reproduced the same failure on reviewed production. A separate FakeDavServer for the timeout stage passes that probe and all four original real-socket cases; original assertions/deadline retained. No DAV package/production change. Dart/native-hook startup alone took 20.576589 seconds, exceeding the existing migration readiness deadline before database work. The test helper now marks startup; the test separately bounds startup at one minute, retains the twenty-second preparation bound and original two-minute outer bound, then asserts the same durable phase/SIGKILL/restart integrity. All fifteen storage/controller cases pass. No storage production change.

BusyMax’s ten skips are explicitly opt-in live Nextcloud/iCloud/login/sharing/restart cases; no disposable live accounts or registrations were authorized. BusyBox’s three standard skips are the separately gated encrypted performance run and two real-MSAL-helper opt-in cases. Historical standard/helper/positive Secret Service/encrypted-store evidence remains attached to its tested inputs; current packaged helper checks are separate receipts.

| Receipt | Exact command (cwd in machine receipt) | Exit | Actual log |
|---|---|---:|---|
| `max-baseline-deadlock-observed` | `timeout --signal=TERM --kill-after=5s 60s flutter test --no-pub --reporter expanded test/contacts/parent_removal_lifecycle_test.dart --plain-name 'BusyProvider.google already granted enrollment queued behind removal drains'` | 1 | `.m2-correction/lifecycle/logs/max-baseline-deadlock-observed.log` |
| `max-baseline-c2-red` | `timeout 45s flutter test --no-pub --reporter expanded --plain-name reversible test/contacts/parent_removal_lifecycle_test.dart` | 1 | `.m2-correction/lifecycle/logs/max-baseline-c2-red.log` |
| `box-baseline-red-final` | `flutter test --no-pub --reporter expanded test/application/contacts_initial_read_failure_test.dart` | 1 | `.m2-correction/lifecycle/logs/box-baseline-red-final.log` |
| `max-fresh-positive-red` | `flutter test --no-pub --reporter expanded --plain-name 'fresh consent positive' test/contacts/parent_removal_lifecycle_test.dart` | 1 | `.m2-correction/lifecycle/logs/max-fresh-positive-red.log` |
| `max-recovery-authority-red` | `flutter test --no-pub --reporter expanded --plain-name 'incomplete credential rollback' test/contacts/parent_removal_lifecycle_test.dart` | 1 | `.m2-correction/lifecycle/logs/max-recovery-authority-red.log` |
| `max-recovery-final` | `flutter test --no-pub --reporter expanded test/contacts/parent_removal_lifecycle_test.dart` | 0 | `.m2-correction/lifecycle/logs/max-recovery-final.log` |
| `max-focused-final-tree` | `flutter test --no-pub --reporter expanded test/contacts test/core/auth/authorization_transition_test.dart test/google_tasks/oauth test/microsoft_todo/oauth test/features/auth/data test/features/sync/account_sync_operations_test.dart test/db` | 0 | `.m2-correction/lifecycle/logs/max-focused-final-tree.log` |
| `box-focused` | `flutter test --no-pub --reporter expanded test/application/contacts_initial_read_failure_test.dart test/application/contacts_controller_test.dart test/application/contacts_enrollment_test.dart test/application/account_manager_removal_test.dart test/application/mail_runtime_shutdown_test.dart test/application/mailbox_application_shutdown_test.dart test/storage/contacts_store_test.dart test/storage/contacts_enrollment_migration_test.dart test/auth` | 0 | `.m2-correction/lifecycle/logs/box-focused.log` |
| `box-storage-controller-final-green` | `flutter test --no-pub --reporter expanded --concurrency 1 test/storage/encrypted_database_test.dart test/application/contacts_initial_read_failure_test.dart` | 0 | `.m2-correction/lifecycle/logs/box-storage-controller-final-green.log` |
| `max-dav-fixture-early-timeout-red` | `flutter test --no-pub --reporter expanded test/dav/fake_dav_server_integration_test.dart --plain-name 'status, per-resource, malformed, invalid-token, delay, and drop matrix'` | 1 | `.m2-correction/lifecycle/logs/max-dav-fixture-early-timeout-red.log` |
| `max-dav-fixture-early-timeout-green` | `flutter test --no-pub --reporter expanded test/dav/fake_dav_server_integration_test.dart --plain-name 'status, per-resource, malformed, invalid-token, delay, and drop matrix'` | 0 | `.m2-correction/lifecycle/logs/max-dav-fixture-early-timeout-green.log` |
| `max-dav-fixture-final-green` | `flutter test --no-pub --reporter expanded --concurrency 1 test/dav/fake_dav_server_integration_test.dart` | 0 | `.m2-correction/lifecycle/logs/max-dav-fixture-final-green.log` |
| `box-encrypted-storage-recheck` | `flutter test --no-pub --reporter expanded --concurrency 1 test/storage/encrypted_database_test.dart` | 1 | `.m2-correction/lifecycle/logs/box-encrypted-storage-recheck.log` |
| `box-migration-child-build-hooks-probe` | `dart run test/helpers/migration_crash_helper.dart` | 64 | `.m2-correction/lifecycle/logs/box-migration-child-build-hooks-probe.log` |
| `max-final-format-analysis-platform-v2` | `python3 /home/albert/busystack/.m2-correction/lifecycle/validate.py busymax --checks-only` | 0 | `.m2-correction/lifecycle/logs/max-final-format-analysis-platform-v2.log` |
| `box-final-format-analysis` | `python3 /home/albert/busystack/.m2-correction/lifecycle/validate.py busybox --checks-only` | 0 | `.m2-correction/lifecycle/logs/box-final-format-analysis.log` |
| `max-full-verified-sequential` | `flutter test --no-pub --reporter expanded --concurrency 2` | 0 | `.m2-correction/lifecycle/logs/max-full-verified-sequential.log` |
| `box-full-verified-sequential` | `flutter test --no-pub --reporter expanded --concurrency 1` | 0 | `.m2-correction/lifecycle/logs/box-full-verified-sequential.log` |
| `reference-debug-default-close` | `python3 /home/albert/busystack/.m2-correction/lifecycle/close_gate.py busymax /home/albert/busystack/.m2-correction/fresh/reference/busymax/build/linux/x64/debug/bundle/busymax reference-debug-default` | 64 | `.m2-correction/lifecycle/logs/reference-debug-default-close.log` |
| `reference-debug-default-close-reproduced` | `python3 /home/albert/busystack/.m2-correction/lifecycle/close_gate.py busymax /home/albert/busystack/.m2-correction/fresh/reference/busymax/build/linux/x64/debug/bundle/busymax reference-debug-default` | 64 | `.m2-correction/lifecycle/logs/reference-debug-default-close-reproduced.log` |
| `reference-debug-default-close-isolated` | `python3 /home/albert/busystack/.m2-correction/lifecycle/close_gate.py busymax /home/albert/busystack/.m2-correction/fresh/reference/busymax/build/linux/x64/debug/bundle/busymax reference-debug-default` | 0 | `.m2-correction/lifecycle/logs/reference-debug-default-close-isolated.log` |
| `reference-debug-mesa-close` | `python3 /home/albert/busystack/.m2-correction/lifecycle/close_gate.py busymax /home/albert/busystack/.m2-correction/fresh/reference/busymax/build/linux/x64/debug/bundle/busymax reference-debug-mesa` | 0 | `.m2-correction/lifecycle/logs/reference-debug-mesa-close.log` |
| `reference-debug-default-gdb` | `python3 /home/albert/busystack/.m2-correction/lifecycle/close_gate.py busymax /home/albert/busystack/.m2-correction/fresh/reference/busymax/build/linux/x64/debug/bundle/busymax reference-debug-default-gdb` | 0 | `.m2-correction/lifecycle/logs/reference-debug-default-gdb.log` |
| `source-final-busybox` | `python3 /home/albert/busystack/.m2-correction/lifecycle/artifacts.py source busybox` | 0 | `.m2-correction/lifecycle/logs/source-final-busybox.log` |
| `fresh-source-busybox-locks` | `flutter pub get --offline --enforce-lockfile` | 0 | `.m2-correction/lifecycle/logs/fresh-source-busybox-locks.log` |
| `source-final-busymax` | `python3 /home/albert/busystack/.m2-correction/lifecycle/artifacts.py source busymax` | 0 | `.m2-correction/lifecycle/logs/source-final-busymax.log` |
| `fresh-source-busymax-locks` | `flutter pub get --offline --enforce-lockfile` | 0 | `.m2-correction/lifecycle/logs/fresh-source-busymax-locks.log` |
| `box-linux-final` | `python3 /home/albert/busystack/.m2-correction/lifecycle/platforms.py busybox linux` | 1 | `.m2-correction/lifecycle/logs/box-linux-final.log` |
| `box-linux-final-isolated` | `python3 /home/albert/busystack/.m2-correction/lifecycle/platforms.py busybox linux` | 1 | `.m2-correction/lifecycle/logs/box-linux-final-isolated.log` |
| `box-linux-final-fresh` | `python3 /home/albert/busystack/.m2-correction/lifecycle/platforms.py busybox linux` | 1 | `.m2-correction/lifecycle/logs/box-linux-final-fresh.log` |
| `native-archive-busymax` | `python3 /home/albert/busystack/.m2-correction/lifecycle/artifacts.py native busymax` | 0 | `.m2-correction/lifecycle/logs/native-archive-busymax.log` |
| `max-linux-final` | `python3 /home/albert/busystack/.m2-correction/lifecycle/platforms.py busymax linux` | 0 | `.m2-correction/lifecycle/logs/max-linux-final.log` |
| `box-linux-final-completion` | `python3 /home/albert/busystack/.m2-correction/lifecycle/platforms.py busybox linux --resume-linux` | 0 | `.m2-correction/lifecycle/logs/box-linux-final-completion.log` |
| `native-archive-busybox` | `python3 /home/albert/busystack/.m2-correction/lifecycle/artifacts.py native busybox` | 0 | `.m2-correction/lifecycle/logs/native-archive-busybox.log` |
| `native-archive-busymax-symbols` | `python3 /home/albert/busystack/.m2-correction/lifecycle/artifacts.py symbols busymax` | 0 | `.m2-correction/lifecycle/logs/native-archive-busymax-symbols.log` |
| `native-archive-busybox-symbols` | `python3 /home/albert/busystack/.m2-correction/lifecycle/artifacts.py symbols busybox` | 0 | `.m2-correction/lifecycle/logs/native-archive-busybox-symbols.log` |
| `candidate-busymax-release-default` | `python3 /home/albert/busystack/.m2-correction/lifecycle/close_gate.py busymax /home/albert/busystack/.m2-correction/lifecycle/extracted/busymax-linux-x64/busymax-0.2.4/busymax candidate-release-default` | 0 | `.m2-correction/lifecycle/logs/candidate-busymax-release-default.log` |
| `candidate-busymax-release-mesa` | `python3 /home/albert/busystack/.m2-correction/lifecycle/close_gate.py busymax /home/albert/busystack/.m2-correction/lifecycle/extracted/busymax-linux-x64/busymax-0.2.4/busymax candidate-release-mesa` | 0 | `.m2-correction/lifecycle/logs/candidate-busymax-release-mesa.log` |
| `candidate-busymax-debug-default` | `python3 /home/albert/busystack/.m2-correction/lifecycle/close_gate.py busymax /home/albert/busystack/.m2-correction/lifecycle/extracted/busymax-source/busymax/build/linux/x64/debug/bundle/busymax candidate-debug-default` | 0 | `.m2-correction/lifecycle/logs/candidate-busymax-debug-default.log` |
| `candidate-busymax-debug-mesa` | `python3 /home/albert/busystack/.m2-correction/lifecycle/close_gate.py busymax /home/albert/busystack/.m2-correction/lifecycle/extracted/busymax-source/busymax/build/linux/x64/debug/bundle/busymax candidate-debug-mesa` | 0 | `.m2-correction/lifecycle/logs/candidate-busymax-debug-mesa.log` |
| `candidate-busybox-release-default` | `python3 /home/albert/busystack/.m2-correction/lifecycle/close_gate.py busybox /home/albert/busystack/.m2-correction/lifecycle/extracted/busybox-linux-x64/busybox-0.0.1/busybox-mail candidate-release-default` | 0 | `.m2-correction/lifecycle/logs/candidate-busybox-release-default.log` |
| `candidate-busybox-release-mesa` | `python3 /home/albert/busystack/.m2-correction/lifecycle/close_gate.py busybox /home/albert/busystack/.m2-correction/lifecycle/extracted/busybox-linux-x64/busybox-0.0.1/busybox-mail candidate-release-mesa` | 0 | `.m2-correction/lifecycle/logs/candidate-busybox-release-mesa.log` |
| `max-android-final-daemon-diagnostic` | `jstack -l 3358887` | 0 | `.m2-correction/lifecycle/logs/max-android-final-daemon-diagnostic.log` |
| `candidate-busybox-debug-default` | `python3 /home/albert/busystack/.m2-correction/lifecycle/close_gate.py busybox /home/albert/busystack/.m2-correction/lifecycle/extracted/busybox-source/busybox/build/linux/x64/debug/bundle/busybox-mail candidate-debug-default` | 0 | `.m2-correction/lifecycle/logs/candidate-busybox-debug-default.log` |
| `candidate-busybox-debug-mesa` | `python3 /home/albert/busystack/.m2-correction/lifecycle/close_gate.py busybox /home/albert/busystack/.m2-correction/lifecycle/extracted/busybox-source/busybox/build/linux/x64/debug/bundle/busybox-mail candidate-debug-mesa` | 0 | `.m2-correction/lifecycle/logs/candidate-busybox-debug-mesa.log` |
| `snap-final-build` | `python3 /home/albert/busystack/.m2-correction/lifecycle/snap_project.py` | 1 | `.m2-correction/lifecycle/logs/snap-final-build.log` |
| `max-android-final-current-download-diagnostic` | `jstack -l 3358887` | 0 | `.m2-correction/lifecycle/logs/max-android-final-current-download-diagnostic.log` |
| `candidate-busymax-release-default-settled` | `python3 /home/albert/busystack/.m2-correction/lifecycle/close_gate.py busymax /home/albert/busystack/.m2-correction/lifecycle/extracted/busymax-linux-x64/busymax-0.2.4/busymax candidate-release-default-settled` | 0 | `.m2-correction/lifecycle/logs/candidate-busymax-release-default-settled.log` |
| `snap-final-relay-conditional-check` | `curl --fail --silent --show-error --proxy http://10.33.34.1:33319 --connect-timeout 10 --max-time 60 -H 'If-Modified-Since: Thu, 10 Oct 2030 00:00:00 GMT' -o /dev/null -w 'HTTP %{http_code}\n' http://archive.ubuntu.com/ubuntu/dists/noble/InRelease` | 0 | `.m2-correction/lifecycle/logs/snap-final-relay-conditional-check.log` |
| `candidate-busymax-release-mesa-settled` | `python3 /home/albert/busystack/.m2-correction/lifecycle/close_gate.py busymax /home/albert/busystack/.m2-correction/lifecycle/extracted/busymax-linux-x64/busymax-0.2.4/busymax candidate-release-mesa-settled` | 0 | `.m2-correction/lifecycle/logs/candidate-busymax-release-mesa-settled.log` |
| `candidate-busymax-debug-default-settled` | `python3 /home/albert/busystack/.m2-correction/lifecycle/close_gate.py busymax /home/albert/busystack/.m2-correction/lifecycle/extracted/busymax-source/busymax/build/linux/x64/debug/bundle/busymax candidate-debug-default-settled` | 0 | `.m2-correction/lifecycle/logs/candidate-busymax-debug-default-settled.log` |
| `candidate-busymax-debug-mesa-settled` | `python3 /home/albert/busystack/.m2-correction/lifecycle/close_gate.py busymax /home/albert/busystack/.m2-correction/lifecycle/extracted/busymax-source/busymax/build/linux/x64/debug/bundle/busymax candidate-debug-mesa-settled` | 0 | `.m2-correction/lifecycle/logs/candidate-busymax-debug-mesa-settled.log` |
| `snap-final-relay-contracts` | `python3 /home/albert/busystack/.m2-correction/lifecycle/proxy_contract_test.py` | 0 | `.m2-correction/lifecycle/logs/snap-final-relay-contracts.log` |
| `reference-debug-default-close-settled` | `python3 /home/albert/busystack/.m2-correction/lifecycle/close_gate.py busymax /home/albert/busystack/.m2-correction/fresh/reference/busymax/build/linux/x64/debug/bundle/busymax reference-debug-default-settled` | 0 | `.m2-correction/lifecycle/logs/reference-debug-default-close-settled.log` |
| `reference-debug-mesa-close-settled` | `python3 /home/albert/busystack/.m2-correction/lifecycle/close_gate.py busymax /home/albert/busystack/.m2-correction/fresh/reference/busymax/build/linux/x64/debug/bundle/busymax reference-debug-mesa-settled` | 0 | `.m2-correction/lifecycle/logs/reference-debug-mesa-close-settled.log` |
| `snap-final-build-repaired-relay` | `python3 /home/albert/busystack/.m2-correction/lifecycle/snap_resume.py` | 143 | `.m2-correction/lifecycle/logs/snap-final-build-repaired-relay.log` |
| `max-android-final` | `python3 /home/albert/busystack/.m2-correction/lifecycle/platforms.py busymax android` | 1 | `.m2-correction/lifecycle/logs/max-android-final.log` |
| `max-android-final-cached` | `python3 /home/albert/busystack/.m2-correction/lifecycle/platforms.py busymax android` | 1 | `.m2-correction/lifecycle/logs/max-android-final-cached.log` |
| `max-android-final-primary-resolution` | `python3 /home/albert/busystack/.m2-correction/lifecycle/platforms.py busymax android` | 1 | `.m2-correction/lifecycle/logs/max-android-final-primary-resolution.log` |
| `max-android-final-scoped-download-diagnostic` | `python3 -c 'import subprocess,pathlib; p=pathlib.Path('"'"'/home/albert/busystack/.m2-correction/lifecycle/logs/android-scoped-daemon-stack.log'"'"'); x=subprocess.run(['"'"'jstack'"'"','"'"'3481436'"'"'],capture_output=True,text=True); p.write_text(x.stdout+x.stderr); print('"'"'stack bytes'"'"',p.stat().st_size); print('"'"'\n'"'"'.join(s for s in x.stdout.splitlines() if any(q in s for q in ['"'"'SocketDispatcher'"'"','"'"'SSLSocket'"'"','"'"'HttpClient'"'"','"'"'kotlin'"'"','"'"'RUNNABLE'"'"','"'"'BLOCKED'"'"']))[:6000]); raise SystemExit(x.returncode)'` | 0 | `.m2-correction/lifecycle/logs/max-android-final-scoped-download-diagnostic.log` |


Current packaging status: Corrected-tree Android native unit/lint and APK/AAB registration-mode rebuilds remain blocked before native tests by unavailable existing Gradle/plugin prerequisites: latest offline failure is system_theme com.android.tools.build:gradle:4.1.0. No dependency downgrade/change was made; no new Android payload is delivered. Earlier native/emulator/test-signed artifacts remain historical for their exact tested inputs.

Corrected-tree BusyBox standard core24 Snap rebuild failed before application compilation installing gnome-46-2404-sdk latest/stable (exit 1). Earlier public APT/Mesa download failures and relay repairs are retained. Public locked Pub inputs and signed Mesa build prerequisite were verified in the task-only container; they do not constitute a package pass. No new Snap is delivered; old package/review evidence remains historical.

The latest exact attempts are:

| Receipt | Exact command | Exit | Actual log |
|---|---|---:|---|
| `max-android-final-existing-plugin-boms` | `python3 /home/albert/busystack/.m2-correction/lifecycle/platforms.py busymax android` | 1 | `.m2-correction/lifecycle/logs/max-android-final-existing-plugin-boms.log` |
| `snap-final-build-signed-prerequisites` | `python3 /home/albert/busystack/.m2-correction/lifecycle/snap_resume.py` | 1 | `.m2-correction/lifecycle/logs/snap-final-build-signed-prerequisites.log` |

All public-prerequisite/cache/diagnostic commands and failed attempts are retained in the machine report; their success is not an Android or Snap application verification gate. The detailed Snapcraft logs are included as actual files. The task-only public relay is stopped and the read-only Mesa cache mount is absent after Snapcraft cleanup.

Every receipt carries start/end tree fingerprint, live HEAD, exact cwd/argv, duration, exit and log SHA256. Full current command records and commit/tree mappings are in `milestone-2-results.json` and the successor evidence archive. The prior archive was located and verified; the successor carries its actual historical entries plus current logs/receipts/captures/inventory. Delivery guide, manifest and checksums are under `.m2-correction/delivery/lifecycle-final`; original `.m2-correction/delivery/final` is preserved.

## Retained B1–B12 production paths

| Item | Root cause and changed production boundary | Regression and outcome |
|---|---|---|
| B1 | `ContactsDatabase._enqueue` began SQL transactions outside its completion handling; rollback could replace the primary error. The whole lifecycle now settles the operation and gate in `finally`, tracks successful BEGIN, preserves cleanup diagnostics and invalidates an unrecoverable connection. `_close` independently drains resources. | Actual SQLCipher adapter BEGIN/body/COMMIT/ROLLBACK injection, bounded operation/shutdown and subsequent-operation assertions in `test/storage/transaction_failure_test.dart`; encrypted restart, awaited isolation and rollback retained. Pass. |
| B2 | BusyMax reauthorization persisted an enabled replacement then disabled it through `disconnect`. `enableLinkedContacts`, staged authorization and `ContactsDirectory.detach` now preserve the working connection through consent, commit validated replacement scopes/generation, drain the old binding without disabling the replacement, and bind its generation. | Actual store/controller Google and Microsoft first enable, upgrade/reconnect, cancellation/wrong identity/partial grant/persistence failure, restart and sync in `test/contacts/contacts_enrollment_test.dart`. Pass. |
| B3 | BusyMax source preferences committed without publishing configuration changes; Settings detached writes. Both store operations and post-commit notifications now have a close boundary; Settings controls pending/error state and versions reloads. | Actual Settings switches, failed persistence rollback, immediate state, source eligibility and durable restart fixtures; no unrelated sync needed. Pass. |
| B4 | The actual Fluent Windows and Android Settings routes had no enrollment actions. Their native contacts panels now call the existing controller for linked Google/Microsoft read/write, reconnect/disable/remove/source selection and independent CardDAV/Nextcloud read/write setup. | Eight route-level backend/platform fixtures starting with no contacts; cancellation, enrollment, source selection, read-only state, write upgrade and removal. Pass. Native host results are separate below. |
| B5 | Attendee requests only fenced query text. All three production attendee controls now capture/revalidate query, selected account and eligible sources, subscribe to configuration changes and invalidate on selection/add/removal/disposal without deleting draft attendees. | Twenty-one actual Linux/Fluent/Android controls fixtures for visible/delayed A→B, selection, source disable/removal and disposal; original manual-entry/metadata/permission preservation suites retained. Pass. |
| B6 | `GraphClient.download` omitted ordinary confirmed-401 recovery used by `request`. Streaming now permits one ordinary recovery and one claims replay before payload, bounded across alternating rejection types. Cancellation, range/headers/account authorization and no replay after payload remain. | Seven direct streaming regressions; actual BusyMax calendar/To Do attachment caller fixtures; BusyBox integrated Graph mail/download/upload/security coverage in its complete final suite. Pass. |
| B7 | BusyMax detached sync failures were recorded but remained unobserved futures; cleanup could stop at a failed operation. `_launch`, per-account status generation and enrollment/sync ownership observe scheduled errors and drain on close, preserving awaitable manual failures. | Actual caller-zone scheduled offline/revoked failure, another successful account, manual error, removal/cancellation and shutdown fixtures. No uncaught scheduled error. Pass. |
| B8 | BusyBox reconstructed full replacement fields from one email/display name. `ContactBrowserDialog` builds patches from the full selected record and actual edits, preserves other values/native metadata and structured names, supports intentional clear, explicit new destination, read-only gates and dirty navigation. Save captures identity/destination/edit generation and mounted state. | Actual dialog/controller/shared Google/Microsoft/CardDAV serialized requests and durable results, repeated emails/labels/IDs/unknown parameters, unchanged Save, name/email-only edits, clear, dirty cancel/switch and close/selection during Save. Google structured-name input edits `givenName`, since `displayName` is output-only. Pass. |
| B9 | BusyBox treated every returned mutation as success and could create a fresh logical mutation after an unknown create. The editor captures `onStaged` journal ID before dispatch; only confirmed state is saved. Failed/conflict/unknown drafts persist and reopen, known retry uses its ID and uncertain writes reconcile before replay. | Returned validation/permission failure, retryable failure, conflict, timeout-after-dispatch, restart, repeated Save dispatch count and account disable/removal recovery tests. No new create while its logical create is unresolved. Pass. No exactly-once guarantee is claimed. |
| B10 | Independent DAV sources had no production mail association, editing-mode action or eligibility invalidation. Native Settings exposes separate association, suggestion preference and read/write mode, reconnect and lifecycle actions. Independent links unlink on parent removal; dependent OAuth accounts follow authorization ownership. | Actual Settings→CardDAV/Nextcloud discovery→scoped real composer suggestions, restart, read-only/write, reconnect/association/removal, preference failure, out-of-order loads and stale visible/delayed suggestions. Native shell workflow also exercised. Pass. |
| B11 | Enrollment lived outside account transition ownership; Google commit/restore minted fresh authority for stale staged results. `ContactsEnrollmentAuthority`, owned enrollment resources and staged original credential authority now fence identity/registration/tenant/generation throughout consent/commit/conditional rollback. Microsoft retains Java/MSAL and protected conditional cache stages. DAV partial durable commits retain recoverable credentials/state. | Real AccountManager/controller/store OAuth loopback/RSA fixtures and framed helper contract cover enable/upgrade/reconnect, cancellation/wrong/partial grant/store failure, removal after authorization, rollback versus newer credentials/removal, old refresh, close and DAV partial failures/restart. Java/helper and positive isolated Secret Service/cache fixtures pass. SQLite and Secret Service remain separate stores with staged recovery, not a claimed atomic transaction. |
| B12 | BusyBox scheduled/discovery failures lacked an explicit observer/status; store close could skip stream cleanup after failed `Future.wait`, with untracked link/preference writes. Controller owns enrollment and sync; every public store operation is tracked, rejects after closing starts, notifies only after durable success while open, and cleanup proceeds after failures. BusyMax uses the equivalent boundary. | Actual caller-zone controller failures, one failure plus one success, manual errors, failing transaction/link save close, writes-after-close, idempotent close and shared mail DB usability; source Settings errors/versioned reloads. Additive schema 10 preserves schema-8 upgrade and existing schema-9 mail/contact data. Pass. |

`ContactsDirectory.bind(accountGeneration:)` and its transaction checks fence
old work across replacement in all three consumers. `detach` is a provider
lifecycle operation; `disconnect` remains the explicit disabling operation.
Directory shutdown closes all providers even if one fails, retaining original
and additional diagnostics. The three ordinary shared packages and their real
consumers remain the only provider path.

## Additional defects found through acceptance

BusyCards native acceptance found a missing startup load of the GTK icon
catalogue and a one-pixel virtual row overflow with a CJK fallback font. The
startup loader and shared title/subtitle strut fix retain the inherited native
font, Yaru controls, virtualization and one GTK/libhandy application window and
one Flutter view; their regressions and the final standard suite pass.

Actual BusyMax Android release startup found resource shrinking removed the
notification drawable loaded dynamically by name. A narrow resource keep rule
and APK/AAB resource checks retain it; the old artifact fails the new check.
Final test-signed APK/AAB artifacts in transitional and user-owned registration
modes pass release/resource/16-KiB alignment/signature checks. The actual API-36
emulator now reaches the normal no-account shell and actual Settings contacts
section; CardDAV and Nextcloud read-only setup dialogs open and cancel. Backend
enrollment, source selection and attendee suggestions are covered by the actual
Android route widget fixtures; native emulator cancellation alone is not claimed
as provider enrollment. A system-UI ANR during the first boot and an earlier
test label mismatch remain recorded as failed progress attempts.

BusyFiles source-RPM qualification rejected the M2 source archive because it
correctly contained both the app and its declared DAV sibling. The verifier now
checks the app plus exactly the manifest-declared dependency root, pinned HEAD
and complete file bytes, rejecting corruption and extra roots/files. All 18
release-provenance tests pass, including a real source RPM and a binary RPM
masquerading as source. File providers, engine pins and runtime are unchanged.

BusyBox actual Snap compilation also exposed a sibling-layout path-sanitizer
call using the staging parent instead of the actual application root. The
production recipe now supplies `app_dir`; a regression executes that real
recipe command on a nested binary fixture and checks length-preserving removal
of the generated registrant URI. The existing unexpected-path rejection stays
strict. Its old recipe fails and the corrected recipe passes. Final Snap
qualification is recorded separately below.

## Historical B1–B12 verification

| Final complete gate | Tested revision | Actual outcome |
|---|---|---|
| BusyBox `flutter test --reporter=expanded` | `38ed8fed` | 1,184 passed; 3 existing skips; analysis clean. |
| BusyMax `flutter test --reporter=expanded` | `19c6cf3e` | 3,512 passed; 10 existing skips; analysis clean. |
| BusyFiles `scripts/verify.sh` through its attested engine wrapper | `14c2853c` | 1,790 Dart/Flutter cases passed; 26 existing skips; full analysis/source/native gates passed. |
| BusyCards `tool/verify.py --offline` (exactly four repositories) | `6518526c` plus packages below | Graph 51, DAV 74, contacts 99 and BusyCards 188 passed; locked resolution, non-mutating format/analysis, examples, encrypted store/stream, Java/helper/positive Secret Service, native CTest and Linux debug/release gates passed. |

At the historical revisions above, BusyBox additionally passes generation, helper Maven verification, packaged
protocol/runtime/cache checks, source/shell checks, release-script tests, native
CTest (5/5), Linux debug/release and its then-current-source Snap build. BusyMax Linux
debug/release/native GTK/locale/ASan and both Android release registration modes
pass. Available native/platform results remain distinct from widget fixtures.

BusyFiles final optimized portable/DEB/RPM packages and source RPM pass the
unmodified provenance, metadata, hash and repeated-format reproducibility
checks. All three package formats pass X11 and real GNOME Wayland window
lifecycle acceptance in both close orders. Real private LocalSearch and standard
1,000/10,000/100,000-entry packaged scale checks pass with no diagnostic deadline
override. Final DEB install/reinstall/socket activation/purge/remove passes in
a disposable Ubuntu 26.04 container; final RPM lifecycle passes in a disposable
Fedora 44 container. The official final gate validates their exact common
source/engine/package identities. Earlier disk, harness-root, private-host-bus,
missing Fedora `lsb_release`, and Fedora `udisks2` hardware-uevent scriptlet
failures remain recorded. The failed dependency transaction was not counted as
a pass; the task app was removed separately, runtime prerequisites retained,
and the unchanged app lifecycle then passed. The earlier final-tree Wayland
focus failure under concurrent work is retained alongside the serialized full
verifier pass.

The accompanying `m2-corrective-evidence` bundle records acceptance commands,
cwd, tested HEAD/tree fingerprint, duration, exit status and log SHA-256. Two
early progress labels were reused and their first logs were overwritten;
`progress-log-integrity.json` discloses those gaps. Final gate logs use unique
labels and match their recorded hashes. Other progress failures, environment
failures and explicitly terminated task runs remain visible. Focused tests, standard complete
suites, native builds, positive credential fixtures and rendered controls are
distinct evidence. Existing skips remain existing skips.

In the historical B1–B12 verification, only task-owned Dart files were formatted. BusyMax's whole-tree formatting
check reports 236 pre-existing files, verified byte-identical to its original
HEAD; BusyBox's whole-tree command found two ignored stale Snap-generated
files. Source formatting checks and `git diff --check` pass. SDK, Dart, Java,
MSAL and dependency pins remain unchanged. The private toolchain is Flutter
3.47.5, Dart 3.13.4 and Temurin Java 25.0.1; BusyFiles uses the existing attested
engine inputs through its own wrapper, not stock Flutter.

## Historical native, rendered and independent layout acceptance

BusyCards native X11 acceptance covers selection/edit, keyboard search,
Unicode clipboard copy/paste, dirty close/cancel/save, a real GTK file chooser,
Settings and actual permission-error/conflict recovery. Matching Yaru light at
100%, Yaru dark at 200%, and HighContrast/increased text/reduced motion captures
cover ordinary/maximized/narrow/wide windows and selected/focused controls. The
reference includes empty and synthetic populated calendar/task states, modal
details/cancel and Settings under the same configurations. The accompanying
rendered comparison index links the actual captures; it is a representative
matrix, not an exhaustive Cartesian or physical-interaction claim.

BusyBox native shell acceptance starts with no contact sources, creates local
fixture DAV through actual Settings, selects a mail association, browses
read-only, explicitly enables editing, protects/cancels dirty close, confirms a
save and opens the actual composer with scoped suggestions. Twenty-three actual
editor/provider/durable-store fixtures and actual Settings→CardDAV/Nextcloud→
composer routes separately prove details beyond that native run. Cards Wayland
accessible controls and owned widget paint readbacks pass; the reference's full
interactive Wayland comparison remains open below.

Each application builds in a fresh layout containing only itself and declared
source dependencies, with private data/credential namespaces and no dependency
on another app's installed helper. Final source extractions use locked offline
resolution; BusyBox/Cards build their own helpers from public inputs. BusyFiles
also builds UI/daemon against a fresh private extraction of the checksummed
exported attested engine. Actual default native Box/Max/Cards startup and native
close are verified in empty private HOME/XDG/Secret Service; Files runs every
packaged format independently. Report-only source differences are checked
separately from tested runtime implementation. Default independent Xvfb runs
select the installed Mesa ICD/software renderer without changing SDK/runtime
pins. Exact historical reference debug SHA256 562040d069a3e6d75d2966dcf7099f51265fcc70b82fa9d7769ae8870cb3b9f8 at recorded source revision 8151130a560025aade0acd1ceb03f9a1abcec6cd retested: default, Mesa/software and default under gdb exit 0; additional default/Mesa attempts after schedule startup settled also exit 0. Full preserved bundle inventory is in reference-build-identity.json. Earlier default and Mesa exit139 remains failed/unresolved. Recorded crashing thread was io.flutter.io in LLVM MachineRegisterInfo::addRegOperandToUseList; main concurrently unloaded NVIDIA EGL. A sole cause is not established; no SDK/driver changes or forced software workaround shipped. Current candidate debug/release results are recorded separately in the lifecycle receipts; local Xvfb close does not qualify physical hardware.


Post-fix measurements: the 50,000-record real encrypted Cards harness performs
500 sync pages in 19,347 ms, browse in 7,467 µs, search median 15,999 µs/p95
20,454 µs, with 46,596,096-byte RSS growth and 1,020 checks. The actual migrated
Nextcloud provider streams 128 MiB in 1.609 s (32 chunks; headers 0.243 s),
18,644,992-byte RSS growth, bounded server progress during consumer pause, and
explicit cancellation after 4,128,715 bytes without replay. Files packaged
Wayland first usable time is 3.520/2.782/6.220 s at 1,000/10,000/100,000 fixture
entries. These are historical local synthetic measurements, not live-provider timings
or portable performance guarantees.

The rendered BusyCards reference is an isolated copy of BusyMax HEAD
`8151130a560025aade0acd1ceb03f9a1abcec6cd` and its exact original dependencies.
Matching GTK theme/font/scale runs capture ordinary, maximized, narrow and wide
actual managed windows. The reference uses its normal no-account shell and a second run with synthetic
calendar/task data seeded into its isolated application database. BusyCards
uses synthetic local CardDAV through its production runtime/store and native
shell. Screenshots are actual X11 captures; Wayland captures are
owned GTK widget paint readbacks and accessible controls, separately labelled.
No pixel identity, exhaustive physical interaction, live provider success or
byte-identical Flutter AOT is inferred from source similarity.

## Precise open gates

Exact historical reference debug SHA256 562040d069a3e6d75d2966dcf7099f51265fcc70b82fa9d7769ae8870cb3b9f8 at recorded source revision 8151130a560025aade0acd1ceb03f9a1abcec6cd retested: default, Mesa/software and default under gdb exit 0; additional default/Mesa attempts after schedule startup settled also exit 0. Full preserved bundle inventory is in reference-build-identity.json. Earlier default and Mesa exit139 remains failed/unresolved. Recorded crashing thread was io.flutter.io in LLVM MachineRegisterInfo::addRegOperandToUseList; main concurrently unloaded NVIDIA EGL. A sole cause is not established; no SDK/driver changes or forced software workaround shipped.

The full reference Wayland Settings/keyboard/clipboard/native-chooser rendered
comparison has not passed: real reference startup/initial owned paint is
available, but its accessible menu/keyboard automation did not reach Settings.
Cards owned Wayland paint/control checks are not compositor screenshots or
physical keyboard/clipboard/file-dialog acceptance. A capable interactive
Wayland comparison session and the remaining exhaustive rendered matrix are
still required; X11 evidence does not substitute for them.

The historical official Snap review reported 51 informational checks OK, no
warnings, and one existing D-Bus slot declaration requiring human store review
(`busybox-dbus`, `deny-connection` constraint), exit 2. For that historical package, build, contents/security,
resquash checksum and actual packaged helper/positive cache fixtures pass.
Store review/publication and strict installed Snap confinement acceptance are
not claimed; no store declaration was registered and no owner Snap was installed
or replaced.

No disposable external provider accounts or registrations were authorized;
Google/Microsoft/live CardDAV/Nextcloud acceptance remains blocked on those
resources. Deterministic local server/provider fixtures do not replace it.
Windows native builds require a Windows host; the actual Fluent route and
attendee controls compile and pass widget regressions on this host. Android
emulator acceptance does not certify a physical device or production signing.

## Provenance, commits and delivery

| Repository | Final tested implementation revision |
|---|---|
| busybox | `5aeba272bde4f6798fadaa394c037e8b7aaf74e6` |
| busymax | `40b3ab6c89fe30cf8580be61ab0f44eb60a99788` |
| busyfiles | `14c2853cc089345d2b1ed053fc0d34b1a7477110` |
| busycards | `6518526cb624a859f126f85a0ccf3e020a265190` |
| busystack_contacts | `cf399b9af0b7bf8a315e8c5d6123e601c90b7bd2` |
| busystack_dav | `18f636f3227e3df8c1406bafd85b45e7f12cf8bd` |
| busystack_graph | `6572ee14ae992d4cd4f8c2218babaff5051bc132` |

BusyCards' following report/evidence commit changes documentation only; the
accompanying final revision manifest records that HEAD separately from tested
implementation `6518526c`. Shared-package commits precede updated consumer
pins; each consumer records contacts `cf399b9a`, Graph `6572ee14` and DAV
`18f636f3` where used. No package pin points to another application.

In the retained B1–B12 work, BusyFiles' only corrective source changes were two release-provenance Python
files. Its earlier owner integration/history, application/provider/engine code
and workspace remain intact. BusyCards' modified/untracked IDE files and helper
`__pycache__` remain owner/generated residuals; the live IDE/generated residuals are preserved from the C1–C3 baseline. The older historical patch records its earlier session; owner/concurrent changes were not reset. All other task-owned implementation work is committed.

The historical B1–B12 seven live branches, HEADs, staged/unstaged/untracked/generated
state, toolchains and sibling pins are preserved in `baseline.json` and the
baseline patches in the evidence bundle. The updated BusyBox integration at
63d0c2a was present from the start; its old delivery mismatch is closed. Final
archives and manifests reference the new corrected implementation. No history
rewrite, reset, clean, destructive branch change or indiscriminate staging was
used. Previously unattributed BusyFiles work was preserved.

Newly built C2 delivery artifacts are BusyMax source, Linux release and split symbols from the corrected tested revision above, the documentation-only BusyCards source, and the actual successor evidence archive. Actual BusyMax payloads and evidence are also included in the committed `docs/implementation/delivery/c2-preparation` handoff so source-only review exports contain inspectable files. They have source-revision manifests and verified checksums.

Reused artifacts are separately identified: unchanged BusyBox source/Linux/symbols at `5aeba272bde4f6798fadaa394c037e8b7aaf74e6`; BusyFiles portable/DEB/RPM/source-RPM/SBOM/provenance and attested engine/symbols at `14c2853cc089345d2b1ed053fc0d34b1a7477110`; BusyCards runtime/public offline inputs at `6518526cb624a859f126f85a0ccf3e020a265190`. Historical BusyBox Snap is tied to `38ed8fed455ad1a537b3bbefd21bf7bec2376774`; historical test-signed Android APK/AAB modes are tied to BusyMax `19c6cf3e753f590ec73510988a23b4c4b81f74ec`. Those successful historical runs remain successful for those inputs; none of those binaries is claimed to contain this C2 correction. No current Android or Snap payload was rebuilt. Exact files/hashes/source revisions and remaining gates are in the successor manifest.

Fresh extraction checks
verify relative paths, symlinks, execute modes, licenses, helper/runtime hashes,
native libraries and metadata. Generated profiles, credentials, SDK/cache/IDE/
Git payloads are excluded; public offline dependency inputs are intentional,
inventory-verified build artifacts. Original command cwd/paths in evidence are
provenance, not installed runtime path requirements. Deterministic archive
construction, repeated package wrapping and independent Flutter AOT identity
are separate claims; byte-identical independently compiled AOT is not claimed.

The report follow-up commit is documentation/evidence only and is distinguished
from the tested implementation revisions. Companion `manifest.json` and
`SHA256SUMS` carry artifact names, sizes, revisions and hashes without a
self-referential archive hash. Source archives and evidence are supplied as
actual accompanying bundles, not only links to local logs.

The authoritative C1–C3 baseline is `lifecycle/metadata/baseline.json`, with saved lock/pin inputs. It started from BusyMax `19c6cf3e` and BusyBox `38ed8fed`, without resetting either. Current branch/HEAD/staged/unstaged/untracked records, preservation receipts and new source/release hashes are in the successor manifest. The exact unchanged BusyFiles engine/packages and BusyCards runtime/offline inputs are reused with their historical tested revisions; no engine, unchanged application or offline archive rebuild was performed.
