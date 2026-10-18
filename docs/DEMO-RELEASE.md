# The client's trial, and shutting it down afterwards (C-8, first pass; D-040)

The trial runs on its **own Firebase project**, `caramel-cottage-demo`, with its own build of the POS (`demo` flavor, application ID `in.caramelcottage.pos.demo`, labelled "Caramel Cottage DEMO") and its own admin site. The real project, `caramel-cottage-retail`, stays empty and untouched. When the demo is over you shut the trial project down, and every demo APK and the demo site stop working. For the real launch you do the same steps again against `caramel-cottage-retail`, with the default (`prod`) flavor.

Run commands in Git Bash from the repo root unless it says otherwise.

## A. Create the trial project (once, about 20 minutes)
1. Firebase console → **Add project** → name `caramel-cottage-demo` (the project ID must be exactly that; if Google offers a variant like `caramel-cottage-demo-1a2b3`, tell me and I'll change the ID in the code). Turn Google Analytics off. Stay on the **Spark** plan.
2. **Authentication** → Get started → Sign-in method → enable **Email/Password**.
3. **Firestore Database** → Create database → location **asia-south1 (Mumbai)**, **Standard** edition, **production mode**.
4. **Hosting** → Get started (just click through; the deploy step does the rest).
5. Connect the code to it:
```bash
cd apps/pos
flutterfire configure --project=caramel-cottage-demo --platforms=android --android-package-name=in.caramelcottage.pos.demo --out=lib/firebase_options_demo.dart --android-out=android/app/src/demo/google-services.json --yes
git checkout firebase.json          # flutterfire rewrites this file; keep the committed one
cd ../admin
flutterfire configure --project=caramel-cottage-demo --platforms=web --out=lib/firebase_options_demo.dart --yes
git checkout firebase.json
cd ../..
git add apps/pos/lib/firebase_options_demo.dart apps/pos/android/app/src/demo/google-services.json apps/admin/lib/firebase_options_demo.dart
git commit -m "Trial project configuration"
```
These values are not secret (access is controlled by the rules), so committing them is fine.

## B. Rules and data for the trial project
```bash
cd firebase
firebase login
firebase deploy --only firestore --project clientdemo
```
Seed it. This needs a service-account key **of the trial project**: Firebase console (trial project) → Project settings → Service accounts → Generate new private key. Save it **outside the repo** (for example `D:\keys\cc-demo.json`), and delete it afterwards.
```bash
npm ci
export GOOGLE_APPLICATION_CREDENTIALS="D:/keys/cc-demo.json"
export SEED_ADMIN_EMAIL="<an email you can read>"
npm run seed -- --project caramel-cottage-demo --yes-really
```
It asks for the Admin password (8+ characters) and an 8-digit override PIN, then creates the roles, the Admin, locations PTB and MNJ and a sample catalog. Safe to run twice.

In the console (sign in at the demo site once it is online, step D): Users → New Store Manager for the client at location PTB.

## C. Signing key (once; also used for the real launch)
An app signed with a different key can't update one signed with another, and the API-key restriction needs this key's fingerprint. **Back the keystore and its passwords up outside the repo. If you lose them, every phone needs an uninstall and reinstall.**
```bash
cd apps/pos/android
keytool -genkey -v -keystore app/caramel-release.jks -alias caramel -keyalg RSA -keysize 2048 -validity 10000
```
Create `apps/pos/android/key.properties` (already in `.gitignore`, never commit it):
```
storeFile=app/caramel-release.jks
storePassword=<the keystore password>
keyAlias=caramel
keyPassword=<the key password>
```

## D. Build and publish the trial
```bash
cd apps/pos
flutter build apk --release --flavor demo
```
The file is `apps/pos/build/app/outputs/flutter-apk/app-demo-release.apk`.

```bash
cd ../admin
flutter build web --release --dart-define=APP_ENV=demo
cd ../../firebase
firebase deploy --only hosting --project clientdemo
```
The console is then at `https://caramel-cottage-demo.web.app`.

Check that the right project is in use before you share anything: sign in to the demo site as the Admin, then open the Firebase console of **caramel-cottage-demo** and see the user and the seeded data there. The real project must still be empty.

## E. Share the APK
**Firebase App Distribution** (free), in the trial project: Release & Monitor → App Distribution → Get started → pick the Android app → upload `app-demo-release.apk` → add the client's email as a tester. He installs from the email link.

Fallback: send the APK as a WhatsApp document or a Google Drive link. He taps it and allows "Install unknown apps" for that app first.

## F. What to tell the client
- This is a trial copy. Its data will be erased after the demo, so use made-up customer numbers.
- Printing is only part of the trial if a printer is paired.
- When something goes wrong: a screenshot and a one-line note to you.

## G. After the demo: switch it off
Do these in order. The first two work at once; the last makes it permanent.
1. **Kill switch.** Replace the trial project's rules with deny-all and redeploy, so every demo APK and the demo site can no longer read or write anything:
```bash
cd firebase
cp firestore.rules firestore.rules.backup        # do not commit this
printf "rules_version = '2';\nservice cloud.firestore { match /databases/{d}/documents { match /{document=**} { allow read, write: if false; } } }\n" > firestore.rules
firebase deploy --only firestore:rules --project clientdemo
git checkout firestore.rules                      # restore the real rules in the repo
rm firestore.rules.backup
```
2. **Authentication** (trial project) → Sign-in method → disable Email/Password, so nobody can sign in either.
3. **Delete the project.** Firebase console (trial project) → Project settings → Delete project. Google keeps it for about 30 days before erasing it for good.
4. Delete the service-account key file, and remove the demo APK from App Distribution or Drive.

Open the demo app afterwards and check it shows an error and not a login. The real project, the keystore and all code are unaffected.

## H. The real launch (later)
Repeat B to E against `caramel-cottage-retail` (`--project prod`, `npm run seed -- --project caramel-cottage-retail --yes-really`, `flutter build apk --release` without `--flavor demo` for `app-prod-release.apk`, and `flutter build web --release` for the admin site on `caramel-cottage-retail.web.app`). Before real customers, restrict both API keys in Google Cloud Console (Credentials): the Android key to package `in.caramelcottage.pos` and the release keystore's SHA-1 (`keytool -list -v -keystore app/caramel-release.jks`), and the web key to your hosting origins. Put a notice at the counter saying why customers' numbers are collected.
