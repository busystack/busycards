# Milestone 2 corrective result ledger

As built on **10 October 2026**. B1–B12 are retained; C1–C3 lifecycle corrections and their final complete affected suites pass. Full acceptance remains open only for the explicitly listed gates; historical 6 October evidence is [preserved](history/milestone-2-ledger-2026-10-06.md).

| Gate | Corrected outcome or exact historical evidence |
|---|---|
| busybox complete suite | 1,186 passed; 3 existing skips; implementation `5aeba272`; final corrected tree |
| busymax complete suite | 3,559 passed; 10 existing skips; implementation `40b3ab6c`; final corrected tree |
| busyfiles historical complete suite | 1,790 passed; 26 existing skips; implementation `14c2853c` |
| busycards historical complete suite | 188 passed; 0 existing skips; implementation `6518526c` |
| busystack_contacts historical complete suite | 99 passed; 0 existing skips; implementation `cf399b9a` |
| busystack_dav historical complete suite | 74 passed; 0 existing skips; implementation `18f636f3` |
| busystack_graph historical complete suite | 51 passed; 0 existing skips; implementation `6572ee14` |
| C1–C3 lifecycle | Actual production OAuth/removal/store orchestration; stale commits denied, original enabled/disabled/absent settings preserved, initial-read failures release ownership; complete corrected suites pass. |
| Reference native close | Historical debug default/Mesa exit139 remains failed/unresolved; exact-binary new default/Mesa/gdb attempts exit0. LLVM crash site and concurrent EGL teardown recorded; physical qualification remains open. |
| Linux native/helper/private credential gates | Debug/release, packaged helper, positive Secret Service/cache and native tests pass. |
| BusyFiles unchanged historical packages | Portable/DEB/RPM/source-RPM provenance/reproducibility; X11 and real Wayland both close orders/all formats; 1k/10k/100k standard scale; isolated Ubuntu DEB and Fedora RPM installed lifecycle pass. |
| BusyBox final Snap | Corrected-tree standard rebuild failed installing GNOME SDK before app compilation; no current Snap delivered. Historical standard package review: exit2, one D-Bus declaration needs human review, 51 info OK/no warnings. Human review and strict installed confinement remain open. |
| BusyMax Android | Corrected-tree unit/lint and registration-mode rebuilds remain blocked by existing Gradle/plugin prerequisites (latest: system_theme AGP 4.1.0); no current APK/AAB delivered. Earlier API-36 shell/Settings/DAV/Nextcloud dialog-cancellation results remain historical; the private emulator is currently offline. Physical/prod signing remain open. |
| Three-platform product routes | Actual Settings setup/source selection and attendee fencing widget regressions pass; Windows native host remains unavailable. |
| Independent source layouts | Final locked source extraction/native builds pass; own helpers/public inputs; Files fresh exported attested engine; private default app startup/close. |
| Historical rendered acceptance | Matching X11 empty/populated/window/theme/font/scale/control captures and native workflows pass; Cards owned Wayland control/paint checks pass. Full reference interactive Wayland/physical/exhaustive matrix remains open. |
| Live providers | Blocked: no disposable external accounts/registrations authorized. |

See the [C1–C3 and retained B1–B12 report](milestone-2-report.md), [as-built integration map](milestone-2-integration.md), [machine-readable results](milestone-2-results.json), and accompanying evidence/manifest/SHA256SUMS. Report-only follow-up HEAD is distinguished from tested implementation commits. No pushes, publication, OAuth registration, owner-app installation, history rewrite or owner-change reset occurred.

Unchanged application/shared-package, BusyFiles engine/package, rendered-reference, benchmark and Android-emulator measurements are historical evidence for their listed revisions. Current Max/Box release/debug builds, isolated startup/close, packaged-helper checks and source extraction are separately recorded in the [current report](milestone-2-report.md). No historical count or acceptance result substitutes for the corrected complete suites.
