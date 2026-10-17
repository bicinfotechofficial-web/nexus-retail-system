# Putting the app online for the client to test (C-8, first pass)

This puts the real Firebase project (`caramel-cottage-retail`, Spark plan) in use, so the client can try the POS on his phone and the admin console on a laptop, end to end. Run every command in Git Bash from the repo root unless it says otherwise.

Test data and real data share one project, so **make a DEMO location first** (step 6) and keep all trial bills there.

## 1. Deploy the rules and indexes
The production database is deny-all until this runs. The rules tests (425) and the data tests are green.

```bash
cd firebase
firebase login
firebase deploy --only firestore --project prod
```

## 2. Seed production
Needs a service-account key: Firebase console → Project settings → Service accounts → **Generate new private key**. Save it **outside the repo** (for example `D:\keys\cc-admin.json`), and delete it when the seed is done.

```bash
cd firebase
npm ci
export GOOGLE_APPLICATION_CREDENTIALS="D:/keys/cc-admin.json"
export SEED_ADMIN_EMAIL="<the Admin's real email>"
npm run seed -- --project caramel-cottage-retail --yes-really
```
It asks for the Admin password (8+ characters) and an 8-digit override PIN. It creates the roles, the Admin, locations PTB and MNJ and the sample catalog. It is safe to run again.

## 3. Create a signing key (once) and keep it safe
An app signed with a different key can't update one signed with another, and the API-key restriction (step 8) needs this key's fingerprint. **Back the keystore file and its passwords up outside the repo. If you lose them, every phone needs an uninstall and reinstall.**

```bash
cd apps/pos/android
keytool -genkey -v -keystore app/caramel-release.jks -alias caramel -keyalg RSA -keysize 2048 -validity 10000
```
Then create `apps/pos/android/key.properties` (already in `.gitignore`, never commit it):
```
storeFile=app/caramel-release.jks
storePassword=<the keystore password>
keyAlias=caramel
keyPassword=<the key password>
```

## 4. Build the release APK
```bash
cd apps/pos
flutter build apk --release
```
The file is `apps/pos/build/app/outputs/flutter-apk/app-release.apk`. Release builds refuse `USE_EMULATOR`, so this one talks to the real project.

## 5. Put the admin console online
```bash
cd apps/admin
flutter build web --release
cd ../../firebase
firebase deploy --only hosting --project prod
```
The console appears at `https://caramel-cottage-retail.web.app`. If Hosting isn't enabled yet, the first deploy asks you to turn it on (free on Spark).

## 6. Set up the demo in the console
1. Sign in as the Admin. Locations → add **DEMO** (code `TST`), with its own override PIN.
2. Users → New Store Manager for the client, scoped to `TST`.
3. Catalog: check the sample products, adjust names and prices for the demo.
4. Stock → on the phone, use Produce or Adjust so the cakes have stock.

## 7. Share the APK
**Firebase App Distribution** (free): Firebase console → Release & Monitor → App Distribution → Get started → select the Android app → upload `app-release.apk` → add the client's email as a tester. He gets an email and installs from a link.

Fallback: upload the APK to Google Drive or send it by WhatsApp as a document, and he taps it on the phone. He must allow "Install unknown apps" for that app first.

## 8. Restrict the API keys (before real customers, not blocking a private test)
Google Cloud Console → APIs & Services → Credentials. Restrict the Android key to package `in.caramelcottage.pos` plus the **release keystore's SHA-1** (`keytool -list -v -keystore app/caramel-release.jks`), and the web key to your `*.web.app` and `*.firebaseapp.com` origins.

## 9. Tell the client
- This is a trial: use the DEMO location, and use **made-up customer numbers** (the app stores them).
- Printing isn't in this trial unless a printer is paired.
- Everything that goes wrong: screenshot and a one-line note, sent to you.
