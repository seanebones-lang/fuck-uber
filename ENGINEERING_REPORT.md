# Destro – Full Engineer's Report & Tech Stack

**Document version:** 1.2  
**Last updated:** March 2026  
**Purpose:** Handoff and iteration; technical reference for iOS automation (Uber/Lyft multi-app driver assistant).

---

## 1. Executive Summary

Destro is an **iOS-first automation app** for gig drivers (Uber, Lyft; extensible to DoorDash, Walmart Spark). It automates multi-apping: stay online on multiple apps, filter offers by custom rules, auto-accept/decline, and manage app switching to avoid conflicting rides. The codebase targets **jailbroken / Misaka26-style** devices (iOS 26.x, iPhone 16) for private API access (AX, HID, FrontBoard); it degrades gracefully on stock iOS.

**Misaka26 / iOS 26.2 (March 2026):** Full jailbreaks are not available for iOS 26.2 on A18 (iPhone 16). Misaka26 supports up to **iOS 26.1** and **26.2 beta 1** only; public 26.2 (and patches) have broken compatibility for many users. Private APIs may work partially or flakily—test on your exact firmware. See ITERATION_ROADMAP_V1.1.md.

**Deliverables:**
- Native iOS app (Swift, UIKit) with daemon, filters, dashboard UI, widget, Live Activity
- React + WebSocket dashboard for desktop monitoring
- Shared JS config/criteria and test/benchmark tooling in a pnpm monorepo

---

## 2. Tech Stack Overview

| Layer | Technology | Version / Notes |
|-------|------------|------------------|
| **iOS app** | Swift | 5.0 |
| **iOS UI** | UIKit | 100% programmatic (no storyboards); init(coder:) unimplemented in custom VCs. |
| **iOS widget** | SwiftUI + WidgetKit | — |
| **iOS deployment** | Xcode, xcodebuild | iOS 17.0+ target |
| **Dashboard server** | Node.js | — |
| **Dashboard client** | React | 18.2 |
| **Charts** | Recharts | 2.12.x |
| **Real-time** | WebSocket (ws) | 8.18 |
| **Monorepo** | pnpm workspaces | 10.13 |
| **Node** | — | ≥20 |
| **Tests (iOS)** | XCTest | — |
| **Tests (JS)** | Vitest, Jest, custom E2E/chaos | — |

**System / private dependencies (iOS):**
- **Accessibility.framework** (private, dlopen): AXUIElement* for reading other apps’ UI
- **IOKit.framework** (private): IOHIDEvent* for touch injection
- **FrontBoardServices / SpringBoardServices** (private): app foreground/background
- **GraphicsServices / UIKit** (private): UIGetScreenImage for screen capture (fallback)
- **Vision.framework** (public): VNRecognizeTextRequest for OCR fallback
- **CoreLocation** (public): geofencing
- **ActivityKit** (public, iOS 16.1+): Live Activities
- **App Intents** (public, iOS 16+): Siri / Shortcuts

---

## 3. Repository Structure

