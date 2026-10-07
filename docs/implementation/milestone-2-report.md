# Milestone 2 completion report

Completed locally on **2026-10-06** against the live repositories. Milestone 1
reports remain historical. This report records implemented production paths and
the acceptance available on this host; it does not turn unavailable platform or
live-provider gates into passes.

## Repository baselines and delivered commits

| Repository / branch | Authoritative start | Task commits | Final code/package commit |
|---|---|---|---|
| `busystack_contacts` / `main` | `872499dc8421dc01c384f0ce7e94321879b56859` | `3fa7ed2`, `4eb01d7`, `a51ac61`, `8f36376` | `8f36376546240a472706e8693f8af10681eca63e` |
| `busystack_dav` / `main` | `ec7dd1560c342f720707dccdfa25a7bf5858e8f0` | `2fbc322`, `e7c0c96`, `18f636f` | `18f636f3227e3df8c1406bafd85b45e7f12cf8bd` |
| `busystack_graph` / `main` | `276f43f1bc9d5664d28123234f1ce1cf7a575e77` | `266aa17`, `b5c42ec`, `4e56cb7`, `cf80565`, `ad97b11` | `ad97b118e80882c7d51f4b02fb9351b7c7ce6fbf` |
| `busycards` / `main` | `53302d60dd5b4c3bbf54f1093bc095d90fa87db5` | `c098b6d`, `4d56eac`, `ca90abe`, `24c1ecc`, `edde9b7`, `8ec2ebe` plus this report-only follow-up | `8ec2ebe49171eddf487e105d9ba9d390160ed672` is the tested/artifact code commit |
| `busybox` / `Release/v0.0.1` | `3e3b959e015e09f4dbe0dbbf7599a316effabfc1` | `1241b3c`, `3a77f04`, `1b265c9`, `bee16fa`, `dba85de`, `63d0c2a` | `63d0c2a11b17e86b099997446dad9f7cba7fe71f` |
| `busyfiles` / `Release/v0.0.1` | `d1a44ca037b2b0b74b9c8724c7d5752b594365d2` | `7151ab0`, `5f5fcaa` | `5f5fcaaae662500fcccf43b6dbcd0cadecb3edef` |
| `busymax` / `feature/remove-onboarding` | `5ab0455ec65cfe2554bbf4abcd89ee45eccf9016` | `0ed6930`, `e8af012`, `1668a13` | `1668a13a024460bd83f2340513bccb18fbd65734` |

The short final hashes in the table are unambiguous in their repositories; the
handoff response records every final full hash after the report commit. Nothing
was pushed or published.

## Delivered integration

- The shared contacts store has one asynchronous contract. BusyCards serializes
  its direct SQLCipher connection; BusyBox uses its existing encrypted mail
  database; BusyMax uses its existing Drift database connection. Transaction
  work is awaited, cursor/data/state commits atomically, notifications follow
  commit, and closing an adapter does not close an application database.
- Source/account/exclusion filtering occurs before the recipient/attendee
  result limit. BusyBox merges scoped cached contacts into its existing
  correspondent composer path. BusyMax supplies cached suggestions to the real
  Linux, Windows and Android attendee controls while preserving manual entry and
  provider-owned attendee fields.
- BusyBox's mail Graph pipeline and BusyMax's calendar/To Do request mechanics
  now use `busystack_graph`. BusyBox keeps immutable mail IDs, budgets and
  bearer-free exact upload-session binding. BusyMax keeps distinct ordinary,
  shared-calendar and category authorization plus timezone/mutation policy.
- BusyFiles' Nextcloud transport, href validation and bounded multistatus
  parsing now use `busystack_dav`, including streamed SEARCH for ordinary
  search and file-ID recovery. BusyMax's common DAV transport, href/error and
  XML layers also use the package. File/calendar/task models, OCS, iCalendar,
  ACL, synchronization and provider-specific policy remain in their apps.
- BusyBox and BusyMax Settings explicitly enable Google/Microsoft contacts and
  create independent CardDAV/Nextcloud sources. They own separate stores,
  credentials, scheduling and removal. No app-to-app runtime dependency, shared
  physical database, provider plugin layer or new account daemon was added.

The production caller/API/adapter/test matrix and the list of retired generic
duplicates are in [milestone-2-integration.md](milestone-2-integration.md).

## Schema and authorization

- BusyBox schema **8 → 9** adds namespaced `bb_contact_*` relations inside the
  existing SQLCipher database. Mail, accounts, drafts, outbox, attachments and
  encryption remain owned by the original schema and migration path.
- BusyMax schema **19 → 20** adds namespaced `bm_contact_*` relations and
  explicit optional links to existing accounts. Its existing SQLite security
  configuration is unchanged; no SQLCipher migration was imposed.
- Google upgrades request the existing complete app scope set plus
  `https://www.googleapis.com/auth/contacts.readonly` or
  `https://www.googleapis.com/auth/contacts`, validate grants/identity, and
  atomically stage persistence. Microsoft similarly requests
  `Contacts.Read` or `Contacts.ReadWrite`. Defaults remain mail/calendar/task
  only. BusyBox's Dart/Java allowlists agree; BusyMax's own desktop and Android
  paths were extended without borrowing another app's helper or cache.

