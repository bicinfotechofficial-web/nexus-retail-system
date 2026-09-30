# Caramel Cottage POS (Android)

The counter app. It runs on one of three data layers, chosen at build time:

| Run with | Data | Use it for |
|---|---|---|
| nothing | The real project `caramel-cottage-retail` (`lib/firebase_options.dart`) | The shop |
| `--dart-define=USE_EMULATOR=true` | The local Firebase emulators, project `demo-caramel-cottage` | Trying things with throw-away data. Debug builds only: a release build refuses to start with it |
| `--dart-define=FAKE_DATA=true` | In-memory demo data, no Firebase at all | Looking at screens |

On start the app restores the saved sign-in, if any. A signed-in phone that is already registered opens on Billing; one that isn't goes to device setup first. With no saved sign-in it shows the login screen, then device setup. If Firebase can't start, the app says so and offers **Try again**.

All commands below are for Git Bash on Windows, from the repo root. `flutter devices` lists the phone or emulator IDs for `-d`.

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

The seed has an Admin, the roles, PTB and MNJ, and a sample catalog, but no Store Manager. Create one in the admin console against the same emulator (`apps/admin/README.md`, Users → New Store Manager at PTB), and sign in to the POS with that account.

Terminal 2, an Android emulator (it reaches the PC at `10.0.2.2`, the default):

```bash
cd apps/pos
flutter run --dart-define=USE_EMULATOR=true
```

A physical phone on the same Wi-Fi: let the emulators listen on the network by changing `"host": "127.0.0.1"` to `"0.0.0.0"` for `auth` and `firestore` in `firebase/firebase.json` (don't commit that), restart them, and pass the PC's LAN IP:

```bash
cd apps/pos
flutter run -d <phone-id> --dart-define=USE_EMULATOR=true --dart-define=EMULATOR_HOST=192.168.1.20
```

The emulator run keeps its own sign-in, device code and offline queue, apart from a production run on the same phone. Only debug builds can talk to the emulator (the Auth emulator is plain HTTP, which only the debug manifest allows).

## Against production
Only once the rules are deployed (docs/SETUP-FIREBASE.md §4) and there is a real Store Manager account:

```bash
cd apps/pos
flutter run -d <phone-id>                # debug build on the real project
flutter run -d <phone-id> --release      # what the shop gets
flutter build apk --release              # build/app/outputs/flutter-apk/app-release.apk
```

## Demo data

```bash
cd apps/pos
flutter run --dart-define=FAKE_DATA=true
flutter run --dart-define=FAKE_DATA=true --dart-define=FAKE_FIRST_RUN=true   # starts at sign-in and device setup
```

The fake login is `sm.ptb@example.com` / `cottage-demo`.

## Device scenarios
`integration_test/` runs the QA device scenarios on an Android emulator against the Firebase emulator. See `integration_test/README.md`; in short, with the emulators running:

```bash
cd apps/pos
flutter test integration_test --dart-define=USE_EMULATOR=true
```

They empty the emulator before each scenario, so reseed it afterwards if you want to go on using the app against it.
