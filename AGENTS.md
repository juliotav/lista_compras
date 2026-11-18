# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Gemini / Antigravity, Codex, etc.) when working with code in this repository. It is the single source of truth: `CLAUDE.md` and `GEMINI.md` only import it.

## Project

"Lista lista" (`lista_compras`): a Flutter app (Android, iOS, web) for shared family shopping lists. Code comments, logs, identifiers in the data layer, and commit messages are in Spanish. The UI is localized in Spanish (template/default) and English.

## Project memory (read first)

`MEMORY.md` holds the binding project principles and current decisions, in Spanish. Read it before changing code. Keep it up to date: when you integrate a new feature or decision, add it; remove anything that no longer applies. Keep it at 50 lines or fewer.

## Commands

All runtime config comes from `--dart-define` values, normally loaded from `.env` (copy `.env.example`). Without it the app runs in `qa` with empty secrets.

```bash
flutter pub get
flutter run --dart-define-from-file=.env            # add -d <deviceId>; see .vscode/launch.json for configured devices
flutter build apk --dart-define-from-file=.env      # ENV=pr in .env for production (real AdMob ids, no "(beta)" label)
flutter build ipa --dart-define-from-file=.env
flutter analyze
flutter test                                        # all tests
flutter test test/offline_sync_test.dart            # one file
flutter test --plain-name "Password security evaluation"   # one test by name
flutter gen-l10n                                    # also runs automatically on build (flutter.generate: true)
dart run flutter_launcher_icons                     # regenerate app icons from assets/images/app_icon.png
```

Tests run SQLite through `sqflite_common_ffi` (`databaseFactory = databaseFactoryFfi`) and mock `SharedPreferences`; follow the same setup in new tests that touch `LocalDbService`/`DatabaseService`.

## Architecture

**State**: `provider` with three `ChangeNotifier`s registered in `lib/main.dart`: `LocaleProvider`, `ThemeProvider`, and `DatabaseService`. `RootSessionDecider` (in `main.dart`) routes on `DatabaseService` state: not initialized → spinner; `isUpdateRequired` → `UpdateRequiredScreen`; user `pending_activation` → activation; user without `idFamilia` → family setup; else `HomeScreen`; no user → intro slides.

**`DatabaseService` (`lib/services/database_service.dart`) is the app's central facade**, a ~2800-line class that holds all in-memory state (current user, families, lists, list items, catalog) and covers auth, account activation and password reset, family management, lists, items, catalog and notifications. Screens call it directly. New domain operations normally go here.

**Data flow is offline-first, with three layers:**
1. **In-memory** lists in `DatabaseService`, updated first so the UI reacts at once (`notifyListeners()`).
2. **Local SQLite** (`LocalDbService`, `sqflite`): mirrors the entities plus a `sync_queue` table and a `session` table. Rows carry a `syncStatus` (`synced`/`pending`).
3. **Remote MongoDB Atlas**, reached **directly from the client** through `mongo_dart` (`MongoService`, a static singleton connection). There is no REST API for data. Collection names live in `MongoConfig` (`lib/config/mongo_config.dart`), and Mongo documents use Spanish snake_case fields (`id_lista_compra`, `fecha_compra`, `nb_articulo`, …).

The mutation pattern, which every write follows (see `markItemAsCompleted`):
update the in-memory list → `_syncService.recordLocalMutation(entityId, action)` → `_localDb.save…(…, syncStatus: 'pending')` → `notifyListeners()` → `_localDb.enqueueSyncItem(collectionName, action, entityId, payload)` → `_syncService.triggerSync(...)`.

`SyncService` (singleton) drains `sync_queue` in batches using `MongoService.bulkWrite`, with retries. On pull it uses recent-mutation timestamps and **tombstones** so that remote data doesn't overwrite or "resurrect" entities changed or deleted locally but not yet pushed. Sync is push-before-pull: on app resume (`DatabaseService.onAppResume`) and when connectivity returns (`ConnectivityService` → `onInternetRestored`). After login, `warmUpOfflineCacheForAllFamilies` preloads every family's data once per user (a flag stored in local DB).

**App version gate**: `MongoConfig.appVersion` reads the version from `package_info_plus` (pubspec `version`). `checkAppVersion` compares it to the `app_version` collection, and an outdated client gets `UpdateRequiredScreen`. Bumping `version:` in `pubspec.yaml` is part of every release.

**Push notifications**: Firebase Messaging plus `flutter_local_notifications` (`PushNotificationService`, which also owns the global `navigatorKey`). Sending works differently: the app POSTs to a PHP microservice (`scripts/hostinger/notify.php`, hosted on Hostinger, configured through `NOTIFICATION_ENDPOINT_URL`/`NOTIFICATION_APP_SECRET`), and that service calls FCM v1 with a service account. `php/contacto.php` is a separate contact-form endpoint for the website (`index.html`, `privacy.html` at the repo root).

**Other services**: `EmailService` sends activation and reset PINs through the Resend API (`RESEND_API_KEY`). `SecurityService` handles password strength checks and SHA-256 hashing (auth is custom, against the `usuario` collection, not Firebase Auth). `AdMobConfig` and `AdInterstitialService` use Google test ad IDs unless `ENV=pr`. `lib/utils/undo_helper.dart` provides the snackbar "undo" used by destructive and completion actions.

## Conventions

- Localization: add strings to both `lib/l10n/app_es.arb` (template) and `app_en.arb`. The `app_localizations*.dart` files are generated, so don't edit them by hand.
- Logging uses `debugPrint` with a bracketed tag prefix such as `[PUSH_NOTIF LOG]` or `[APP_LIFECYCLE]`.
- Heavy initialization (ads, push) runs in the background after `runApp` with `unawaited(...)`, so the first frame is never blocked. Keep startup work off the critical path.
- Portrait-only orientation is enforced on phones and tablets (Android and iOS native config).