## Dependency and release provenance

Consumers pin these final shared revisions and preserve them as siblings:

- contacts: `8f36376546240a472706e8693f8af10681eca63e`
- DAV: `18f636f3227e3df8c1406bafd85b45e7f12cf8bd`
- Graph: `ad97b118e80882c7d51f4b02fb9351b7c7ce6fbf`

BusyBox intentionally resolves DAV as a direct dependency and UUID 4.6.0.
BusyMax moved the necessary XML surface to 7.0.1 without changing Riverpod 2.
BusyFiles remains its own workspace and consumes `../../../busystack_dav` as
an ordinary external path dependency. Current-source CI and source/package
staging reconstruct these layouts; no unpinned release branch is used.

## Verification summary

- Shared packages: analysis/examples pass; contacts **95**, DAV **74**, Graph
  **44** tests pass.
- BusyCards: full standard Flutter **183** pass; Maven/helper, packaged protocol,
  50,000-contact SQLCipher (1,020 checks), 512 MiB streaming, debug/release,
  native CTest and positive Secret Service/cache gates pass. Final extracted
  source dependency and package gates pass.
- BusyBox: enforced lock and focused production integration **162** pass.
  The pre-correction complete run had 1,126 passes, 3 skips and one off-screen
  test tap; the corrected case passes. The complete suite was not repeated
  after that test-only harness correction.
- BusyFiles: pinned analysis and **100** deterministic Nextcloud provider cases
  pass; one live case is skipped. This is actual provider-path evidence.
- BusyMax: analysis/platform boundaries and all focused suites pass. Its complete
  run had 3,440 passes, 10 skips and two workflow-contract failures; the
  artifact workflow correction then passes 4/4. The whole suite was not
  repeated after that YAML-only correction.

Exact commands, counts, environment distinctions and follow-up results are in
[final-results.md](../../validation/milestone-2/final-results.md).

## Artifacts

| Artifact | SHA-256 |
|---|---|
| `busycards/validation/artifacts/busycards-0.1.0-source.tar.gz` (tested code commit `8ec2ebe`) | `2666e6c63b454eb31fce3b5f7b78d8635e90cd6f69620c4896a88f9de7a16e8d` |
| `busycards/validation/artifacts/busycards-0.1.0-offline-inputs.tar.gz` | `77883f3210011c26b3902b018b39aa1f6c6ecf56127a49e58cb940f8234e4696` |
| `busycards/validation/artifacts/busycards-0.1.0-linux-x64.tar.gz` | `4076e0d50f3c138aa6604d682ab3350da1f205aa641d6589505ecaacecba4229` |
| `busybox/dist/source/busybox-0.0.1-source.tar.gz` | `b16ed587ec64c3c63fa893836b353b04836123fcac03085642316238651d22f5` |
| `busyfiles/dist/source/busyfiles-0.0.1-source.tar.gz` | `8852b738eae2cb81df614a10e6f6554f33a0fd2988c73273b079428f0b3eadc7` |
| `busymax/dist/source/busymax-0.2.4-source.tar.gz` | `c5754b0a0b9c3e617e704ba159badfbd941427dc477f9ce252712a35d10755fb` |

BusyCards' 109-file helper/runtime distribution manifest, archive integrity,
executable modes, metadata, dynamic libraries and default helper handshake pass.
Its AOT library contains one generated build-prefix diagnostic URI but has no
runtime dependency on that prefix. The other three archives resolve their
locked sibling layouts after fresh extraction; their platform release packages
remain subject to the blockers below.

## Explicitly open acceptance

- No live Google, Microsoft, CardDAV, CalDAV or Nextcloud account/resource or
  app registration was authorized. No live provider claim is made.
- BusyFiles' full verifier stops at missing `actionlint`, `rpmbuild` and
  `rpm2cpio`; the corrected engine source path is absent and its wrapper
  refuses stock Flutter. Corrected-engine/native/package release acceptance is
  therefore open. Bubblewrap itself works on the capable host.
- BusyCards starts and remains live under isolated X11/Xvfb, but no screenshot
  utility or Wayland compositor is installed. The required rendered comparison,
  Wayland, physical IME and full visual/accessibility matrix remain open.
- BusyMax Windows/Android builds and packaging were not executed on this Linux
  host. Its repository-wide format check still reports 246 pre-existing or
  unrelated files; touched files are formatted, and no broad unrelated rewrite
  was made.

These limitations did not cause a fallback transport, weakened credential
store, stock BusyFiles engine, test skip, or live-data substitution.

## Preserved owner changes

BusyCards' pre-existing `.idea/busycards.iml` modification,
`.idea/libraries/Flutter_Plugins.xml` untracked file and helper
`__pycache__` remain outside every task commit. Other six repositories are
clean after ignoring their generated distribution outputs.
