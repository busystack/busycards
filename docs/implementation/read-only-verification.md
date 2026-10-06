# Read-only repository verification

No write-capable resolution, generator, formatter, test, build, install or donor verification script was run in BusyMax, BusyBox or BusyFiles. Commands use explicit new-target work directories. No original Git/index/configuration write, source edit, generated file addition, migration, adapter, registration/credential access, live account mutation or installed-app connection was performed. The parent was not treated as a Git repository or Dart workspace. No owner instruction files were found by initial applicable parent/repository inspection. New target directories were absent initially; no existing target work was deleted/reinitialized.

## Method and initial state

`tool/read_only_baseline.py` recursively inventories the three originals without following links. Each regular file records mode/size/SHA-256, symlinks record their text, and directories/modes are inventoried, including .git, untracked and ignored/generated files. It detects a file changing while hashed instead of silently taking a torn reading. Source-only Git inspection uses `GIT_OPTIONAL_LOCKS=0` and `git --no-optional-locks`; status is porcelain v2 with complete untracked/ignored entries. No index refresh or clean-tree assumption is used. The baseline does not store/publish file contents. Hashing is read only; it does not compare user application data outside these repositories or prove unrelated external data unchanged.

Snapshots: validation/baselines/*-before.json, *-protocol-phase.json, *-application-phase.json, *-release-phase.json and accompanying difference arrays. Audit exit 2 means a detected difference; it is not concealed as an all-green Git check. Baseline timestamps in UTC are inside each snapshot. The original BusyFiles dirty state is preserved.

| Repository | Initial HEAD | Branch | Initial staged/unstaged/untracked/ignored status records | Inventory entries before → release phase | Differences from baseline |
|---|---|---|---|---|---|
| busymax | `660c6016860e4e020634a93d54b921dde966536e` | Release/v0.2.4 | 0/0/0/7011 | 14982 → 14982 | 0 |
| busybox | `3e3b959e015e09f4dbe0dbbf7599a316effabfc1` | Release/v0.0.1 | 0/0/0/131000 | 146409 → 146409 | 0 |
| busyfiles | `f1f9b4f08db07381c5d44e3566a4e79e169d046e` | Release/v0.0.1 | 0/25/24/1659 | 6208 → 6209 | 43 |

BusyMax and BusyBox match their complete initial inventories, Git states and ignored/generated content through the release-phase check. BusyFiles differs. Its HEAD/branch and .git/index content remain unchanged at that check; its pre-existing dirty tree was not reset. Difference attribution is unestablished: the command ledger contains no write-capable operation in the original, and the changes were preserved. When differences appeared, operations potentially capable of writing there were stopped and paths identified; independent new-target work continued. No claim is made that all three originals are unchanged, or that a concurrent owner/tool caused the BusyFiles differences.

BusyFiles changed paths (release phase; final delivery audit is appended separately):

- `.dart_tool/hooks_runner/shared/sqlite3/.lock`
- `.dart_tool/hooks_runner/sqlite3/6b4ebf10e7/.lock`
- `.dart_tool/hooks_runner/sqlite3/6b4ebf10e7/dependencies.dependencies_hash_file.json`
- `.dart_tool/hooks_runner/sqlite3/6b4ebf10e7/output.json`
- `.dart_tool/hooks_runner/sqlite3/6b4ebf10e7/stdout.txt`
- `.dart_tool/hooks_runner/sqlite3/799a3ceee2/.lock`
- `.dart_tool/hooks_runner/sqlite3/799a3ceee2/dependencies.dependencies_hash_file.json`
- `.dart_tool/hooks_runner/sqlite3/799a3ceee2/output.json`
- `.dart_tool/hooks_runner/sqlite3/799a3ceee2/stdout.txt`
- `.dart_tool/test/incremental_kernel.Ly9AZGFydD0zLjEz`
- `apps/busyfiles_ui/.dart_tool/flutter_build/f9b2111733194e465a084e32e65196c6/.filecache`
- `apps/busyfiles_ui/.dart_tool/flutter_build/f9b2111733194e465a084e32e65196c6/app.dill`
- `apps/busyfiles_ui/.dart_tool/flutter_build/f9b2111733194e465a084e32e65196c6/debug_bundle_linux-x64_assets.stamp`
- `apps/busyfiles_ui/.dart_tool/flutter_build/f9b2111733194e465a084e32e65196c6/flutter_assets.d`
- `apps/busyfiles_ui/.dart_tool/flutter_build/f9b2111733194e465a084e32e65196c6/kernel_snapshot_program.stamp`
- `apps/busyfiles_ui/.dart_tool/flutter_build/f9b2111733194e465a084e32e65196c6/linux_engine_sources.d`
- `apps/busyfiles_ui/.dart_tool/flutter_build/f9b2111733194e465a084e32e65196c6/unpack_linux.stamp`
- `apps/busyfiles_ui/build/.last_build_id`
- `apps/busyfiles_ui/build/flutter_assets/NativeAssetsManifest.json`
- `apps/busyfiles_ui/build/flutter_assets/fonts/MaterialIcons-Regular.otf`
- `apps/busyfiles_ui/build/flutter_assets/kernel_blob.bin`
- `apps/busyfiles_ui/build/flutter_assets/packages/yaru/assets/yaru_icons.otf`
- `apps/busyfiles_ui/build/linux/x64/debug/.ninja_deps`
- `apps/busyfiles_ui/build/linux/x64/debug/.ninja_log`
- `apps/busyfiles_ui/build/linux/x64/debug/build.ninja`
- `apps/busyfiles_ui/build/linux/x64/debug/bundle/data/flutter_assets/kernel_blob.bin`
- `apps/busyfiles_ui/build/native_assets/linux/native_assets.json`
- `apps/busyfiles_ui/build/test_cache/build/c38486b69605e051440ffddd6528c79b.cache.dill.track.dill`
- `apps/busyfiles_ui/linux/flutter/ephemeral/generated_config.cmake`
- `apps/busyfiles_ui/linux/flutter/ephemeral/libflutter_linux_gtk.so`
- `docs/evidence/native-linux-ui-validation-2026-10-03.json`
- `docs/native-linux-ui-completion-2026-10-03.md`
- `engine/README.md`
- `native/build/Testing/Temporary/CTestCostData.txt`
- `native/build/Testing/Temporary/LastTest.log`
- `scripts/browser-keyboard-native.py`
- `scripts/diagnostics/window_lifecycle_probe.py`
- `scripts/package-wayland-smoke.py`
- `scripts/test_package_wayland_smoke.py`
- `scripts/ui-followup-native.py`
- `scripts/verify.sh`
- `scripts/with-isolated-desktop-session.sh`
- `git:status`

Initial BusyFiles tracked/untracked paths are retained in the original baseline status (no requirement for a clean tree). Original ignored output includes .dart_tool, builds, native/helper products and other generated content; all is fingerprinted rather than assumed safe because Git ignores it.

## Independent references and data protection

The BusyMax reference is an ordinary source-only copy at validation/references/busymax. It has no donor .git, .dart_tool or build links; new caches/build outputs are owned by the copy. The only donor-generated native libraries copied were public SQLite/SQLCipher dependency artifacts independently checked against the resolved maintainer package’s embedded SHA-256. No original application generated business code, profile/database, registration, live token or native-helper cache is used as a build/runtime dependency. No hard links, symlinks into originals, Git worktree or shared writable generated/source files were created.

The original reference lockfile is resolved independently in validation/reference-pub-cache; reference release compilation passed. Required native/registration_reader source was copied, not registration files. Launch attempts use isolated 0700 XDG profiles under validation/profiles/native-acceptance and unset owner display/DBus addresses. They failed before launching the app because Unix socket binding is denied. No installed owner instance was launched/connected or installed over. No original install script was invoked. User application data outside the repositories was not opened or fingerprinted; protection is by isolated paths and avoided credentials/sessions, not an invented before/after data comparison.

BusyCards deterministic store, OAuth, provider, helper and performance fixtures use their own temporary validation profiles and synthetic contacts/tokens; fixture secrets are labeled synthetic in tests. No live-resource authorization was supplied. Fresh source extraction reconstructs only four new siblings under validation/fresh-extraction and uses independently copied verified public dependencies, with no original app checkout or installed helper.

## Earlier delivery verification

The final `delivery-phase` audit exited **2**, reflecting detected differences rather than a false clean pass. [Its log](../../validation/read-only-delivery.log) and full before/after inventories and difference lists under validation/baselines are retained. BusyMax and BusyBox have **zero** differences across contents, modes, links, Git state and ignored output. Their HEAD/branch and .git/index also match. BusyFiles has **44** differences from its original baseline, with **6,210** final inventory entries versus 6,208 initially. HEAD/branch and .git/index remain identical. The new difference since the 43-path release audit is `scripts/test_isolated_desktop_session.py`. Its attribution, like the other differences, is unestablished; no changes were reverted. [Full BusyFiles delivery difference list](../../validation/baselines/busyfiles-delivery-phase-differences.json).

| Repository | Initial staged / unstaged / untracked / ignored | Delivery staged / unstaged / untracked / ignored | Fingerprint differences |
|---|---|---|---|
| BusyMax | 0 / 0 / 0 / 7,011 | 0 / 0 / 0 / 7,011 | 0 |
| BusyBox | 0 / 0 / 0 / 131,000 | 0 / 0 / 0 / 131,000 | 0 |
| BusyFiles | 0 / 25 / 24 / 1,659 | 0 / 28 / 25 / 1,660 | 44, preserved and unattributed |

The source-only inspection and all implementation commands were confined as described above. No original-app operation capable of writing was started after differences were found; independent new-target work continued. These audits are observations at recorded times, not a claim that ongoing owner/concurrent changes are absent or that their author has been identified. Milestone 2 has not started.

The subsequent final-phase audit also exited 2 with identical results: BusyMax/BusyBox zero differences; BusyFiles 44. [Final audit log](../../validation/read-only-final.log). Head/branch/index remain unchanged and no further difference appeared between delivery-phase and final-phase.

## Final handoff verification

After the final vCard and release/helper-permission corrections, the `handoff-phase` audit exited **2**. [Audit log](../../validation/read-only-handoff.log), [complete BusyFiles difference list](../../validation/baselines/busyfiles-handoff-phase-differences.json). BusyMax and BusyBox again have **zero** differences. BusyFiles has **127 comparison differences**, including Git metadata files and HEAD/status records; this count is not 127 changed application-source files. Its inventory now contains **6,283** entries. At **2026-10-04T23:18:11.435760Z**, its observed HEAD was `c939a62dee7ba5e4f2bbf25fc8a0d209addc4850`, advanced from initial `f1f9b4f08db07381c5d44e3566a4e79e169d046e`. Its branch remains Release/v0.0.1; .git/index and refs/logs/objects changed. Status counts are **0 staged / 4 unstaged / 8 untracked / 1,660 ignored** versus initial 0 / 25 / 24 / 1,659.

Additional non-Git differences since the prior final audit include `.idea/workspace.xml`, `apps/busyfilesd/test/local_batch_rename_crash_test.dart` and `apps/busyfilesd/test/local_mutation_identity_test.dart`; `apps/busyfiles_ui/build/.last_build_id` returned to its initial fingerprint. No BusyFiles write-capable operation or Git write was performed by this implementation. Attribution remains unestablished. The changed files/Git state were identified and preserved without reset/revert; operations that might write originals remain stopped. Only new-target reports/artifacts were finalized after this observation. The Milestone 2 source map records the inspection revision and this later observed revision separately; it must be freshly revalidated if that milestone is authorized.

## Correction-task observed baseline and comparisons

This correction began with the existing four new targets; none was deleted or reinitialized. The three original repositories remained read-only. **BusyFiles was observed first**, at `2026-10-05T02:13:39.214199+00:00` through `02:14:13.783275+00:00`, before other corrective work. Its already changed HEAD, index, dirty tracked state and complete untracked/ignored/generated inventory became the new observed baseline. The older **127-difference Milestone 1 comparison remains unresolved**; it was neither reset nor reattributed. That historical count is a separate earlier comparison, not a count to add to the new differences below.

Initial corrective before/after evidence is under [validation/correction](../../validation/correction/read-only-results.json): each donor has `*-before.json`, `*-after.json` and `*-differences.json`. These first corrective after-snapshots use imported `tool/read_only_baseline.py.snapshot`, ordinary read-only file handles, `GIT_OPTIONAL_LOCKS=0` and `git --no-optional-locks`. Every inventory entry and the HEAD/branch/porcelain-status results were compared; only snapshot timestamps were excluded. The audit executed in order BusyFiles, BusyMax, BusyBox and exited **2**, reporting the observed BusyFiles byte differences instead of declaring a false unchanged pass. A separate final delivery observation is recorded below; these earlier results are retained.

| Repository | Correction-start HEAD = first after-HEAD | Branch | Inventory before → first after | Staged / unstaged / untracked / ignored before = first after | First comparison differences |
|---|---|---|---|---|---|
| BusyFiles | `c939a62dee7ba5e4f2bbf25fc8a0d209addc4850` | Release/v0.0.1 | 6,284 → 6,284 | 0 / 7 / 9 / 1,660 | 7 file fingerprints; no Git-state differences |
| BusyMax | `660c6016860e4e020634a93d54b921dde966536e` | Release/v0.2.4 | 14,982 → 14,982 | 0 / 0 / 0 / 7,011 | 0 |
| BusyBox | `3e3b959e015e09f4dbe0dbbf7599a316effabfc1` | Release/v0.0.1 | 146,409 → 146,409 | 0 / 0 / 0 / 131,000 | 0 |

Index contents, size, mode and file type are unchanged for all three. Observed index SHA-256 values before and after are:

- BusyFiles: `da88cfb982e6b729b0908d78f3c4addcca1ee2ef537aa7f8a6b60c3ddb038512` (93,156 bytes).
- BusyMax: `e23729c73acc1182a25dacdb4d64134de3a8ae4b8ffd6581e5c1aef469be999a` (151,380 bytes).
- BusyBox: `447504c0962596384cf8c9f2f253fc796adfcdc7e761b74c1cafe3b53a0eb75f` (119,495 bytes).

First corrective after-snapshot observation intervals in UTC are BusyFiles `02:47:06.100759–02:47:36.070943`, BusyMax `02:47:36.253112–02:48:41.501840`, and BusyBox `02:48:42.310148–02:51:02.294521`, all on 2026-10-05 (the preceding local calendar date in America/Vancouver). Their baseline-completion times and exact interval timestamps are recorded in the result manifest.

The [seven new BusyFiles differences](../../validation/correction/busyfiles-differences.json) are:

- `.dart_tool/hooks_runner/shared/sqlite3/.lock`
- `.dart_tool/hooks_runner/sqlite3/6b4ebf10e7/.lock`
- `.dart_tool/hooks_runner/sqlite3/799a3ceee2/.lock`
- `.dart_tool/test/incremental_kernel.Ly9AZGFydD0zLjEz`
- `apps/busyfiles_ui/build/test_cache/build/c38486b69605e051440ffddd6528c79b.cache.dill.track.dill`
- `native/build/Testing/Temporary/CTestCostData.txt`
- `native/build/Testing/Temporary/LastTest.log`

These changes were preserved. Their attribution is **unestablished**. The corrective command allowlist and evidence show no donor resolution/build/test/formatter/generator/install/Git-write operation, but that does not establish who changed these files or prove a byte-unchanged BusyFiles boundary. BusyMax and BusyBox match their full correction-start byte/Git baselines; the corresponding BusyFiles byte-verification gate remains unresolved. No reset, checkout, clean, restore, commit, stage or revert was attempted. No user credential store or installed application instance was accessed to resolve this observation.

A separate [metadata-only shared-path check](../../validation/correction/shared-path-check.json) examined 113,991 regular files and 781 symlinks inside the four authorized new targets. It found no symlink resolving into any protected donor and no device/inode match between a new-target regular file and any of the seven changed BusyFiles files. This excludes those observed direct shared-file/link routes; it does not attribute the differences, compare every donor inode, or establish who wrote them. No file contents or user credential stores were read for that check. Its initial attempt could not launch because sandbox `/tmp` mount preparation hit quota; a later attempt completed after disposable new-target cleanup, without donor cleanup.

### Delivery observation before the final helper-layout correction

The separate complete delivery snapshots preserve the earlier observations rather than overwrite them: `*-delivery-after.json`, `*-delivery-differences.json` and [read-only-delivery-results.json](../../validation/correction/read-only-delivery-results.json), compared against this task's unchanged `*-before.json` baselines. The same read-only method again executed BusyFiles first and exited **2**. No snapshot timestamp is treated as a file/Git difference.

| Repository | Final delivery interval, UTC 2026-10-05 | Inventory before → delivery | File differences from correction start | HEAD / branch / index / porcelain status |
|---|---|---|---|---|
| BusyFiles | 02:58:41.366372–02:59:34.514335 | 6,284 → 6,284 | **11** | All unchanged |
| BusyMax | 02:59:34.850302–03:00:57.441046 | 14,982 → 14,982 | **0** | All unchanged |
| BusyBox | 03:00:58.295522–03:02:46.734299 | 146,409 → 146,409 | **0** | All unchanged |

All HEADs, branch names, index SHA-256/size/mode values and staged/unstaged/untracked/ignored counts remain the same as the correction-start values listed above. BusyFiles's [eleven delivery differences](../../validation/correction/busyfiles-delivery-differences.json) retain the earlier seven and add these four generated paths:

- `apps/busyfiles_ui/.dart_tool/flutter_build/f9b2111733194e465a084e32e65196c6/debug_bundle_linux-x64_assets.stamp`
- `apps/busyfiles_ui/.dart_tool/flutter_build/f9b2111733194e465a084e32e65196c6/flutter_assets.d`
- `apps/busyfiles_ui/build/.last_build_id`
- `apps/busyfiles_ui/build/linux/x64/debug/.ninja_log`

The eleven are observations relative to this corrective task's baseline; the earlier seven remain an intermediate observation, and the historical 127 remain a different earlier Milestone 1 comparison. None is silently combined or attributed to an owner/concurrent process. No donor write-capable command, reset, restoration, staging or Git write was performed by the correction or either audit. Nevertheless, **BusyFiles cannot be reported byte-unchanged or proven unaffected by this task solely from these observations**. Its changed bytes are preserved and their attribution remains unresolved. BusyMax and BusyBox match their complete current-task delivery baselines. The earlier inode check was not repeated or expanded; it does not provide an attribution claim for the four additional paths.

### Final corrected-release observation

After the production BusyCards Microsoft-helper layout correction and its main/fresh test, analysis and Linux rebuilds, a final complete read-only audit again compared all three donors against the **original correction-start snapshots**, BusyFiles first. Separate `*-corrected-release-after.json`, `*-corrected-release-differences.json` and [read-only-corrected-release-results.json](../../validation/correction/read-only-corrected-release-results.json) preserve every earlier observation. The audit exited **2** because of the observed BusyFiles byte differences; no timestamp alone is counted.

| Repository | Final corrected-release interval, UTC 2026-10-05 | Inventory before → final | File differences from correction start | HEAD / branch / index / porcelain status |
|---|---|---|---|---|
| BusyFiles | 03:15:34.236059–03:15:59.366961 | 6,284 → 6,284 | **11** | All unchanged |
| BusyMax | 03:15:59.523785–03:17:03.173928 | 14,982 → 14,982 | **0** | All unchanged |
| BusyBox | 03:17:03.976164–03:19:24.187454 | 146,409 → 146,409 | **0** | All unchanged |

The final observed HEADs, branch names, index SHA-256/size/mode and staged/unstaged/untracked/ignored counts still match this task's original observed baselines listed above. The [eleven BusyFiles paths](../../validation/correction/busyfiles-corrected-release-differences.json) are the same path set as the previous delivery audit. **The count did not establish byte stability:** a separate complete comparison against the previous delivery snapshots found two of those files changed again, `.dart_tool/hooks_runner/shared/sqlite3/.lock` and `.dart_tool/hooks_runner/sqlite3/6b4ebf10e7/.lock`. Those additional observations are included in the latest manifest's `differencesSincePriorDelivery`; BusyMax and BusyBox have zero differences in that comparison as well.

All observed BusyFiles changes remain preserved and unattributed. The correction/audit command allowlist contains no original-app write-capable resolution, generator, formatting, test, build, install, Git write, reset or restoration, but it does not prove causation or a byte-unchanged BusyFiles boundary. The historical 127, intermediate seven, and final eleven retain their distinct baselines and observation intervals. The final deliverable therefore records **BusyMax/BusyBox unchanged and BusyFiles byte verification unresolved**, rather than claiming all three passed. No optional inode/symlink scan was repeated. Following this final audit, only new-target documentation and archive verification/packaging remain authorized; Milestone 2 remains unstarted.

Milestone 2 has not started. Remaining reports, fresh-copy verification and artifact generation are confined to the four new targets; none authorizes existing-app integration.