```
fuck-uber/
├── package.json              # Root pnpm workspace
├── pnpm-workspace.yaml       # Packages: shared, dashboard, deploy, test
├── README.md
├── dashboard.js              # Stub (Blessed TUI + WebSocket idea)
│
├── ios/
│   ├── Mystro.xcodeproj/     # Xcode project (scheme Destro; app + widget + test target)
│   ├── Destro/
│   │   ├── Destro/           # Main app target
│   │   │   ├── AppDelegate.swift
│   │   │   ├── ViewController.swift (legacy placeholder)
│   │   │   ├── DashboardViewController.swift  # Main UI
│   │   │   ├── ProdDaemon.swift                # Scan loop + state machine
│   │   │   ├── DaemonTypes.swift               # OfferData, OfferSource, ActionExecutor, RideDecision
│   │   │   ├── CriteriaEngine.swift            # Accept/reject rules
│   │   │   ├── FilterConfig.swift              # Persisted filters + HistoryStore + GeofenceZone
│   │   │   ├── ServiceReadinessStore.swift     # Per-service linked state + Keychain
│   │   │   ├── AccessibilityOfferSource.swift # AX-based screen read (private API)
│   │   │   ├── VisionOfferSource.swift        # OCR fallback
│   │   │   ├── HIDActionExecutor.swift        # Tap injection (private API)
│   │   │   ├── AppSwitcher.swift              # Foreground/background (private API)
│   │   │   ├── ConflictManager.swift         # Ride-accept → other app offline
│   │   │   ├── GeofenceManager.swift         # CoreLocation accept/avoid zones
│   │   │   ├── RidePredictor.swift           # Heuristic ride quality
│   │   │   ├── DynamicRuleEngine.swift       # Time/battery-based threshold tweaks
│   │   │   ├── EarningsTracker.swift         # Session/today earnings
│   │   │   ├── SyncManager.swift             # iCloud KV + export/import
│   │   │   ├── DestroLiveActivity.swift      # ActivityKit (iOS 16.1+)
│   │   │   ├── DestroIntents.swift           # App Intents (Siri/Shortcuts)
│   │   │   ├── Info.plist
│   │   │   ├── Destro.entitlements
│   │   │   └── LaunchScreen.storyboard
│   │   ├── DestroTests/
│   │   │   └── DestroTests.swift             # Unit tests (CriteriaEngine, Daemon, Conflict, Geofence, Earnings, DynamicRule)
│   │   └── Widgets/
│   │       ├── DestroWidget.swift            # WidgetKit (DestroWidgetExtension target in Xcode)
│   │       ├── Info.plist
│   │       └── DestroWidget.entitlements
│   └── deploy/
│       └── ipa.sh                            # Archive + export IPA (needs ExportOptions.plist)
│
├── dashboard/
│   ├── package.json
│   ├── server.js                             # WebSocket server :3000, stats (accepts/rejects/conflict/earnings)
│   ├── index.html
│   └── client/
│       └── src/
│           └── App.js                        # React + Recharts, WS client
│
├── shared/
│   ├── config.json                           # SCAN_CYCLE_MS, ADAPTIVE, BUSY_THRESHOLD
│   ├── criteria.js                           # JS criteria (reference)
│   ├── scraper.js                            # Regex hints for price/mi/shared/stops
│   ├── anti-detect.js                        # Jitter/delay notes
│   ├── metrics.proto                         # Protobuf (if used)
│   └── benchmark.js                          # Benchmark script
│
├── test/
│   ├── README.md
│   ├── e2e-test.js                           # Dashboard WebSocket E2E
│   └── chaos-suite.js                       # Chaos / stress
│
└── deploy/
    └── ipa.sh                               # Duplicate of ios/deploy/ipa.sh (if used from root)
```

---

## 4. Architecture (Conceptual)

```
┌─────────────────────────────────────────────────────────────────────────┐
│  UI Layer                                                                 │
│  DashboardViewController │ DestroWidget │ Live Activity │ App Intents     │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────────────┐
│  Core Daemon (ProdDaemon)                                                 │
│  Scan loop → OfferSource (AX or Vision) → CriteriaEngine → ActionExecutor│
│  ConflictManager → AppSwitcher (on accept)                                │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────────────┐
│  Data & Config                                                            │
│  FilterConfig (UserDefaults) │ HistoryStore │ GeofenceManager │ SyncManager│
│  ServiceReadinessStore │ Keychain (tokens)                                │
└──────────────────────────────────────────────────────────────────────────┘
```

**Data flow (simplified):**
1. User taps GO → daemon starts; `offerSource` (Accessibility → Vision fallback) polls each enabled app.
2. When an offer is found, `CriteriaEngine.evaluate(offer)` returns accept/reject (uses FilterConfig + GeofenceManager + time window).
3. On accept: if **requireConfirmBeforeAccept**, daemon stores pending offer and posts notification → UI shows "Accept $X? [Accept] [Decline]"; else **bringToForeground** → `actionExecutor.executeAccept` (HID tap) → `conflictManager.rideAccepted(app)` → other app sent to background.
4. Metrics/history written; DashboardRelay sends state/decisions/earnings to WebSocket; LogBuffer stores last 50 log lines (Menu → View logs).

---

## 5. Key Components (iOS)

