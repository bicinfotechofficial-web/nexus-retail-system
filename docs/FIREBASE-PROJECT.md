# Firebase Project

| Setting | Value |
|---|---|
| Project ID | `caramel-cottage-retail` |
| Project number | `137960797974` |
| Plan | Spark (no cost) |
| Auth | Email/Password enabled (email-link sign-in off) |
| Firestore | `(default)` database, **Standard** edition, `asia-south1` (Mumbai), production mode (deny-all until our rules are deployed) |
| Backups | None. Scheduled backups need the Blaze plan (D-021) |

## Web app `admin-web`
These values aren't secret: in a Firebase web config, access is controlled by the Security Rules, not by the keys.

```js
const firebaseConfig = {
  apiKey: "AIzaSyDLcgxUujnY6NZCGXXQHsORVTQ9lHIzZNs",
  authDomain: "caramel-cottage-retail.firebaseapp.com",
  projectId: "caramel-cottage-retail",
  storageBucket: "caramel-cottage-retail.firebasestorage.app",
  messagingSenderId: "137960797974",
  appId: "1:137960797974:web:e16ab706577d29c3cc0237"
};
```

## Android app `in.caramelcottage.pos`
Registered by `flutterfire configure` in B-5 (D-023).

| Setting | Value |
|---|---|
| App ID | `1:137960797974:android:0bef52460e74598fcc0237` |
| Config files | `apps/pos/android/app/google-services.json`, `apps/pos/lib/firebase_options.dart` |

The admin app's `apps/admin/lib/firebase_options.dart` uses the `admin-web` app above.

## Still to do
- Before the pilot: restrict both API keys in Google Cloud Console → Credentials. The Android key (starts `AIzaSyATX`) to package `in.caramelcottage.pos` plus the release signing certificate (C-8), and the web key (starts `AIzaSyDLc`) to the admin console's domain.
