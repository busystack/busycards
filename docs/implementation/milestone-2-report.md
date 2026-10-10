# Milestone 2 corrective implementation and acceptance

Corrective assignment B1–B12, **10 October 2026**. This report supersedes the
6 October status, preserved beside it as dated historical documents. The
seven repositories remain independent. Application databases, credentials,
authentication, UI and lifecycle remain application-owned. BusyFiles has no
contacts functionality. No external account, OAuth registration, push,
publication or installation over an owner's application was performed.

## Corrected production paths

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

## Final-tree verification

| Final complete gate | Tested revision | Actual outcome |
|---|---|---|
| BusyBox `flutter test --reporter=expanded` | `38ed8fed` | 1,184 passed; 3 existing skips; analysis clean. |
| BusyMax `flutter test --reporter=expanded` | `19c6cf3e` | 3,512 passed; 10 existing skips; analysis clean. |
| BusyFiles `scripts/verify.sh` through its attested engine wrapper | `14c2853c` | 1,790 Dart/Flutter cases passed; 26 existing skips; full analysis/source/native gates passed. |
| BusyCards `tool/verify.py --offline` (exactly four repositories) | `6518526c` plus packages below | Graph 51, DAV 74, contacts 99 and BusyCards 188 passed; locked resolution, non-mutating format/analysis, examples, encrypted store/stream, Java/helper/positive Secret Service, native CTest and Linux debug/release gates passed. |

BusyBox additionally passes generation, helper Maven verification, packaged
protocol/runtime/cache checks, source/shell checks, release-script tests, native
CTest (5/5), Linux debug/release and current-source Snap build. BusyMax Linux
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

Only task-owned Dart files were formatted. BusyMax's whole-tree formatting
check reports 236 pre-existing files, verified byte-identical to its original
HEAD; BusyBox's whole-tree command found two ignored stale Snap-generated
files. Source formatting checks and `git diff --check` pass. SDK, Dart, Java,
MSAL and dependency pins remain unchanged. The private toolchain is Flutter
3.47.5, Dart 3.13.4 and Temurin Java 25.0.1; BusyFiles uses the existing attested
engine inputs through its own wrapper, not stock Flutter.

## Native, rendered and independent layout acceptance

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
pins. An earlier BusyMax native close exited 139 with default ICD enumeration;
the untouched reference reproduces it, and gdb shows NVIDIA EGL `dlclose` during
process exit. The reference debug build also exits 139 with Mesa, so the sole
cause is not established; its native orderly-close gate remains failed. Those
existing reference/runtime-driver failures and the initial read-only harness
temporary-directory failure are retained, not converted into passes. Physical GPU/default-driver close acceptance and original-reference native
orderly close remain unverified. Current Box debug, Max release and Cards debug
Mesa-qualified startup/native close each exit 0.

Post-fix measurements: the 50,000-record real encrypted Cards harness performs
500 sync pages in 19,347 ms, browse in 7,467 µs, search median 15,999 µs/p95
20,454 µs, with 46,596,096-byte RSS growth and 1,020 checks. The actual migrated
Nextcloud provider streams 128 MiB in 1.609 s (32 chunks; headers 0.243 s),
18,644,992-byte RSS growth, bounded server progress during consumer pause, and
explicit cancellation after 4,128,715 bytes without replay. Files packaged
Wayland first usable time is 3.520/2.782/6.220 s at 1,000/10,000/100,000 fixture
entries. These are new local synthetic measurements, not live-provider timings
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

The original BusyMax reference debug build exits 139 on native window close
under both default and Mesa ICD selection in the private Xvfb fixture. The
default trace shows NVIDIA EGL unloading, but a sole cause is not established.
Current Max release and Box/Cards debug pass the separate Mesa-qualified native
close check. Reference-debug orderly close and physical/default-driver GPU
acceptance remain failed/unverified; this is not reported as a completed gate.

The full reference Wayland Settings/keyboard/clipboard/native-chooser rendered
comparison has not passed: real reference startup/initial owned paint is
available, but its accessible menu/keyboard automation did not reach Settings.
Cards owned Wayland paint/control checks are not compositor screenshots or
physical keyboard/clipboard/file-dialog acceptance. A capable interactive
Wayland comparison session and the remaining exhaustive rendered matrix are
still required; X11 evidence does not substitute for them.

The official current Snap review reports 51 informational checks OK, no
warnings, and one existing D-Bus slot declaration requiring human store review
(`busybox-dbus`, `deny-connection` constraint), exit 2. Build, contents/security,
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
| busybox | `38ed8fed455ad1a537b3bbefd21bf7bec2376774` |
| busymax | `19c6cf3e753f590ec73510988a23b4c4b81f74ec` |
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

BusyFiles' only corrective source changes are two release-provenance Python
files. Its earlier owner integration/history, application/provider/engine code
and workspace remain intact. BusyCards' modified/untracked IDE files and helper
`__pycache__` remain owner/generated residuals; the modified IDE patch matches
the initial bytes exactly. All other task-owned implementation work is committed.

The original seven live branches, HEADs, staged/unstaged/untracked/generated
state, toolchains and sibling pins are preserved in `baseline.json` and the
baseline patches in the evidence bundle. The updated BusyBox integration at
63d0c2a was present from the start; its old delivery mismatch is closed. Final
archives and manifests reference the new corrected implementation. No history
rewrite, reset, clean, destructive branch change or indiscriminate staging was
used. Previously unattributed BusyFiles work was preserved.

Final delivery contains source archives for Box, Max, Files and Cards (with
exact declared sibling dependencies), tested Linux release bundles, the final
BusyBox Snap, both test-signed Android APK/AAB registration modes, final Files
portable/DEB/RPM/source-RPM/SBOM/provenance, matching exported engine inputs and
symbols, Cards verified public offline inputs, and the actual corrective
evidence archive. Companion manifest/SHA256SUMS records each exact SHA-256,
size, source revision and relevant tested build basis. Fresh extraction checks
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
