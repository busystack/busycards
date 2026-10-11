# Milestone 2 integration — as-built map

As built on **2026-10-10**. Historical 6 October map: [preserved copy](history/milestone-2-integration-2026-10-06.md). The applications remain independent repositories
with app-owned databases, credentials and lifecycles. They consume the three
ordinary Dart packages through public libraries and pinned sibling paths; no
application depends on another application checkout or process.

## Shared foundations

| Shared production contract | Implementation | Proving regression |
|---|---|---|
| Awaitable contacts reads, writes and transaction callbacks | `ContactsStore`, `ContactsReadTransaction` and `ContactsWriteTransaction` in `busystack_contacts`; directory/coordinator/provider callers await every operation | contacts full suite: delayed rollback, transaction serialization, cursor/data atomicity, incomplete scans, pending edits, removal fencing and coordinator shutdown |
| Source-qualified cached suggestions | `ContactsDirectory.suggestRecipients(accountIds, sourceKeys, excludedAddresses, limit)` applies eligibility and exclusions before limiting | multi-account/multi-source regression where the first disabled source would otherwise consume the limit |
| Streamed DAV `SEARCH` | `DavTransferClient.openRead(method: 'SEARCH')`, with the same origin, redirect, body and response bounds as other authenticated reads | DAV protocol suite plus BusyFiles `dav_client_test.dart` file-ID and search cases |
| Shared Graph authentication/retry provenance | `GraphClient` bounded claims replay and ordinary authentication recovery; `GraphException.retryAfterProvided` distinguishes a valid provider delay from the generic fallback | Graph package 51-test suite and both applications' production transport fixtures |

## Application production paths

| Application caller | Public shared API | App-owned storage/auth/lifecycle adapter | Proving application test |
|---|---|---|---|
| BusyCards browse, sync, edit, conflicts, drafts and shutdown through `CardsRuntime` and contacts workspace/editor | `ContactsDirectory`, asynchronous `ContactsStore`, provider public libraries | serialized SQLCipher `ContactsDatabase`; BusyCards authorization brokers and runtime ownership | full 188-test Flutter suite; runtime/workflow tests; 50,000-record encrypted store contract; stream and helper contracts |
| BusyBox `MailboxApplication.suggestRecipients` → `ComposeDialog`/recipient field | `ContactsDirectory.suggestRecipients` | `BusyBoxContactsStore` in the existing SQLCipher mail database; `BusyBoxContactsController`; `MailRuntime` startup/removal/shutdown | `mailbox_application_shutdown_test.dart` cached correspondent/contact merge and source scope; actual Settings→DAV/Nextcloud→composer route fixtures; complete corrected 1,186-test suite |
| BusyBox Settings account actions and contact browser/editor | Google, Microsoft and CardDAV public contacts libraries | explicit linked Google/Microsoft contacts and independent CardDAV/Nextcloud accounts; source preferences; existing registration/secret stores | 23 actual dialog/controller/provider/store edit/recovery cases; 14 owned enrollment orchestration fixtures; positive Java/Secret Service cache gates |
| BusyBox `GraphMailProviderAdapter` and upload-session binding through `provider/graph/graph_client.dart` | `busystack_graph.GraphClient`, `GraphUploadDestination`, streamed download/upload | thin mail error/budget/activity adapter; existing account-scoped token bridge and upload provenance | `graph_client_test.dart`, `graph_adapter_fixture_test.dart`, draft/attachment/security and sync suites |
| BusyFiles `NextcloudHttpTransport` metadata/transfer operations | `DavHttpTransport`, `DavTransferClient` | BusyFiles cancellation, progress, provider-error and ambiguous-mutation mapping; existing origin/credential policy | complete Nextcloud provider suite, especially `http_transport_test.dart` |
| BusyFiles `NextcloudDavClient` listing/search/file-ID recovery | streamed `DavTransferClient.openRead`, `parseDavMultistatusStream`, `DavXmlParser`, `resolveDavHref` | Nextcloud query bodies, namespaces, file IDs, limits and node mapping remain app-owned | `dav_client_test.dart`, `dav_multistatus_test.dart`, provider adapter tests; 100 deterministic cases pass |
| BusyMax Settings and application bootstrap | `ContactsDirectory` and Google/Microsoft/CardDAV provider libraries | `BusyMaxContactsController`; existing account token/authorization staging, Android native authorization and secure-store boundaries | contacts controller/store, Google/Microsoft OAuth, Android authorization and database migration tests |
| BusyMax Linux `EventEditor`, Fluent Windows dialog and Android schedule attendee entry | cached `ContactsDirectory.suggestRecipients` | `BusyMaxContactsStore.selection` supplies linked-account and enabled-source scope; platform UI retains manual entry and attendee metadata | 21 actual three-platform suggestion fencing cases plus original manual-entry/metadata/platform preservation coverage in the complete corrected 3,559-test suite |
| BusyMax Microsoft calendar and To Do clients | `busystack_graph.GraphClient` via `BusyMaxGraphTransport` | distinct ordinary/shared-calendar/category authorization callbacks; calendar timezone and mutation policy remain in callers | calendar/To Do attachment ordinary-401/claims/range fixtures; 50 combined focused Graph cases and complete suite |
| BusyMax DAV HTTP/XML/href/error layers | `DavHttpTransport`, `DavProviderProfile`, shared error/href/XML public types | calendar/task endpoints, iCalendar, scheduling, ACL, sync engine and Nextcloud/iCloud policy remain app-owned | DAV transport/XML/discovery/mutation/sync suites, including the retained 345-case integration focus and complete final suite |

