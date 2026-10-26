# BusyCards

Source: [busystack/busycards](https://github.com/busystack/busycards), branch `v0.0.1`.

Standalone Linux contacts application consuming busystack_contacts, busystack_dav and busystack_graph in production paths. Google People personal contacts, Microsoft personal contacts/folders and generic CardDAV/Nextcloud address books use a private encrypted SQLCipher directory. No other BusyStack application, shared database or daemon is required.

The ordinary empty shell opens without an onboarding wizard. Add sources in Settings; configure BusyCards-owned Google Desktop and Microsoft public-client registrations there. Lookup-only connections request read scopes; editing requests contacts write scopes. Generic CardDAV accepts its HTTPS server, DAV login identity and app password. Nextcloud uses system-browser Login Flow v2 and the returned loginName/server, then CardDAV discovery. Credentials and the database key use OS Secret Service under BusyCards' own profile/account namespaces.

Browse/search cached contacts, switch sources, view full details/preserved source data, create/edit/clear/delete, manage actual groups/folders/address books, and change supported photos. Pending changes show base/local/remote and unknown outcomes. Editors autosave drafts and guard close/cancel/save. Native file dialogs provide bounded vCard import previews, destination selection and explicit conversion-loss consent. Multi-selection delete/export is confirmed and operations report per-item outcomes. CardDAV same-format export retains the original resource.

Linux presentation and native host were adapted directly from BusyMax: Flutter/Yaru inside one GTK/libhandy application window, one engine and direct FlView, with Flutter-owned full-height sidebar/header geometry. Fonts, contrast, window-button order, symbolic icons, native search styling, modal keyboard isolation and close decisions use the copied implementations. Rendered side-by-side acceptance remains a separate gate; source similarity is not proof of visual parity.

The source bundle must be extracted as four ordinary siblings:

```
busystack_dav/
busystack_graph/
busystack_contacts/
busycards/
```

Use Flutter 3.47.5 / Dart 3.13.4, Temurin Java 25.0.1, Maven 3.10.0 (owned wrapper), clang/CMake/Ninja/pkg-config, GTK 3/libhandy/libsecret development libraries, Python 3, and a working Linux display/Secret Service session. The Microsoft helper bundles its own Java runtime. No registration, token or secret belongs in build arguments. From `busycards/`:

```
python3 tool/verify.py --flutter /path/to/flutter/bin/flutter
python3 tool/package.py
```

The verifier explicitly permits only these four targets, writes logs/exit codes under `validation/commands`, and never searches a suite workspace or invokes donor scripts. It performs locked resolution, non-mutating format checks, analysis/tests/public examples, localization, Java/native/protocol/cache checks, durable-store/stream harnesses and Linux debug/release builds. Failures remain failures even if an independent release artifact builds. CI materializes the manifest-pinned sibling checkouts to verify the current branch. Its optional source-bundle job reconstructs the same four siblings from an owner-approved HTTPS URL and SHA-256.

For Git checkouts, `tool/shared_dependencies.json` records the canonical package
URLs and exact tested commits. Contacts develops on `busystack_contacts/main`;
the manifest pins that tested revision while Pub resolves the sibling path.
Run `python3 tool/checkout_shared_dependencies.py` before verification; it
rejects a wrong origin, revision, or dirty sibling. Source archives already
contain the selected package trees and need no Git checkout.

For the supplied portable dependency-input bundle, extract it separately, then:

```
python3 tool/prepare_offline.py /path/to/extracted/inputs
export PUB_CACHE="$PWD/validation/pub-cache"
export BUSYCARDS_MAVEN_REPOSITORY="$PWD/validation/helper-maven-repository"
python3 tool/verify.py --offline --flutter /path/to/flutter/bin/flutter
```

Inputs contain independently copied public package/Maven artifacts and the SQLCipher binary matching sqlite3 3.6.0's embedded SHA-256. They contain no application store or credentials. Connected builds fetch the same locked public versions and native artifact without this bundle or a developer's private cache. See [provenance](docs/implementation/build-provenance.md).

Run a relocatable release from its extracted directory with `./busycards`. It does not install itself or register URI handlers. Desktop/AppStream/icon metadata are included for a future owner-approved install. `BUSYCARDS_PROFILE` selects a separate absolute application profile; default is BusyCards' own XDG data directory. Do not point it at another app's profile. Closing/disabling/removing connections never revokes consent for another application.

Evidence and precise remaining gates: [Milestone 1 report](docs/implementation/milestone-1-report.md), [provider references](docs/implementation/provider-references.md), [read-only audit](docs/implementation/read-only-verification.md), [Milestone 2 handoff](docs/implementation/milestone-2-integration.md). No existing app was migrated. No live provider resource is authorized or tested. Fixtures, widget/native execution and live acceptance are reported separately. Milestone 2 requires a subsequent explicit authorization.

Apache-2.0, with BusyStack donor attributions in NOTICE; third-party licenses and the derived suite-style BusyCards icon are documented in [licenses](docs/implementation/licenses.md).
