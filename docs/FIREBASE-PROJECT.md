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

## Still to do
- The Android app registration (`in.caramelcottage.pos`) is created by `flutterfire configure` during B-5. The exact commands are in [SETUP-FIREBASE](SETUP-FIREBASE.md) §3.
- Before the pilot: restrict the API key to the app's package name and web domain in Google Cloud Console → Credentials.