## Persistence and permission changes

- BusyCards retains its contacts-only SQLCipher database and now serializes the
  asynchronous shared transaction contract across yielded callbacks.
- BusyBox advances its encrypted mail database from schema 8 through 9 to **10**. Tables
  use the `bb_contact_*` namespace for accounts, links, sources, records,
  mutations, conflicts, drafts, sync state and source preferences. Contacts-only
  DAV accounts do not become `MailProvider` accounts and closing the adapter
  does not close the mail database. Schema 10 adds a non-secret enrollment
  recovery journal without resetting existing schema-9 data. Independent DAV
  links do not transfer credential ownership to a mail account.
- BusyMax advances its existing application database from schema 19 to **20**.
  Tables use the `bm_contact_*` namespace and explicit links to optional
  calendar/task accounts. The adapter uses the existing Drift transaction and
  background database boundary; it does not open a second database.
- Google contact enablement stages the complete existing app scopes plus
  `contacts.readonly` or `contacts`, verifies returned grants and identity,
  and commits through each app's existing credential boundary. It does not use
  installed-app incremental authorization or add contacts to default login.
- Microsoft contact enablement similarly adds `Contacts.Read` or
  `Contacts.ReadWrite` only when requested and validates actual grants.
  BusyBox extends both its Dart bridge and Java helper allowlist while retaining
  mail-only defaults. BusyMax extends its own desktop and Android paths; no
  BusyBox helper/cache was transplanted.

## Retired generic duplicates and retained policy

- BusyBox's active generic Graph request/stream/upload implementation was
  replaced by a thin adapter over `busystack_graph`. Mail DTOs, immutable-ID
  headers, budgets, error meanings and `GraphUploadSessionBinding` remain
  BusyBox policy.
- BusyFiles' active generic authenticated DAV transport and multistatus parser
  now delegate to `busystack_dav`. Nextcloud SEARCH XML, file properties,
  identities, OCS/share/trash/version/chunking behavior and provider error
  mapping remain BusyFiles policy.
- BusyMax's generic DAV transport, href/error helpers and XML parser now wrap or
  export `busystack_dav`; calendar sync and iCalendar logic were not replaced.
  Calendar and To Do request mechanics use `busystack_graph`, while their
  endpoint models, scope routes, timezone headers and mutation reconciliation
  remain app-owned.

There is no feature flag selecting an older transport and no second contacts
sync implementation in an application. The remaining adapters are domain and
lifecycle policy, not parallel generic protocol stacks.

## Reproducible sibling layout

Each consumer has `tool/shared_dependencies.json` containing live remote URLs,
exact revisions and relative sibling paths, plus a guarded checkout helper.
Current-source CI materializes those revisions before locked resolution.
BusyBox Snap/source staging, BusyFiles source/package workflows, BusyMax
Linux/Windows/Android workflows, and BusyCards' current-source and four-target
bundle paths preserve the sibling directory relationship. BusyFiles remains its
own workspace; `busystack_dav` is an ordinary external dependency.

Current corrective results are in the [report](milestone-2-report.md),
[compact ledger](milestone-2-ledger.md) and accompanying corrective evidence
bundle. `validation/milestone-2` records historical 6 October evidence.

## Corrective lifecycle and product wiring

`ContactsDirectory.bind(accountGeneration:)` validates the persisted generation
before and after awaited provider work. `detach` invalidates and drains an old
binding without disabling the replacement record; explicit `disconnect`
continues to disable it. Provider cleanup closes every owned provider and
retains primary and additional errors. BusyCards owns its exception-safe
SQLCipher queue; BusyBox and BusyMax own their existing Drift database adapter
operations and post-commit configuration streams. Closing a contacts adapter
does not close the application's shared database or calendar/task token client.

