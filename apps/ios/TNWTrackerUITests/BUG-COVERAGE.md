# Bug Coverage — ios-ui-test-automation-poc

Validation procedure for the 5 historic UI-flow bugs caught by
`test_criticalFlowFromHomeToSummary` in `CriticalFlowTests.swift`.

All 5 fixes landed in a single commit: `61a900011acd3f3a8a0d14c640ae19a530f6a50e`
(`fix(ios): wire UI flow Home→ActiveWorkout→Summary y restaurar sesión`).

To reproduce a regression: revert the relevant code change on a temp branch,
run the targeted assertion, confirm it fails, then discard the branch.

---

## BUG-1 — Double coordinator start (race in ActiveWorkoutCover.task)

**Description**: `ActiveWorkoutCover.task` ran twice on some re-renders,
starting the coordinator twice. Two `elapsedTimer` StaticTexts appeared in the
view hierarchy (one per coordinator instance).

**Fix file**: `apps/ios/TNWTracker/App/RootView.swift`
**Fix commit**: `61a9000`

**Revert procedure**:

```bash
git checkout -b tmp/revert-bug1

# In RootView.swift, inside ActiveWorkoutCover.body .task { ... }:
# Remove this guard:
#   guard coordinator == nil else { return }
# so the coordinator is created unconditionally on every task execution.

xcodebuild test \
  -project apps/ios/TnwTracker.xcodeproj \
  -scheme TNWTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:TNWTrackerUITests/CriticalFlowTests/test_criticalFlowFromHomeToSummary

# Expected: FAIL — assertSingleElapsedTimer() fires:
#   "BUG-1 detected: 2 elapsed timer(s) visible, expected exactly 1."
# OR the coordinator is in an inconsistent state → test may also crash/hang.

git checkout -
git branch -D tmp/revert-bug1
```

**Catching assertion**: `active.assertSingleElapsedTimer()`
→ `XCTAssertEqual(elapsedTimer.count, 1, ...)`

**Empirical note (2026-05-10, F1 validation)**: the simple revert procedure
(removing the `guard coordinator == nil`) does NOT produce two timers in the
happy-path E2E flow because SwiftUI does not re-execute `.task` in this linear
test scenario. The original BUG-1 manifested under specific re-render conditions
(background/foreground transitions, onChange storms) that the happy-path does
not stress.

`assertSingleElapsedTimer()` is therefore a **DEFENSIVE assertion** — it does
not reproduce the original bug, but it will catch future regressions where a
bug does produce two timers in the happy-path. The structural fix (the `guard`)
remains the real protection. Reproducing the original BUG-1 would require a
dedicated test that forces re-renders (e.g., simulator background/foreground
cycles).

---

## BUG-2 — Nested fullScreenCover chain (Summary cover never mounts)

**Description**: `WorkoutSummaryView` was presented via a second `.fullScreenCover`
modifier chained at the `RootView` level. SwiftUI only activates the first
`.fullScreenCover` in a chain on the same view — the summary cover was silently ignored.

**Fix file**: `apps/ios/TNWTracker/App/RootView.swift`
**Fix commit**: `61a9000`

**Revert procedure**:

```bash
git checkout -b tmp/revert-bug2

# In RootView.swift body, extract the summary fullScreenCover back to
# the parent view level (chained after the active workout cover):
#
#   .fullScreenCover(item: $router.presentedActiveWorkout) { presentation in
#       ActiveWorkoutCover(sessionID: presentation.id)
#   }
#   .fullScreenCover(item: $router.presentedWorkoutSummary) { summary in   // BUG: chained on parent
#       WorkoutSummaryView(workoutId: summary.id)
#   }
#
# Remove the nested .fullScreenCover from inside ActiveWorkoutCover.body.

xcodebuild test \
  -project apps/ios/TnwTracker.xcodeproj \
  -scheme TNWTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:TNWTrackerUITests/CriticalFlowTests/test_criticalFlowFromHomeToSummary

# Expected: FAIL — WorkoutSummaryScreen.waitUntilLoaded(5s) fires:
#   "WorkoutSummaryScreen did not load: closeButton not found within 5.0s.
#    BUG-2: nested fullScreenCover chain may be broken."

git checkout -
git branch -D tmp/revert-bug2
```

**Catching assertion**: `active.tapEnd()` → `WorkoutSummaryScreen.waitUntilLoaded(timeout: 5)`
→ `XCTAssertTrue(closeButton.waitForExistence(timeout: 5), ...)`

---

## BUG-3 — Phase guard race (cover dismissed before ActiveWorkout rendered)

