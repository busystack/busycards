# Milestone 2 implementation ledger

This compact ledger is updated as production paths are adopted. A passing fixture is not a live-provider or rendered-platform result; detailed command evidence belongs under `validation/milestone-2/`.

| Production path | Public shared API | Application adapter / lifecycle | Proving regression or acceptance | Status |
|---|---|---|---|---|
| BusyCards browse, sync, mutation and shutdown | `ContactsStore` asynchronous read/write transactions; `ContactsDirectory` | SQLCipher `ContactsDatabase`; `CardsRuntime` | contacts package full suite; `cards_runtime_test.dart`; `contacts_workflow_test.dart`; `tool/store_contract.dart` | Implemented; real encrypted adapter and UI/runtime fixtures pass |
| BusyCards source-scoped cached selection | `ContactsDirectory.suggestRecipients(accountIds, sourceKeys, excludedAddresses, limit)` | Existing runtime/store projections | package multi-source/exclusion-before-limit regression | Implemented; no remote keystroke lookup |
| BusyFiles streaming search prerequisite | `DavTransferClient.openRead(method: 'SEARCH')` | BusyFiles provider adapter pending | DAV request/body/auth/no-redirect/incremental-response protocol regression | Shared prerequisite implemented; consumer migration pending |
| BusyBox contacts and Graph mail | Contacts/Graph public libraries | Existing encrypted mail database, account auth and runtime | Pending | Not yet integrated |
| BusyFiles Nextcloud DAV | DAV public libraries | Existing provider/daemon/file policy | Pending | Not yet integrated |
| BusyMax contacts, Graph and applicable DAV/CalDAV | Contacts/Graph/DAV public libraries | Existing app database, token broker and platform runtimes | Pending | Not yet integrated |

The Milestone 1 ledger remains historical. “Pending” rows are deliberately not treated as implementation or acceptance.
