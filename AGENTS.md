# Working agreement for agents

This file tells coding agents (Claude Code, Codex and others) how to work in this repository. It is the single source: `CLAUDE.md` only imports it.

The owner leads the product and reviews at checkpoints. Agents work autonomously in between, inside the limits below.

## Repository map

| Path                           | What it holds                                                                  |
| ------------------------------ | ------------------------------------------------------------------------------ |
| `apps/ios/`                    | iOS app (SwiftUI, SwiftData), its kit, widget and tests (XcodeGen)             |
| `supabase/`                    | Postgres migrations, seed and pgTAP tests                                      |
| `docs/training-data-format.md` | Neutral training data format: the contract between app, database and importers |
| `docs/database-schema.md`      | How the format maps to database columns                                        |
| `docs/deploy.md`               | Environments and deployment                                                    |

## Autonomy

### Agents do without asking

1. Work through the agreed plan, issue by issue, test first.
2. Take small product or technical decisions: choose the most reversible option, carry on, and record it under "Decisions taken without asking" in the issue's task document. The owner reviews them in batch at the next checkpoint.
3. Commit work units on working branches (`feat/…`, `fix/…`, `docs/…`, `chore/…`) and push those branches.
4. Open pull requests as drafts and fix CI failures on their own branches.
5. Keep the design mockup in sync with decisions as they are taken.
6. Run everything local: tests, the iOS simulator (one test run at a time), the local Supabase stack, and clean up their scratch files.

### Agents always ask first

1. Merging into `develop` or `main`, releasing, deploying, or marking a draft pull request ready for review.
2. Any operation on a remote Supabase project (dev or prod).
3. Product decisions that clearly change what the user sees, or that would be hard to undo once merged.
4. Credentials, secrets, personal data, calls to third-party services that are not read-only, deleting branches or data.
5. Large multi-agent runs.

### Reporting

- After each task: a short summary of what is done, how it was verified, and what is left.
- At each checkpoint (an issue ready for the owner): the decisions taken without asking and everything the owner needs to decide, together.
- When blocked: ask only about the blocker and keep working on what does not depend on it.

## Definition of Ready

An issue is ready to start when it has acceptance criteria written as **Given / When / Then**. If it has none, the agent writes them before any code and lists them for the owner's review at the next checkpoint.

## Acceptance tests

Every acceptance criterion has at least one automated test that proves it, and the owner tests a feature by hand only after all of them pass.

- **Test first.** Write the acceptance test from the criterion, run it and see it fail for the expected reason, then implement until it passes.
- **Every kind that applies:**
  - unit tests for logic (Swift Testing);
  - integration tests for persistence (SwiftData) and for the database (pgTAP: schema, constraints, row-level security);
  - end-to-end UI tests (XCUITest, through the screen objects in `apps/ios/TNWTrackerUITests/Screens/`) for every user flow the issue adds or changes;
  - an accessibility audit (`XCUIApplication.performAccessibilityAudit()`) on every screen the issue adds or changes;
  - no missing translations in `Localizable.xcstrings` for the strings the issue adds.
- **Traceability.** The issue's task document and the pull request carry a table: criterion → test → observed result.
- **Evidence.** UI tests attach screenshots of the final state of each flow, so the owner can see the result before opening the app.
- **Green before the owner tests.** All CI checks pass on the branch before the owner is asked to try anything.

## Test quality

A test is only worth keeping if it fails when the behaviour it covers breaks.

- **Real over fake.** Use the real implementation whenever it runs in a test: the SwiftData store in memory with the real repositories, and the local Supabase stack for the database.
- **Test doubles only at boundaries** the test cannot control: network, clock, authentication, system services (Live Activities, notifications, HealthKit). Never replace the app's own code with a double; if a unit is hard to test without one, change its design instead.
- **Assert outcomes, not calls.** Check the resulting state, output or stored data, not which functions a double received, unless the call itself is the observable effect (for example, a request sent to the network).
- **Strong assertions.** Each test checks every observable effect of its rule (value, persisted data, error), not just that something is not nil.
- **Mutation testing.** At each checkpoint, run mutation testing (Muter for Swift) on the files the change touched. Every surviving mutant gets a new or stronger test, or a written reason why it is equivalent.
- **Review.** The independent review includes the tests: for each criterion, would the test fail if the behaviour broke, and is every double justified?

## Definition of Done

A change is done when:

1. every acceptance criterion has a passing automated test (table above);
2. CI is green: commit messages, formatting, SwiftLint, iOS unit and UI tests, `supabase test db`, format examples, secret scan (gitleaks), CodeQL;
3. a new table has row-level security tests for its owner and for another user;
4. an independent reviewer (an agent that did not write the change) has checked the diff and its tests against the criteria and its findings are fixed or listed for the owner;
5. mutation testing on the changed files leaves no unexplained surviving mutant;
6. docs that describe the behaviour are updated in the same change;
7. the decisions taken without asking are listed for the owner.

## Commands

| Check             | Command                                                                                                                                    |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| iOS unit tests    | `xcodebuild test -scheme TNWTracker -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TNWTrackerTests` (from `apps/ios/`) |
| iOS UI tests      | same, with `-only-testing:TNWTrackerUITests`                                                                                               |
| iOS Release build | `xcodebuild build -scheme TNWTracker -configuration Release -destination 'generic/platform=iOS Simulator'`                                 |
| Database tests    | `supabase start`, `supabase db reset --local`, `supabase test db`                                                                          |
| Format examples   | `python docs/training-data/validate.py`                                                                                                    |
| Formatting        | `pnpm format:check`                                                                                                                        |

Run one simulator test run at a time. If the first run fails to launch the app on the simulator, shut the simulator down, boot it again and rerun.

## Commits and pull requests

- Conventional Commits, checked by commitlint. Allowed scopes: `ios`, `db`, `ci`, `deps`, `release`; docs-only commits use no scope.
- One commit per work unit, with its tests and docs. Aim for about 400 changed lines per pull request; split larger changes into chained pull requests where the parts still build and pass on their own.
- No AI attribution or `Co-Authored-By` lines in commits.

## Privacy

This repository is public.

- Never commit personal training data, body metrics, health data, credentials, session tokens or captured network traffic.
- Never name third-party providers, gyms or their platforms, nor use their field names. Use neutral names (the format's `<kind>-<codename>` provider slugs).
- Examples, fixtures, screenshots and sample data use invented data only.
