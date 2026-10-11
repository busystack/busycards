# C2 preparation correction — actual payload handoff

This documentation folder contains the actual corrected BusyMax source, Linux release, split symbols and evidence archives, plus manifests/checksums. It is included in source-only review exports, so the files can be inspected independently. It is not used by BusyCards at runtime.

Run `sha256sum --check SHA256SUMS` in this directory. Extract each archive into a separate empty directory. `m2-corrective-evidence.tar.gz` contains actual current logs, receipts, patches, regression inputs and native captures, plus selected verified historical BusyBox and unresolved reference-close evidence. Its embedded inventory covers every file byte, size and mode. The application archive includes its declared sibling dependency layout.

All new BusyMax payloads name the tested correction commit in their manifests. There is no current-source Android or BusyBox Snap payload here. Older APK/AAB/Snap successes apply only to the historical revisions listed in the manifest and do not contain this correction. Full M2 acceptance remains open at the recorded platform/live-resource/native-close/confinement gates. No SDK/driver change, owner-app installation, OAuth registration, push or publication was performed.
