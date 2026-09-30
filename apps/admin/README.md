# Caramel Cottage admin console (Flutter Web)

The Admin's console in the browser. It runs on one of three data layers, chosen at build time:

| Run with | Data | Use it for |
|---|---|---|
| nothing | The real project `caramel-cottage-retail` (`lib/firebase_options.dart`) | The shop's Admin |
| `--dart-define=USE_EMULATOR=true` | The local Firebase emulators on `localhost`, project `demo-caramel-cottage` | Trying things with throw-away data. Debug runs only: a release build refuses to start with it |
| `--dart-define=FAKE_DATA=true` | In-memory demo data, no Firebase at all | Looking at screens |

A saved sign-in is restored before the console shows, so reloading a page keeps you on it. If Firebase can't start, the console says so and offers **Try again**. Financials is for Admins only (`expense.manage`), since it shows salaries.

All commands below are for Git Bash on Windows, from the repo root.

## Against the emulator
Terminal 1: start Firestore and Auth, then seed them once per emulator start (it asks for the Admin's email and password and an 8-digit override PIN):

```bash
cd firebase
firebase emulators:start --only firestore,auth --project demo-caramel-cottage
```

```bash
cd firebase
npm ci        # first time only
npm run seed
```

Terminal 2:

```bash
cd apps/admin
flutter run -d chrome --dart-define=USE_EMULATOR=true
```

Sign in with the seeded Admin. Users → **New Store Manager** creates a Store Manager in the Auth emulator (never in the real project); use that account on the POS against the same emulator (`apps/pos/README.md`). The Emulator UI at http://127.0.0.1:4000 shows every document and account.

## Against production
Only once the rules and indexes are deployed (docs/SETUP-FIREBASE.md §4) and the real Admin account exists:

```bash
cd apps/admin
flutter run -d chrome                     # debug run on the real project
flutter build web                         # release build in build/web, for hosting
```

## Demo data

```bash
cd apps/admin
flutter run -d chrome --dart-define=FAKE_DATA=true
```

The login page lists the demo accounts.
