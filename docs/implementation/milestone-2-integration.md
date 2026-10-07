# Milestone 2 integration — as-built map

As built on **2026-10-06**. The applications remain independent repositories
with app-owned databases, credentials and lifecycles. They consume the three
ordinary Dart packages through public libraries and pinned sibling paths; no
application depends on another application checkout or process.

## Shared foundations

| Shared production contract | Implementation | Proving regression |
|---|---|---|
| Awaitable contacts reads, writes and transaction callbacks | `ContactsStore`, `ContactsReadTransaction` and `ContactsWriteTransaction` in `busystack_contacts`; directory/coordinator/provider callers await every operation | contacts full suite: delayed rollback, transaction serialization, cursor/data atomicity, incomplete scans, pending edits, removal fencing and coordinator shutdown |
| Source-qualified cached suggestions | `ContactsDirectory.suggestRecipients(accountIds, sourceKeys, excludedAddresses, limit)` applies eligibility and exclusions before limiting | multi-account/multi-source regression where the first disabled source would otherwise consume the limit |
| Streamed DAV `SEARCH` | `DavTransferClient.openRead(method: 'SEARCH')`, with the same origin, redirect, body and response bounds as other authenticated reads | DAV protocol suite plus BusyFiles `dav_client_test.dart` file-ID and search cases |
| Shared Graph authentication/retry provenance | `GraphClient` bounded claims replay and ordinary authentication recovery; `GraphException.retryAfterProvided` distinguishes a valid provider delay from the generic fallback | Graph package 44-test suite and both applications' production transport fixtures |

## Application production paths

| Application caller | Public shared API | App-owned storage/auth/lifecycle adapter | Proving application test |
|---|---|---|---|
| BusyCards browse, sync, edit, conflicts, drafts and shutdown through `CardsRuntime` and contacts workspace/editor | `ContactsDirectory`, asynchronous `ContactsStore`, provider public libraries | serialized SQLCipher `ContactsDatabase`; BusyCards authorization brokers and runtime ownership | full 183-test Flutter suite; runtime/workflow tests; 50,000-record encrypted store contract; stream and helper contracts |
| BusyBox `MailboxApplication.suggestRecipients` → `ComposeDialog`/recipient field | `ContactsDirectory.suggestRecipients` | `BusyBoxContactsStore` in the existing SQLCipher mail database; `BusyBoxContactsController`; `MailRuntime` startup/removal/shutdown | `mailbox_application_shutdown_test.dart` cached correspondent/contact merge and source scope; composer/settings focused suite |
| BusyBox Settings account actions and contact browser/editor | Google, Microsoft and CardDAV public contacts libraries | explicit linked Google/Microsoft contacts and independent CardDAV/Nextcloud accounts; source preferences; existing registration/secret stores | contacts-store, Google OAuth, Microsoft bridge/helper and settings tests |
| BusyBox `GraphMailProviderAdapter` and upload-session binding through `provider/graph/graph_client.dart` | `busystack_graph.GraphClient`, `GraphUploadDestination`, streamed download/upload | thin mail error/budget/activity adapter; existing account-scoped token bridge and upload provenance | `graph_client_test.dart`, `graph_adapter_fixture_test.dart`, draft/attachment/security and sync suites |
| BusyFiles `NextcloudHttpTransport` metadata/transfer operations | `DavHttpTransport`, `DavTransferClient` | BusyFiles cancellation, progress, provider-error and ambiguous-mutation mapping; existing origin/credential policy | complete Nextcloud provider suite, especially `http_transport_test.dart` |
| BusyFiles `NextcloudDavClient` listing/search/file-ID recovery | streamed `DavTransferClient.openRead`, `parseDavMultistatusStream`, `DavXmlParser`, `resolveDavHref` | Nextcloud query bodies, namespaces, file IDs, limits and node mapping remain app-owned | `dav_client_test.dart`, `dav_multistatus_test.dart`, provider adapter tests; 100 deterministic cases pass |
| BusyMax Settings and application bootstrap | `ContactsDirectory` and Google/Microsoft/CardDAV provider libraries | `BusyMaxContactsController`; existing account token/authorization staging, Android native authorization and secure-store boundaries | contacts controller/store, Google/Microsoft OAuth, Android authorization and database migration tests |
| BusyMax Linux `EventEditor`, Fluent Windows dialog and Android schedule attendee entry | cached `ContactsDirectory.suggestRecipients` | `BusyMaxContactsStore.selection` supplies linked-account and enabled-source scope; platform UI retains manual entry and attendee metadata | Linux editor (80), Windows preservation (17), Android/adaptive suites and contacts tests |
| BusyMax Microsoft calendar and To Do clients | `busystack_graph.GraphClient` via `BusyMaxGraphTransport` | distinct ordinary/shared-calendar/category authorization callbacks; calendar timezone and mutation policy remain in callers | calendar/To Do Graph fixtures (45), OAuth and attachment tests |
| BusyMax DAV HTTP/XML/href/error layers | `DavHttpTransport`, `DavProviderProfile`, shared error/href/XML public types | calendar/task endpoints, iCalendar, scheduling, ACL, sync engine and Nextcloud/iCloud policy remain app-owned | DAV transport/XML/discovery/mutation/sync suites (345 focused cases) |

## Persistence and permission changes

- BusyCards retains its contacts-only SQLCipher database and now serializes the
  asynchronous shared transaction contract across yielded callbacks.
- BusyBox advances its encrypted mail database from schema 8 to **9**. Tables
  use the `bb_contact_*` namespace for accounts, links, sources, records,
  mutations, conflicts, drafts, sync state and source preferences. Contacts-only
  DAV accounts do not become `MailProvider` accounts and closing the adapter
  does not close the mail database.
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

Detailed command results and the intentionally open host/live gates are in
`validation/milestone-2/final-results.md` and the final Milestone 2 report.
