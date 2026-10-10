# Milestone 2 corrective result ledger

As built on **10 October 2026**. B1–B12 production corrections and deterministic application-boundary regressions pass. Full acceptance remains open only for the explicitly listed gates; historical 6 October evidence is [preserved](history/milestone-2-ledger-2026-10-06.md).

| Gate | Final-tree outcome |
|---|---|
| busybox complete suite | 1,184 passed; 3 existing skips; implementation `38ed8fed` |
| busymax complete suite | 3,512 passed; 10 existing skips; implementation `19c6cf3e` |
| busyfiles complete suite | 1,790 passed; 26 existing skips; implementation `14c2853c` |
| busycards complete suite | 188 passed; 0 existing skips; implementation `6518526c` |
| busystack_contacts complete suite | 99 passed; 0 existing skips; implementation `cf399b9a` |
| busystack_dav complete suite | 74 passed; 0 existing skips; implementation `18f636f3` |
| busystack_graph complete suite | 51 passed; 0 existing skips; implementation `6572ee14` |
| Linux native/helper/private credential gates | Debug/release, packaged helper, positive Secret Service/cache and native tests pass. |
| BusyFiles final packages | Portable/DEB/RPM/source-RPM provenance/reproducibility; X11 and real Wayland both close orders/all formats; 1k/10k/100k standard scale; isolated Ubuntu DEB and Fedora RPM installed lifecycle pass. |
| BusyBox final Snap | Built; contents/runtime/helper/private cache pass. Official review exit 2: one existing D-Bus slot needs human store review; 51 informational checks OK; no warnings. |
| BusyMax Android | Both APK/AAB registration modes/resource/alignment/signature checks pass; actual API-36 emulator shell/Settings/DAV/Nextcloud dialog cancellation pass. |
| Three-platform product routes | Actual Settings setup/source selection and attendee fencing widget regressions pass; Windows native host remains unavailable. |
| Independent source layouts | Final locked source extraction/native builds pass; own helpers/public inputs; Files fresh exported attested engine; private default app startup/close. |
| Rendered acceptance | Matching X11 empty/populated/window/theme/font/scale/control captures and native workflows pass; Cards owned Wayland control/paint checks pass. Full reference interactive Wayland/physical/exhaustive matrix remains open. |
| Live providers | Blocked: no disposable external accounts/registrations authorized. |

See the [B1–B12 report](milestone-2-report.md), [as-built integration map](milestone-2-integration.md), [machine-readable results](milestone-2-results.json), and accompanying evidence/manifest/SHA256SUMS. Report-only follow-up HEAD is distinguished from tested implementation commits. No pushes, publication, OAuth registration, owner-app installation, history rewrite or owner-change reset occurred.