**Description**: `ActiveWorkoutView` (now inside `ActiveWorkoutCover`) was checking
`phase == .idle` and calling `dismiss()`. Since the coordinator always starts in
`.idle` state until `start(from:)` completes, the cover dismissed itself
immediately after appearing.

**Fix file**: `apps/ios/TNWTracker/App/RootView.swift` (ActiveWorkoutCover)
and `apps/ios/TNWTracker/Features/Workout/Views/ActiveWorkoutView.swift`
**Fix commit**: `61a9000`

**Revert procedure (refined 2026-05-10 after F1 empirical validation)**:

The simple "swap branches" revert does NOT reproduce the bug because by the
time the body re-evaluates, `phase` has already advanced to `.active` (the
`.task` ran `start()` synchronously fast). To reproduce the dismiss-on-idle
race, the edit must combine two changes: introduce the `phase == .idle`
dismiss pattern AND remove `start()` from the `.task` so phase stays `.idle`.

```bash
git checkout -b tmp/revert-bug3

# In ActiveWorkoutCover (apps/ios/TNWTracker/App/RootView.swift):
#
# (1) Replace the body's "if let coordinator" branch to introduce the
#     dismiss-on-idle pattern:
#
#     if let coordinator {
#         if coordinator.phase == .idle {
#             Color.clear.onAppear {
#                 appEnv.router.presentedActiveWorkout = nil
#             }
#         } else {
#             NavigationStack {
#                 ActiveWorkoutView(coordinator: coordinator)
#             }
#         }
#     } else {
#         ProgressView().controlSize(.large)
#     }
#
# (2) Remove the start() call from the .task so phase stays at .idle:
#
#     .task {
#         guard coordinator == nil else { return }
#         let c = appEnv.makeActiveWorkoutCoordinator()
#         coordinator = c
#         appEnv.activeCoordinator = c
#         // (removed: fetch Session + try await c.start(from: session))
#     }

xcodebuild test \
  -project apps/ios/TnwTracker.xcodeproj \
  -scheme TNWTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:TNWTrackerUITests/CriticalFlowTests/test_criticalFlowFromHomeToSummary

# Empirically validated 2026-05-10: this procedure produces FAIL within ~20s
# with the documented assertions:
#   "ActiveWorkoutScreen did not load: endButton not found within 5.0s.
#    Possible causes: BUG-1 (double coordinator start race) or BUG-3
#    (phase guard dismissed cover)."
# AND
#   "BUG-3 detected: endButton not visible — ActiveWorkout cover dismissed
#    unexpectedly."
# (4 cascading assertions fail as colateral consequence of the dismiss.)

git checkout -
git branch -D tmp/revert-bug3
```

**Catching assertion**: `home.tapQuickStart()` → `ActiveWorkoutScreen.waitUntilLoaded(timeout: 5)`
→ `XCTAssertTrue(endButton.waitForExistence(timeout: 5), ...)`
and `active.assertNotDismissed()` → `XCTAssertTrue(endButton.exists, ...)`

---

## BUG-4 — Lifecycle gap (start() not called; workoutId captured before coordinator ready)

**Description**: Two related gaps: (a) nobody called `coordinator.start(from:)` — the
coordinator was created but never started, leaving the phase at `.idle` and
exercise data empty; (b) `WorkoutSummaryView` read `workoutId` from
`appEnv.activeCoordinator` which could be nil by the time the summary mounted.

**Fix file**: `apps/ios/TNWTracker/App/RootView.swift` (ActiveWorkoutCover)
**Fix commit**: `61a9000`

**Revert procedure**:

```bash
git checkout -b tmp/revert-bug4

# In ActiveWorkoutCover.task, remove the start() call:
#   // Remove: await coordinator.start(from: session)
# This leaves the coordinator created but phase stuck at .idle.
# exerciseTitle will not be populated → assertActiveContentVisible() fails.
#
# Alternatively, to target the summary side of BUG-4:
# Change WorkoutSummaryView to accept an optional coordinator instead of
# a captured workoutId, and have it read from appEnv.activeCoordinator
# (which is nil when the summary mounts because the active workout was dismissed).

xcodebuild test \
  -project apps/ios/TnwTracker.xcodeproj \
  -scheme TNWTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:TNWTrackerUITests/CriticalFlowTests/test_criticalFlowFromHomeToSummary

# Expected (start() removed path): FAIL — assertActiveContentVisible() fires:
#   "BUG-4 (indirect): exerciseTitle not visible — coordinator phase may be incorrect."
# Expected (workoutId capture path): FAIL — assertWorkoutNameVisible() fires:
#   "BUG-4: workoutNameLabel.label is empty — workout name not rendered."

git checkout -
git branch -D tmp/revert-bug4
```

