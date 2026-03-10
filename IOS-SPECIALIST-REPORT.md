# Destro (Mystro) iOS App — Specialist Report

**App:** Destro · **Bundle ID:** `online.nextelevenstudios.destro` · **Scheme:** Destro · **Project:** `ios/Mystro.xcodeproj`

---

## 1. Structure, Code Quality & Patterns

**Layout**
- **Targets:** Destro (app), DestroWidgetExtension, DestroTests. Main sources in `ios/Mystro/Mystro/`.
- **Key modules:** ProdDaemon (state machine), ServiceReadinessStore, CriteriaEngine, FilterConfig, AccessibilityOfferSource, AccessibilityActionExecutor, DashboardViewController, AppDelegate — all present and correctly scoped.

**Swift patterns**
- **State machine:** `DaemonState` enum in `DaemonTypes.swift`; `ProdDaemon.state` with `didSet` for metrics; transitions idle → scanning → decisioning(app) → cooldown (or error).
- **Protocols:** `OfferSource` and `ActionExecutor` with fallbacks (e.g. `AdaptiveFallbackOfferSource`, `FallbackActionExecutor`) for AX/Vision and AX/HID.
- **DI:** Daemon receives `offerSource` and `actionExecutor` from AppDelegate; no formal container. Heavy use of singletons (`FilterConfig`, `GeofenceManager.shared`, `DynamicRuleEngine.shared`, `EarningsTracker.shared`, `DashboardRelay.shared`, `LogBuffer.shared`) — reduces test isolation.

**Code quality**
- No force unwraps (`as!`, `try!`, `value!`) in app code.
- `[weak self]` used in Task/notification/closure handlers (ProdDaemon, DashboardViewController, AppDelegate, DashboardRelay) to avoid retain cycles.
- **Gap:** `ServiceReadinessStore.discoverPID` uses `Thread.sleep(forTimeInterval: 0.15)` on the calling thread — blocks the scan loop; consider async delay or moving to a background queue.

---

## 2. Build & Config (TestFlight Readiness)

| Item | Status |
|------|--------|
| **ExportOptions.plist** | `ios/ExportOptions.plist`: `method` app-store, `teamID` L35VLYNTLK, `signingStyle` automatic ✓ |
| **project.pbxproj** | Destro uses `Mystro/Mystro/Info.plist`, `Mystro/Mystro/Mystro.entitlements`; deployment 17.0; bundle ID `online.nextelevenstudios.destro` ✓ |
| **Info.plist** | NSAccessibilityUsageDescription, NSLocationWhenInUseUsageDescription, UIBackgroundModes (fetch, processing), URL scheme `destro`, Live Activities, ATS allows arbitrary loads ✓ |
| **Entitlements** | App: app group `group.com.destro.app`, sandbox, location, network client/server. Widget: separate MystroWidget.entitlements ✓ |

**TestFlight:** Export config is TestFlight-ready (app-store + teamID). No Fastlane/GHA or other CI in repo; manual archive + upload.

---

## 3. Accessibility, Memory & Threading

**Accessibility**
- **Usage:** AX used for offer detection (`AccessibilityOfferSource` via `AXLoader` dlopen) and Accept/Decline (`AccessibilityActionExecutor` via `AXActionHelper`). User must enable Destro in Settings → Accessibility.
- **Info.plist:** `NSAccessibilityUsageDescription` clearly explains reading Uber/Lyft screens for trip requests and automate accept/decline ✓
- **Mystro alignment:** Own URL scheme `destro://`, daemon cycles driver URLs and returns to app URL; confirm-accept path uses same pattern. No private APIs for switching; URL-scheme fallback in place.

**Threading**
- UI updates: `DispatchQueue.main.async` in DashboardViewController and DashboardRelay; `MainActor.run` in ProdDaemon and MystroIntents for AppDelegate/daemon access. Dedicated queues: `destro.dashboard.relay`, `destro.logbuffer`.
- **Risk:** Dashboard gets daemon via `(UIApplication.shared.delegate as? AppDelegate)?.daemon`; no `@MainActor` on DashboardViewController — relies on callers dispatching to main. Consider annotating UI-facing types with `@MainActor` for clarity and safety.

**Memory**
- Consistent `[weak self]` in async paths; no obvious retain cycles identified.

---

## 4. High-Impact Improvements

1. **Remove blocking sleep in PID discovery**  
   Replace `Thread.sleep(forTimeInterval: 0.15)` in `ServiceReadinessStore.discoverPID` with `Task { try? await Task.sleep(nanoseconds: ...) }` or a non-blocking delay on a background queue so the scan loop is not blocked.

2. **Adopt `@MainActor` for UI and AppDelegate/daemon access**  
   Mark `DashboardViewController` and `AppDelegate` (or daemon accessors) as `@MainActor` where appropriate to make main-thread requirements explicit and avoid accidental background access.

3. **Tighten ATS**  
   Info.plist has `NSAllowsArbitraryLoads = true`. Restrict to specific domains (e.g. dashboard/API endpoints) via `NSExceptionDomains` to reduce risk and satisfy review if questioned.

4. **Add a UI test target**  
   No UI tests today. A minimal XCTest UI target for critical flows (e.g. open app → link service → GO → stop) would improve regression safety before TestFlight builds.

5. **Introduce a lightweight DI or shared view model for the daemon**  
   Replace optional chaining on `AppDelegate` for daemon with a single injectable dependency (e.g. environment object or shared view model) so Dashboard and intents have a clear, testable dependency.

---

## 5. Summary

Destro is a well-structured Mystro-style driver automation app: clear state machine, pluggable offer/action sources, and sensible use of Accessibility and URL schemes. Build and entitlements are correctly set for TestFlight. Main gaps are blocking sleep in PID discovery, missing `@MainActor` clarity, broad ATS, no UI tests, and global singletons. Addressing the five items above would improve robustness, review readiness, and maintainability with limited scope.
