# Firestore rules and tests

`firestore.rules` enforces `docs/04-PERMISSIONS.md`. The suite under `test/` proves it on the Firestore emulator (BE-1 to BE-6).

## Running the tests
Once, and after `package-lock.json` changes:

```bash
cd firebase
npm ci
```

Then either start the emulator yourself and run the suite against it (what `tool/check.sh --e2e` does):

```bash
firebase emulators:start --only firestore   # terminal 1
npm test                                     # terminal 2 (npm run test:watch to re-run on save)
```

or let the Firebase CLI start and stop an emulator around one run:

```bash
npm run test:emulator
```

The tests use the `demo-caramel-cottage` project and **clear its Firestore data before every test**, so don't keep hand-made emulator data you care about while they run. The emulator address comes from `FIRESTORE_EMULATOR_HOST` if it is set, otherwise from `firebase.json`. The rules are read from `firestore.rules` on disk at the start of each test file, so there's no need to restart the emulator after editing them.

## Layout
| Path | What it is |
|---|---|
| `test/support/fixtures.js` | Roles, locations and the test actors. Roles are parsed from `packages/core/lib/src/permissions.dart`, so they can't drift from the app's permission sets |
| `test/support/env.js` | `useRulesEnv()`: one test environment per file, and a clean, seeded database before each test. `t.db('<actor>')` gives a client acting as that actor with the rules on; `t.arrange(fn)` writes setup state with the rules off |
| `test/*.test.js` | One file per rule group: `org` (#1–4) |

## Actors
| Key | uid | Role | Location | Active |
|---|---|---|---|---|
| `admin` | `admin` | ADMIN | all | yes |
| `smPtb` | `sm-ptb` | STORE_MANAGER | PTB | yes |
| `smMnj` | `sm-mnj` | STORE_MANAGER | MNJ | yes |
| `disabled` | `sm-ptb-disabled` | STORE_MANAGER | PTB | no |
| `noProfile` | `no-profile` | signed in, no `users` doc | — | — |
| `anonymous` | — | not signed in | — | — |

Both fixture locations start with `nextDeviceNo: 0` and use the offline override PIN `24681357`.
