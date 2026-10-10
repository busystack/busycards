# Milestone 2 implementation ledger

Status as built on **2026-10-06**. “Pass” below means the stated deterministic
gate, not live-provider or rendered-platform acceptance.

| Production path | Implementing repository / symbol | Regression or acceptance | Status |
|---|---|---|---|
| Asynchronous contacts transactions and source-filtered lookup | `busystack_contacts`: `ContactsStore`, `ContactsDirectory` | 95 package tests; public example | Implemented / pass |
| Streaming DAV SEARCH and file-size transport semantics | `busystack_dav`: `DavTransferClient`, `DavHttpTransport` | 74 package tests; BusyFiles real-provider suite | Implemented / pass |
| Graph claims/auth recovery and Retry-After provenance | `busystack_graph`: `GraphClient`, `GraphException` | 44 package tests; BusyBox/BusyMax client fixtures | Implemented / pass |
| BusyCards real encrypted store/runtime/UI migration | `ContactsDatabase`, `CardsRuntime` | 183 Flutter tests; 1,020 store checks; debug/release/native/helper gates | Implemented / pass |
| BusyBox contacts storage/settings/composer/lifecycle | `BusyBoxContactsStore`, `BusyBoxContactsController`, `MailboxApplication` | 162 focused final tests; schema/encryption/removal tests | Implemented / pass |
| BusyBox Graph mail/attachments | `provider/graph/GraphClient` thin adapter → shared client | Graph and full mail adapter fixtures, upload/range/security tests | Implemented / pass |
| BusyFiles Nextcloud DAV transport/search/parser | `NextcloudHttpTransport`, `NextcloudDavClient`, multistatus adapter | 100 deterministic provider cases pass; 1 live case skipped | Implemented; full release verifier host-blocked |
| BusyMax contacts and attendee controls | `BusyMaxContactsStore`, `BusyMaxContactsController`, Linux/Windows/Android editors | contacts, database, OAuth and platform attendee fixtures | Implemented / pass |
| BusyMax Graph calendar/To Do and common DAV | `BusyMaxGraphTransport`; DAV wrapper/export layers | 45 Graph and 345 DAV focused cases | Implemented / pass |
| Pinned CI/source/package sibling reconstruction | per-repository manifests/helpers/workflows/package scripts | BusyBox/BusyFiles/BusyMax fresh extraction locked resolution; BusyCards four-target verifier | Implemented / pass for locally available source gates |
| Live providers and native cross-platform/rendered matrix | external registrations/accounts, Windows/Android hosts, Wayland compositor and capture tooling | not available/authorized on this host | Explicitly open; no fallback or false pass |
