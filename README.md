# Nexus Retail System — Caramel Cottage

A multi-location cake shop POS, inventory and admin system. It has a Flutter Android POS app with offline billing and a Bluetooth thermal printer, a Flutter Web admin console, and Firebase (Firestore + Auth) on the Spark plan.

**Status:** Phase 0 complete; Phase 1 starting. The data and printer contracts are in place (D-026), and the agent briefs are in [`docs/agents/`](docs/agents/README.md).

## Start here
| Doc | What it defines |
|---|---|
| [00-DECISIONS](docs/00-DECISIONS.md) | Every design decision and its status |
| [01-MVP-SCOPE](docs/01-MVP-SCOPE.md) | What the pilot includes and how it is accepted |
| [02-DATA-MODEL](docs/02-DATA-MODEL.md) | Firestore collections and fields |
| [03-SYNC-AND-OFFLINE](docs/03-SYNC-AND-OFFLINE.md) | Offline queue, bill numbering, idempotency, offline limit |
| [04-PERMISSIONS](docs/04-PERMISSIONS.md) | Roles, permissions, security-rule contract |
| [05-AGENT-PLAN](docs/05-AGENT-PLAN.md) | Who builds what, phases, definitions of done |
| [06-TASKS](docs/06-TASKS.md) | Every task, with owner, dependencies and done check |
| [SETUP-FIREBASE](docs/SETUP-FIREBASE.md) | Tools, the local emulator, and connecting the apps to Firebase |
| [agents/](docs/agents/README.md) | Phase 1 agent briefs and the rules every agent follows |

Requirements baseline: Caramel Cottage BRD v3 (`docs/requirements/BRD-v4.md`; v3 kept for history).

## Repository layout
| Path | Package | Owner |
|---|---|---|
| `packages/core/` | `nexus_core` (pure Dart) | Central |
| `packages/data/` | `nexus_data` | Backend |
| `packages/printer/` | `nexus_printer` | Printer |
| `apps/pos/` | `nexus_pos` (Android) | POS |
| `apps/admin/` | `nexus_admin` (web) | Admin |
| `test/e2e/` | `nexus_e2e` (pure Dart) | QA |
| `firebase/` | rules, indexes, seed (Node) | Backend |

All six Dart packages form one pub workspace: a single `pubspec.lock` at the root, and one `analysis_options.yaml` for everyone. Members must not add their own.

## Development
Built and checked with Flutter **3.47.5** stable (Dart 3.13). On Windows, run the scripts from Git Bash.

```bash
flutter pub get          # once, at the repo root; resolves every member
tool/check.sh            # boundaries, format, analyze (fatal infos), tests, core coverage gate
tool/check.sh --fix      # format in place, then check
tool/check.sh --e2e      # also test/e2e and firebase rules tests; needs the emulator
```

`tool/check.sh` must pass before any branch is merged into `main`.

Adding a dependency: add it to your own member's `pubspec.yaml` and run `flutter pub get` at the root. The root `pubspec.lock` changes with it; on a merge conflict in the lock file, the central agent re-runs `flutter pub get` on the merged pubspecs.
