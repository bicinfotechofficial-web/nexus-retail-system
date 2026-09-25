# Firebase Setup

How to run Firebase locally, and how to connect the two apps to the real project (task B-5). Project details are in [FIREBASE-PROJECT](FIREBASE-PROJECT.md).

## 1. Tools
Install these once, on top of Flutter and Android Studio (B-3). On Windows, run the commands in Git Bash or PowerShell.

| Tool | Why | Install | Check |
|---|---|---|---|
| Node.js 20 or newer | Runs the Firebase CLI and the rules tests | https://nodejs.org (LTS) | `node -v` |
| Java 21 (JDK) | The Firestore emulator is a Java program | https://adoptium.net (Temurin 21) | `java -version` |
| Firebase CLI | Emulators, deploys | `npm install -g firebase-tools` | `firebase --version` |
| FlutterFire CLI | Generates each app's Firebase config | `dart pub global activate flutterfire_cli` | `flutterfire --version` |

After installing the FlutterFire CLI on Windows, add `%LOCALAPPDATA%\Pub\Cache\bin` to your user PATH and open a new terminal.

Then sign in once: `firebase login`. Use the Google account that owns the `caramel-cottage-retail` project.

## 2. Local emulator
Everything under `firebase/` belongs to the emulator and the rules:

| File | What it is | Owner |
|---|---|---|
| `firebase.json` | Emulator ports, and where the rules and indexes live | Central |
| `.firebaserc` | Project aliases: `default` and `demo` point to the local demo project, `prod` to the real one | Central |
| `firestore.rules` | Security rules. A deny-all placeholder until BE-2 to BE-5 | Backend |
| `firestore.indexes.json` | Composite indexes. Empty until BE-7 | Backend |

Start it:

```bash
cd firebase
firebase emulators:start
```

Then open the Emulator UI at http://127.0.0.1:4000.

| Emulator | Address |
|---|---|
| Firestore | `127.0.0.1:8080` |
| Auth | `127.0.0.1:9099` |
| Emulator UI | `127.0.0.1:4000` |

The default project is **`demo-caramel-cottage`**. A `demo-` project exists only inside the emulator, so local runs and tests can never read or write production data, even by mistake. Every test and every app debug run against the emulator must use this project ID.

If port 8080 is already taken on your machine, change the Firestore port in `firebase/firebase.json` for yourself, but don't commit that change.

## 3. Connect the apps to the real project (B-5)
Run these from the repo root in Git Bash, after B-3 is done:

```bash
cd apps/pos
flutterfire configure --project=caramel-cottage-retail --platforms=android --android-package-name=in.caramelcottage.pos --out=lib/firebase_options.dart --yes

cd ../admin
flutterfire configure --project=caramel-cottage-retail --platforms=web --web-app-id=1:137960797974:web:e16ab706577d29c3cc0237 --out=lib/firebase_options.dart --yes

cd ../..
tool/check.sh
```

What they do:
- **POS:** registers the Android app `in.caramelcottage.pos` in the Firebase project (D-023), and writes `apps/pos/lib/firebase_options.dart`, `apps/pos/android/app/google-services.json` and `apps/pos/firebase.json`. It may also add the Google Services plugin to the Gradle files.
- **Admin:** reuses the existing `admin-web` app (it does not create a second one), and writes `apps/admin/lib/firebase_options.dart` and `apps/admin/firebase.json`.

Commit everything they create or change. None of it is secret: access is controlled by the security rules, not by these keys.

If a command asks a question, stops with an error, or says it could not update the Gradle files, stop there and send the output to the central agent.

## 4. Deploying rules and indexes
Don't deploy yet. The production database is in deny-all mode, and stays that way until the rules pass their tests (BE-6). The central agent will say when. The command will be:

```bash
cd firebase
firebase deploy --only firestore --project prod
```
