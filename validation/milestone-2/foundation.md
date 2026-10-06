# Milestone 2 foundation evidence

Environment: Ubuntu 26.04 host, Flutter 3.47.5, Dart 3.13.4. Commands used `TMPDIR=/var/tmp` because the small `/tmp` tmpfs exhausted its quota. The normal sandbox denies socket creation; a permission-capable probe established loopback TCP, Unix sockets, private D-Bus and X11 availability. No provider account or remote service was used.

| Repository / tree | Command (repository working directory) | Result |
|---|---|---|
| `busystack_contacts` / committed `3fa7ed2` | `dart analyze`; `dart test` | Pass; analysis clean; 95 tests |
| `busystack_dav` / committed `2fbc322` | `dart analyze`; `dart test` | Pass; analysis clean; 72 tests |
| `busycards` / pre-commit task tree based on `53302d6` | `flutter analyze --no-pub` | Pass; no issues |
| `busycards` / same tree | `flutter test --no-pub test/application/cards_runtime_test.dart test/features/contacts_workflow_test.dart` | Pass; 12 tests |
| `busycards` / same tree | `dart run tool/store_contract.dart --dataset-size 50000` | Pass; 1,020 checks, encrypted 146,010,112-byte store, restart/wrong-key/rollback/concurrent isolation exercised |

The 50,000-record fixture reported 29,332 ms sync time, 14,332 µs bounded browse, 19,329 µs search p50, 27,122 µs p95 and 27,979,776-byte RSS growth. These are local deterministic measurements, not live-provider or rendered UI acceptance.

The foundation change makes every store operation and transaction callback awaitable. The BusyCards adapter serializes its direct SQLCipher connection across asynchronous gaps, commits cursor/data/state before notifications, rolls back failures and rejects use after close. The shared directory revalidates account/source generation at the commit boundary. Source/account/exclusion eligibility is applied before the final suggestion limit.