BusyMax Linux/Yaru, Windows/Fluent and Android Settings route through the same
controller and staged app authorization boundaries. Google/Microsoft read-only
setup, explicit write consent, reconnect, disable/remove and source selection
are available on the actual platform routes. Independent CardDAV/Nextcloud
contacts do not acquire calendar/task permissions. The three attendee controls
capture account/source/query eligibility, invalidate displayed and pending
results when it changes, and retain manually entered and selected attendees.

BusyBox native Settings exposes independent DAV/Nextcloud association to a
selected mail context separately from suggestion preferences and editing mode.
The real composer preserves correspondent-first ranking and applies contact
eligibility/exclusions before its eight-result limit. Independent credentials
survive mail-link removal; OAuth connections depending on removed mail
authorization follow the existing account ownership. Configuration writes
publish after commit; Settings and recipient controls version reloads and
observe pending/errors and changed eligibility.

BusyBox's basic contact editor retains the full provider-native selected record
and sends only actual field changes. One email edit preserves repeated values
and native IDs/labels/parameters. Structured Google names expose given-name
editing because People `displayName` is output-only; family/middle/native name
fields remain intact. New contacts require an explicit writable destination.
Dirty navigation and in-flight save generation checks protect the draft.
Only confirmed mutations are saved; failed/conflict/unknown states keep their
logical journal ID and draft across restart. Recovery uses shared retry or
reconcile rather than issuing another create.

BusyBox enrollment is owned by the existing AccountManager transition and
credential authority from consent through commit/conditional rollback. Google
staged results retain their original authority; Microsoft retains Java/MSAL
and conditional protected-cache stages. Identity, registration, tenant and
generation are checked at the durable boundary. Separate Secret Service and
SQLite commits use staged recovery; no cross-store atomicity is claimed.
Scheduled tasks in both apps have explicit failure observers and account
status, while manually requested failures remain awaitable.

`GraphClient.download` permits one ordinary confirmed-401 forced-refresh and
one claims replay before yielding any bytes, with a shared finite replay
budget. It preserves range/caller headers, cancellation and account-scoped
claims. Payload already yielded is never restarted. Calendar/To Do attachment
callers and BusyBox's integrated Graph mail/upload consumers exercise this
shared implementation. Exact preauthorized bearer-free uploads are retained.

## Final lifecycle ownership (C1–C3)

BusyMax’s actual bootstrap shares one `AuthorizationPersistence` between both desktop OAuth services and `AuthRepository`. Parent removal claims the controller fence synchronously, captures account identity/generation under authorization serialization, releases it for cancellation and drain, then reacquires and validates before coherent removal. The same receipt owns conditional contacts restoration; a newer user/account/authorization change, retained journal or irreversible removal denies recovery. Contact rows and new parent grant metadata share the credential commit transaction. Network/browser work stays outside database transactions.

BusyBox’s `synchronizeAccount` owns its map entry from the initial account read through final cleanup. Concurrent active callers coalesce; a failure releases only that operation’s entry. Status requires a captured valid generation, scheduled errors remain observed, and contacts cleanup leaves the mail database owned by `MailRuntime`.

The [current report](milestone-2-report.md) and [machine receipts](milestone-2-results.json) identify both final committed trees, failing and passing regressions, complete suites, actual commands and successor artifacts. Shared-package source/consumer pins, independent databases/credentials, native presentation and supported platforms remain unchanged.

Current corrected-tree packaging limits: Corrected-tree Android native unit/lint and APK/AAB registration-mode rebuilds remain blocked before native tests by unavailable existing Gradle/plugin prerequisites: latest offline failure is system_theme com.android.tools.build:gradle:4.1.0. No dependency downgrade/change was made; no new Android payload is delivered. Earlier native/emulator/test-signed artifacts remain historical for their exact tested inputs. Corrected-tree BusyBox standard core24 Snap rebuild failed before application compilation installing gnome-46-2404-sdk latest/stable (exit 1). Earlier public APT/Mesa download failures and relay repairs are retained. Public locked Pub inputs and signed Mesa build prerequisite were verified in the task-only container; they do not constitute a package pass. No new Snap is delivered; old package/review evidence remains historical. See the machine results for exact commands, exit codes, tree fingerprints and logs.

C2 preparation follow-up (11 October 2026): the existing BusyMax removal receipt owns original contact/binding state, partial detach and committed disable separately. Real Drift rollback/COMMIT and mutation-journal failures are tested with the production repository/controller/broker/OAuth/persistence orchestration. The corrected complete BusyMax suite has 3579 passes and 10 existing skips. No shared API/package/pin change; BusyBox, BusyFiles and BusyCards runtime implementations remain unchanged. Actual new payloads/evidence are in the tracked delivery handoff; reused Android/Snap binaries remain tied to their historical source revisions.