| Component | Role | Notes |
|-----------|------|--------|
| **ProdDaemon** | Scan loop, state machine (idle/scanning/decisioning/cooldown/error) | 30ms cycle; 3 retries on nil offer; cooldown after accept/reject |
| **OfferData** | Immutable offer model | price, miles, shared, stops, acceptPoint, rejectPoint + optional pickup/dropoff, rating, surge, rideType, estimatedHourlyRate, pickupDistanceMiles |
| **OfferSource** | Protocol: `fetchOffer(appBundleId) -> OfferData?` | NilOfferSource, AccessibilityOfferSource, VisionOfferSource, FallbackOfferSource, AdaptiveFallbackOfferSource (3 nils → fallback-only 10 cycles) |
| **ActionExecutor** | Protocol: accept/reject tap at CGPoint | NoOpActionExecutor, HIDActionExecutor (IOKit) |
| **CriteriaEngine** | Pure function: offer → RideDecision | Uses FilterConfig, GeofenceManager, **DynamicRuleEngine.effectiveThresholds(idleMinutes)** for minPrice, minPricePerMile, maxPickupDistance; reasons: belowMinPrice, … |
| **FilterConfig** | UserDefaults-backed thresholds | minPrice, minPricePerMile, autoAccept, autoReject, **requireConfirmBeforeAccept**, minHourlyRate, maxPickupDistance, minPassengerRating, minSurgeMultiplier, blockedRideTypes, activeHoursStart/End, geofenceZones |
| **ConflictManager** | State: idle \| rideActive(app) \| transitioning | rideAccepted → send other app to background; rideCompleted → bring other back |
| **AppSwitcher** | bringToForeground / sendToBackground by bundleId | Used before accept/reject tap so tap lands on correct app. Private FBSSystemService-style APIs |
| **GeofenceManager** | Accept/avoid circles (FilterConfig.geofenceZones), CLLocationManager | shouldRejectByGeofence(pickupCoordinate) |
| **EarningsTracker** | Session + today earnings from HistoryStore; **daily goal** (persisted) | startSession/endSession on GO/STOP; dailyGoalProgress(); Menu → Set daily goal… |
| **LogBuffer** | In-memory ring of last 50 log lines | Metrics/daemon append; Menu → View logs |
| **SyncManager** | NSUbiquitousKeyValueStore sync; export/import JSON | Pull on external change |
| **DestroLiveActivity** | ActivityKit (iOS 16.1+) | start/end/update from dashboard GO/STOP |
| **DestroIntents** | GoOnline, GoOffline, GetEarnings, SetMinimumPrice + AppShortcutsProvider | Siri/Shortcuts |

---

## 6. Build & Run

**Prerequisites:** Xcode (iOS 17+ SDK), Node ≥20, pnpm 10.13.

**iOS (simulator or device):**
```bash
cd ios
open Mystro.xcodeproj
# Or: open ios/Mystro/Mystro.xcodeproj from repo root. Select scheme Destro, pick simulator or device.
# Signing: set team in Signing & Capabilities. Run (Cmd+R). Tests: Cmd+U.
# Run (Cmd+R). Tests: Cmd+U.
```

