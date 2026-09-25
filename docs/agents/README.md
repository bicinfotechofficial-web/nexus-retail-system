# Phase 1 Agents

Five build agents work in parallel, each in its own session and on its own branch. This file holds the rules they all share. Each agent also gets its own brief:

| Agent | Brief | Owns | Branch |
|---|---|---|---|
| Backend | [BACKEND](BACKEND.md) | `firebase/`, `packages/data/` (except `src/api/`) | `agent/backend` |
| Printer | [PRINTER](PRINTER.md) | `packages/printer/` (except `src/api.dart`) | `agent/printer` |
| POS | [POS](POS.md) | `apps/pos/` (except `integration_test/`) | `agent/pos` |
| Admin | [ADMIN](ADMIN.md) | `apps/admin/` | `agent/admin` |
| QA | [QA](QA.md) | `test/e2e/`, `apps/pos/integration_test/`, `docs/QA-FINDINGS.md` | `agent/qa` |

## Starting an agent (for Bicy)
1. Open a new Claude Code session with this GitHub repo attached, so it can push to its branch.
2. Paste this, with the agent's name filled in:

   > You are the **<Agent>** agent for the nexus-retail-system repo. Read `docs/agents/README.md` and then `docs/agents/<AGENT>.md`, and follow them. Start with the first task in your brief.

3. Each agent works through its task list and pushes its branch. It tells you when a task is ready for review. Bring that to the central agent.

## Rules for every agent
**Read first:** `docs/00-DECISIONS.md` (the Locked rows are the contract), `docs/02-DATA-MODEL.md`, `docs/04-PERMISSIONS.md`, and whatever else your brief lists.

**Stay in your lane.**
- Write only inside the directories your brief gives you. You may read everything.
- `packages/core`, `packages/data/lib/src/api/`, `packages/printer/lib/src/api.dart`, `docs/` (except your own status cells in `06-TASKS.md`), the root `pubspec.yaml`, `analysis_options.yaml` and `tool/` belong to the central agent.
- If a contract is missing something, wrong, or blocks you, don't work around it. Add a row to `docs/CHANGE-REQUESTS.md` (what, why, options), push, and tell Bicy. Build against the current contract, or a local stub, until it's decided.

**Branches and commits.**
- Branch from `main`: `git switch -c agent/<name> origin/main`. Rebase on `origin/main` when the central agent merges something you need.
- Commit as **Bicy** (`bicinfotechofficial-web@users.noreply.github.com`). Set it with `git config user.name Bicy` and `git config user.email bicinfotechofficial-web@users.noreply.github.com`.
- No `Co-Authored-By` or other tool-attribution trailers, and no personal names in code, comments, docs, test data or commit messages. Use role names ("Admin", "Store Manager").
- Start commit messages with the task ID: `BE-3: bills create and cancel rules`.
- In `docs/06-TASKS.md`, change only the Status cell of your own rows (`WIP` when you start, `REVIEW` when it's pushed and green).

**Quality bar.**
- `tool/check.sh` must pass before every push: format, analyze with infos as errors, tests.
- Every task's "Done when" check in `06-TASKS.md` must be demonstrably met. Say how in the task's final commit message.
- Money is `Money` (paise), quantities are `int` base units, dates come from `BusinessDate`, and paths and IDs come from `FirestorePaths` and `Ids`. Never build a path string or do money arithmetic by hand; `packages/core` already has it.

**Dependencies.**
- Add third-party packages to your own member's `pubspec.yaml`, then run `flutter pub get` at the root. Commit the root `pubspec.lock` with it.
- Prefer the packages your brief names. For anything else, pick an actively maintained package that supports Android 12+ and the current Flutter stable, and say why in the commit message.

**Environment.** Flutter 3.47.5 stable (Dart 3.13). The Firebase emulator needs Node 20+ and Java 21. See `docs/SETUP-FIREBASE.md`. Local runs and tests use the `demo-caramel-cottage` project, never the real one.