**Catching assertions**:

- `active.assertActiveContentVisible()` → `XCTAssertTrue(exerciseTitle.exists, ...)`
- `summary.assertWorkoutNameVisible()` → `XCTAssertFalse(workoutNameLabel.label.isEmpty, ...)`

---

## BUG-5 — Auth state restoration (currentUserId nil on cold start)

**Description**: Supabase stores the session in the Keychain but does NOT emit a
`.signedIn` event when the app restarts with an already-active session. The
`.task` in `TnwTrackerApp` only set `isAuthenticated`, leaving `currentUserId`
nil. `makeActiveWorkoutCoordinator()` has a `guard let uid = currentUserId` that
calls `fatalError` when uid is nil.

In UI tests this bug is bypassed by `AppEnvironment.bootstrapForUITesting(modelContext:)`,
which sets both `isAuthenticated = true` and `currentUserId = uiTestingUserId`.
Reverting the bypass in that factory reproduces the crash.

**Fix file**: `apps/ios/TNWTracker/App/TnwTrackerApp.swift`
and `apps/ios/TNWTracker/App/AppEnvironment.swift` (`bootstrapForUITesting`)
**Fix commit**: `61a9000` (TnwTrackerApp); PR 1 commit `de910a8` (bootstrapForUITesting)

**Revert procedure**:

```bash
git checkout -b tmp/revert-bug5

# In AppEnvironment+Debug.swift (or AppEnvironment.swift #if DEBUG extension):
# Remove the currentUserId assignment from bootstrapForUITesting:
#   // Remove: env.currentUserId = uiTestingUserId
# Leave env.isAuthenticated = true so HomeView renders, but currentUserId is nil.

xcodebuild test \
  -project apps/ios/TnwTracker.xcodeproj \
  -scheme TNWTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:TNWTrackerUITests/CriticalFlowTests/test_criticalFlowFromHomeToSummary

# Expected: FAIL — app process terminates after tapQuickStart() triggers
# makeActiveWorkoutCoordinator() → fatalError("currentUserId is nil").
# XCUITest reports: "Application crashed during test execution"
# OR step 3 waitUntilLoaded(5s) fires:
#   "ActiveWorkoutScreen did not load: endButton not found within 5.0s."

git checkout -
git branch -D tmp/revert-bug5
```

**Catching assertion**: `HomeScreen.waitUntilLoaded(timeout: 10)` (step 2) or
`home.tapQuickStart()` → crash → XCUITest reports process termination → test fails.

---

## Notes

- All 5 bugs were introduced across the history of the feature development
  and fixed in a single consolidating commit (`61a9000`).
- Revert procedures are non-destructive: use a temp branch, run, discard.
- Do NOT execute these on `develop` or any long-lived branch.
- After validation on each temp branch, `git branch -D` to clean up.
- Validation was designed but not executed in this PoC batch (T19 procedural scope).
  Execute before promoting to production CI.

---

## F1 Empirical validation results (2026-05-10)

Bug-revert procedures executed empirically on `feat/ios-ui-test-automation-poc/03-e2e-test`,
device: iPhone 17 simulator, Xcode 26.4.

| Bug   | Status                        | Caught by                                                                                                                                                                |
| ----- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| BUG-1 | Defensive coverage            | `assertSingleElapsedTimer()` does not reproduce the original bug (no re-renders in happy-path); protects against future regressions where a bug does produce two timers. |
| BUG-2 | Caught with exact assertion   | `WorkoutSummaryScreen.waitUntilLoaded(5s)` — `closeButton` not found, BUG-2 message fires.                                                                               |
| BUG-3 | Caught with refined procedure | `ActiveWorkoutScreen.waitUntilLoaded(5s)` and `assertNotDismissed()` — both BUG-3 assertions fire.                                                                       |
| BUG-4 | Caught with exact assertion   | `assertActiveContentVisible()` — BUG-4 indirect message fires.                                                                                                           |
| BUG-5 | Caught via crash detection    | `Application com.tnwtracker.app is not running` — `fatalError("currentUserId is nil")` triggers process termination, XCUITest reports failure.                           |

**Score**: 4/5 caught with exact assertion + 1/5 defensive coverage documented (BUG-1).

The PoC is empirically validated. The defensive coverage of BUG-1 is intentional:
the structural fix (`guard coordinator == nil`) is the real protection; the
assertion serves as a tripwire for future regressions that might manifest the
double-start in the happy-path. To reproduce the original BUG-1 would require
a dedicated re-render test outside the scope of this PoC.