**IPA (TestFlight):** Use **Product → Archive** (destination: Any iOS Device), then **Window → Organizer** → select archive → **Distribute App** → **App Store Connect** → **Upload**. In App Store Connect, add the build to TestFlight and invite testers.  
*Optional (ad‑hoc/dev):* Run `./deploy/ipa.sh` from the **ios/** directory.

```bash
cd ios
# For TestFlight: Archive in Xcode, then Organizer → Distribute App → App Store Connect.
# For local IPA: set teamID in ExportOptions.plist, then:
./deploy/ipa.sh
# Output: Destro.ipa → install via Xcode Devices (ad‑hoc) or use TestFlight flow above.
```

**Dashboard:**
```bash
cd dashboard
npm i
npm start   # server :3000 + React dev server
```

**Tests (from repo root):**
```bash
pnpm i
# iOS: run tests in Xcode (Cmd+U).
node test/e2e-test.js          # Start dashboard server first
node test/chaos-suite.js [n]
node shared/benchmark.js
```

---

## 7. Configuration & Entitlements

- **shared/config.json:** SCAN_CYCLE_MS (30), ADAPTIVE, BUSY_THRESHOLD (not wired into iOS daemon; daemon uses hardcoded 30ms in ProdDaemon).
- **Info.plist:** NSSupportsLiveActivities, NSLocationWhenInUseUsageDescription, UIBackgroundModes (fetch, processing). The app now includes **NSAccessibilityUsageDescription** for offer reading, and in-app **PID entry** (Menu → Set driver app PID) with a **GO-time warning** when no PID is set.
- **Destro.entitlements:** App Sandbox on, network client/server on. Location entitlement set to **true** for geofencing; app group **group.com.destro.app** added. Main app writes status/earnings/conflict via AppGroupStore.
- **Widget:** DestroWidgetExtension target in Xcode; main app writes to app group. Widgets/DestroWidget.swift, app group group.com.destro.app. See ITERATION_ROADMAP_V1.1.md.
- **ExportOptions.plist:** Template at ios/ExportOptions.plist; set teamID. Used by ./deploy/ipa.sh for ad‑hoc export. For **TestFlight** use Xcode Archive → Organizer → Distribute App → App Store Connect.

---

## 8. Dependencies (Explicit)

**Root (package.json):** pnpm, typescript, vitest, @vitest/coverage-v8, ws, @types/node.  
**Dashboard:** react, react-dom, react-scripts, recharts, ws, jest.  
**iOS:** No CocoaPods or SPM; system frameworks only (UIKit, Foundation, CoreLocation, Vision, Security, ActivityKit, AppIntents). Private frameworks loaded at runtime via dlopen/dlsym.

---

## 9. Testing

| Scope | Location | How |
|-------|----------|-----|
| Unit (iOS) | DestroTests/DestroTests.swift | XCTest: CriteriaEngine (incl. new reasons), ProdDaemon.decide, DaemonState, ServiceReadinessStore, ConflictManager, GeofenceManager, EarningsTracker, DynamicRuleEngine |
| Unit (shared) | shared/criteria.spec.js | Vitest: `pnpm test` |
| Unit (dashboard) | dashboard/src/App.test.js | Jest/React Testing Library: `cd dashboard && npm test -- --watchAll=false` |
| E2E (dashboard) | test/e2e-test.js | WebSocket connect + events (start server first) |
| Chaos | test/chaos-suite.js | Optional runs with server |
| Benchmark | shared/benchmark.js | Criteria checks / mock events |

**Full test matrix and commands:** see [test/README.md](test/README.md).

---

## 10. Known Gaps & Iteration Opportunities

See **ITERATION_ROADMAP_V1.1.md** for risk/effort table and widget extension steps.

1. **Widget target:** Done. DestroWidgetExtension target added in Xcode; embed Widgets/DestroWidget.swift + app group. Set development team for Destro and DestroWidgetExtension. See ITERATION_ROADMAP_V1.1.md.
2. **Location entitlement:** Done in v1.1 (entitlement true).
3. **PID for AX:** discoverPID(for:) + store added; private API stub returns nil—use stored or manual PID. Effort for real enumeration: 2–4 h.
4. **Dashboard ↔ app:** Done. DashboardRelay sends decision/state/earnings to WebSocket; setBaseURL for device (e.g. Mac IP).
5. **App group:** Done. AppGroupStore writes session/status/conflict from Metrics and DashboardViewController.
6. **ExportOptions.plist:** Done. Template at ios/ExportOptions.plist; set teamID.
7. **CriteriaEngine + DynamicRuleEngine:** Done. CriteriaEngine uses effectiveThresholds(idleMinutes:) for minPrice, minPricePerMile, maxPickupDistance.
8. **Ride completion detection:** Done. After accept, 10s poller; 2 consecutive nil offers for active app → rideCompleted.
9. **CoreML model:** Heuristic only; no .mlmodel yet. Effort: 4–8 h.
10. **UIGetScreenImage / capture fallback:** May need Misaka26 or other path on newer iOS. Effort: 2–4 h.

---

## 11. Conventions & Patterns

- **Swift:** No third-party iOS deps; private APIs via dlopen/dlsym with optional fallbacks. Protocols for OfferSource and ActionExecutor for testability and swapping implementations.
- **State:** UserDefaults for persistence; Keychain for tokens (ServiceReadinessStore). NSUbiquitousKeyValueStore for iCloud sync (SyncManager).
- **Async:** Daemon uses Swift Task and async/await; scan loop is a single long-running Task cancelled on stopScanning.
- **Dashboard:** React 18, single App.js, Recharts for line chart; WebSocket for live stats. No state management library.
- **Monorepo:** pnpm workspaces; iOS is outside the workspace (no package.json under ios).

---

## 12. File Manifest (iOS app target)

| File | LOC (approx) | Purpose |
|------|-----------------|--------|
| AppDelegate.swift | ~40 | Window, daemon init, offerSource/actionExecutor, background task, Geofence permission |
| DashboardViewController.swift | ~1100 | Tabs, service cards, GO/STOP, earnings + daily goal, setup banner, relay indicator, filters/history/menu (Export history, Set daily goal, View logs), confirm-accept alert, Live Activity + Geofence |
| ProdDaemon.swift | ~320 | Scan loop, bringToForeground before tap, requireConfirmBeforeAccept/pendingConfirmOffer, rideCompletionPoller (15s delay), Metrics, LogBuffer, DashboardRelay, notifications |
| DaemonTypes.swift | ~176 | DaemonState, OfferData, RideType, DecisionReason, RideDecision, OfferSource, FallbackOfferSource, AdaptiveFallbackOfferSource, ActionExecutor |
| CriteriaEngine.swift | ~52 | evaluate() with all filter + geofence checks |
| FilterConfig.swift | ~220 | GeofenceZone, FilterConfig (all keys), HistoryEntry, HistoryStore |
| ServiceReadinessStore.swift | ~113 | ServiceBundleIds, get/set/markLinked, getToken/setToken (Keychain), discoverPID, storedPID, storePID |
| AppGroupStore.swift | ~28 | UserDefaults(suiteName: group.com.destro.app), writeStatus, writeSessionEarnings, writeConflictState |
| DashboardRelay.swift | ~140 | WebSocket, isConnected, destroDashboardRelayConnectionDidChange notification, setBaseURL, reconnect |
| AccessibilityOfferSource.swift | ~207 | AXLoader (dlopen AX*), AXOfferParser, traverse UI tree, parse price/miles/stops/buttons; uses ServiceReadinessStore.discoverPID |
| VisionOfferSource.swift | ~99 | UIGetScreenImage, VNRecognizeTextRequest, parseText |
| HIDActionExecutor.swift | ~132 | Jitter, HIDInjector (IOHIDEvent*), tap retry up to 3× with 100 ms delay |
| AppSwitcher.swift | ~73 | load FBSSystemService*, bringToForeground, sendToBackground |
| ConflictManager.swift | ~60 | state, rideAccepted, rideCompleted, reset |
| GeofenceManager.swift | ~95 | CLLocationManager, isInAcceptZone, isInAvoidZone, shouldRejectByGeofence |
| RidePredictor.swift | ~83 | predict(offer), estimatedMinutesToPickup; optional RidePredictorModel.mlmodelc |
| DynamicRuleEngine.swift | ~49 | effectiveMinPricePerMile, effectiveMinPrice, effectiveMaxPickupDistance, effectiveThresholds |
| EarningsTracker.swift | ~80 | sessionEarnings, todayEarnings, dailyGoal (persisted), startSession, endSession, dailyGoalProgress |
| SyncManager.swift | ~73 | syncToCloud, pullFromCloud, exportSettings, importSettings |
| DestroLiveActivity.swift | ~47 | Activity attributes, start/end/update (iOS 16.1+) |
| DestroIntents.swift | ~76 | GoOnline, GoOffline, GetEarnings, SetMinimumPrice, DestroShortcuts (MainActor daemon access) |
| LogBuffer.swift | ~26 | Singleton ring buffer (50 lines), append/lines; used by Metrics and daemon |
| ViewController.swift | ~9 | Placeholder (unused) |

**Build status:** Destro scheme builds with DestroWidgetExtension embedded; set development team for Destro and DestroWidgetExtension in Signing & Capabilities.

---

## 14. Next improvements

For the current backlog and iteration ideas, see **ITERATION_IMPROVEMENTS.md** (live backlog v1.2). Summary:

- **PID discovery:** `tryPrivatePIDDiscovery` is a stub; manual PID entry is available (Menu → Set driver app PID; Set PID on each service card). Document or implement discovery when on Misaka26/jailbreak.
- **Geofence zones UI:** Done. FilterConfig/CriteriaEngine support geofence accept/avoid zones; Filters screen has list, Add zone (Name, Lat, Lon, Radius → Accept/Avoid), and Delete per row.
- **Tests:** Additional coverage for History filter logic, notification handlers.
- **Vision/screen-capture fallback:** Implemented. `VisionOfferSource` uses `UIGetScreenImage` (private API) and `VNRecognizeTextRequest` for offer parsing when AX is unavailable (jailbreak/Misaka26 or overlay).
- **CoreML ride predictor:** Optional. Add `RidePredictorModel.mlmodelc` (or `.mlmodel`) to the Destro app target. Inputs: price, miles, surge, timeOfDay, pickupZoneHash. Outputs: qualityScore (0–1), predictedEarnings. `RidePredictor` uses the model when present; heuristic fallback otherwise. See `RidePredictor.swift`.
- **Doc sync:** ITERATION_IMPROVEMENTS.md is the live backlog (v1.2).

---

## 13. Document History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | Mar 2026 | Initial full engineer's report and tech stack for iteration handoff |
| 1.1 | Mar 2026 | Iteration roadmap: ExportOptions, location/app group, PID, AppGroupStore, DashboardRelay, DynamicRuleEngine in CriteriaEngine, ride completion, AdaptiveFallbackOfferSource, tap retry. See ITERATION_ROADMAP_V1.1.md. |
| 1.2 | Mar 2026 | Confirm-before-accept (requireConfirmBeforeAccept, pendingConfirmOffer, performPendingAccept); Export history (CSV share); Set daily goal (persisted); LogBuffer + View logs; setup banner (PID); Dashboard relay indicator; Filters UI expanded; CriteriaEngine stops > 1; orientation support; doc sync. |

---

*End of report.*
