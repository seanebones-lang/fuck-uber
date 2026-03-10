# Destro (fuck-uber) — Production Reliability Report

**Date:** March 5, 2025  
**Purpose:** Pre–go-live analysis for use tomorrow.

---

## 1. Test Coverage: Critical Paths

| Critical path | Has tests? | Where | Notes |
|---------------|------------|--------|-------|
| **Accept/Reject** | **Partial** | `ios/Mystro/MystroTests/MystroTests.swift` (CriteriaEngineTests, ProdDaemonDecisionTests) | CriteriaEngine `evaluate()` and daemon `decide()` are tested. **No tests** for: confirm-before-accept UI, `performPendingAccept()` / `clearPendingConfirm()`, full accept/reject execution (tap, ConflictManager, HistoryStore write, Metrics, DashboardRelay). |
| **Daemon** | **Partial** | Same file (DaemonStateTests) | Tests: starts idle, stop clears state. **No tests** for: `startScanning()` loop, background task on app background, error → idle transition, disconnect DashboardRelay on stop. |
| **CriteriaEngine** | **Yes** | MystroTests.swift (CriteriaEngineTests) | Accept (meetsCriteria, zeroStops) and reject reasons (belowMinPrice, belowMinPricePerMile, sharedRide, tooManyStops, belowMinHourlyRate, pickupTooFar, blockedRideType, lowPassengerRating, belowSurgeThreshold). **Not covered:** active-hours rejection, geofence rejection (only empty zones tested). |
| **HistoryStore** | **Yes** | MystroTests.swift (HistoryStoreTests) | Append, load, max 200 entries. |
| **FilterConfig** | **Partial** | FilterConfigTests + CriteriaEngineTests | Round-trip for `minPassengerRating`, `minSurgeMultiplier`. Other keys only used indirectly via CriteriaEngine; no full load/save suite. |
| **PID** | **No** | — | No tests for ServiceReadinessStore `discoverPID`/`storePID`/`storedPID`, ProdDaemon `findPID(bundle:)`, or dashboard PID alert UI. |
| **WebSocket / Dashboard** | **Server/E2E only** | `test/e2e-test.js`, `test/chaos-suite.js` | E2E: connect, send scan/offer_seen/decision/action_result, assert `connected` + stats. Chaos: many connections (default 500), random decisions, assert ≥95% uptime. **No** unit tests for iOS `DashboardRelay` (connect, send, reconnect, connection state). **No** tests for dashboard client reconnection, error UI, or empty data. |

**Shared JS criteria:** `shared/criteria.spec.js` (Vitest) tests `FIXED_CRITERIA` only; this is not the iOS CriteriaEngine (which uses FilterConfig + DynamicRuleEngine).

**Dashboard React:** `dashboard/client/src/App.test.js` and `dashboard/src/App.test.js` only assert heading "Destro Dashboard"; no WebSocket or flow tests.

---

## 2. Flaky or Order-Dependent Tests

- **Shared global state (FilterConfig / UserDefaults)**  
  CriteriaEngineTests mutate `FilterConfig` (e.g. `blockedRideTypes`, `minPassengerRating`, `minSurgeMultiplier`, `geofenceZones`) and restore with `defer`. If a test fails before `defer` runs, or test order changes, other tests can see wrong values. GeofenceManagerTests set `FilterConfig.geofenceZones = []` with no restore in some cases.

- **HistoryStore**  
  Tests append real entries to UserDefaults; no `setUp`/`tearDown` cleanup. `testLoadRespectsMaxEntries` writes 210 entries and does not remove them. Count assertions depend on prior test state.

- **EarningsTracker / AppGroupStore**  
  Use shared singletons; EarningsTrackerTests call `endSession()` with no full reset. AppGroupStoreTests write to real app group defaults and do not clean up.

- **No test isolation in Swift**  
  No `setUp()`/`tearDown()` in MystroTests; each test relies on clean process or manual restore. Order of execution can matter if any test leaves global state changed.

- **Date/time**  
  CriteriaEngine uses `Date()` and `Calendar.current` for active hours. No time mocking; behavior could change at midnight or in restricted hours (most tests use 0–23 so accept path is used).

- **E2E / chaos timing**  
  e2e-test.js: 5s connect timeout, 50ms between sends, 300ms before assert. chaos-suite: 2s connect per run. Slow CI or load could cause intermittent failures.

---

## 3. Simulator vs Device: What May Behave Differently

- **Accessibility (AX) / PID**  
  `AccessibilityOfferSource` uses `AXUIElementCreateApplication(pid)` to read the driver app UI. Requires correct **PID** and **Accessibility** permission. Enumerating other apps' PIDs is restricted on stock iOS; behavior is environment- and device-dependent.

- **Location / CoreLocation**  
  GeofenceManager, RidePredictor, FilterConfig (GeofenceZone) use CLLocation/CLLocationManager. Permissions and accuracy differ on device; simulator can simulate location.

- **Screen capture / Vision**  
  VisionOfferSource uses `UIGetScreenImage` (private, dlsym) and VNRecognizeTextRequest. Private API not available on stock device; behavior may differ on simulator vs jailbreak/Misaka26.

- **Background execution**  
  AppDelegate uses `beginBackgroundTask` / `endBackgroundTask` when daemon is scanning. Background time limits and suspension behavior differ on device vs simulator.

- **HID / tap injection**  
  HIDActionExecutor used in accept path; may be restricted or behave differently on device.

- **Keychain**  
  ServiceReadinessStore uses Keychain; behavior can differ slightly between simulator and device.

---

## 4. Dashboard: WebSocket Reconnection, Error States, Empty Data

### Reconnection

- **iOS (DashboardRelay)**  
  On receive failure or send error: sets `_isConnected = false`, clears task, calls `scheduleReconnect()` → `_connect()` after **5 seconds**. No backoff or max retries; no ping/keepalive.

- **Dashboard client (browser)**  
  Single `new WebSocket(WS_URL)` in `useEffect`; cleanup `ws.close()` on unmount. **No reconnection** on close or error; user must refresh.

### Error states

- **DashboardRelay (iOS)**  
  State via `isConnected` and `destroDashboardRelayConnectionDidChange`. Send failures trigger disconnect + scheduleReconnect. No explicit error message surface.

- **Dashboard client**  
  - **client/src/App.js:** `wsError` set on `onerror` / `onclose`, rendered as `<p role="alert">` with message (e.g. "Dashboard disconnected. Is the server running at …?").  
  - **dashboard/src/App.js:** **No** `wsError` state or alert; disconnect/error is invisible.

### Empty data

- **Server**  
  New clients get `{ type: 'connected', stats }`; `stats` is always the in-memory object.

- **Client**  
  - **client/src/App.js:** If `statsHistory.length === 0`, shows "No data yet. Connect the app and go online to see the chart."  
  - **dashboard/src/App.js:** No empty check; always renders `<LineChart data={statsHistory}>` (Recharts with empty array).

**Recommendation:** Confirm which dashboard entry is used in production (`client` vs `src`). Prefer `client` for error and empty-state handling; add client-side reconnection (e.g. retry with backoff on close/error).

---

## 5. Manual Test Checklist Before Going Live

Use this tomorrow before declaring "live":

### App & daemon

- [ ] **Start/stop:** Start scanning → state shows scanning; stop → state idle, no lingering tasks.
- [ ] **Background:** With scanning on, send app to background; confirm background task runs and daemon stops cleanly when time expires (no crash).
- [ ] **PID:** Set Uber/Lyft PIDs via dashboard/settings; confirm app uses them for offer source (if applicable).
- [ ] **FilterConfig:** Change min price, min per mile, blocked ride types, passenger rating, surge; confirm next offer is accepted/rejected per rules.
- [ ] **Accept path (happy):** Offer that meets criteria → accept (and confirm if "confirm before accept" is on) → tap executed, conflict state updated, history entry, dashboard shows accept.
- [ ] **Reject path:** Offer that fails criteria → reject → no tap, dashboard shows reject with reason.
- [ ] **Confirm-before-accept:** With option on, accept → alert "Accept ride?" → Accept → performPendingAccept; Decline → clearPendingConfirm, no tap.
- [ ] **Geofence:** If using zones, offer inside/outside zone → correct accept/reject.
- [ ] **History:** Accept/reject several offers; open history screen → correct entries, max 200; filter (all/accept/reject) works.

### Dashboard

- [ ] **Server up, app connected:** Dashboard shows live stats and chart updates.
- [ ] **Server down at load:** Start dashboard client with server down → error message (if using client build); no infinite spin.
- [ ] **Server dies after connect:** Kill server while dashboard open → error message; after restarting server, **manual refresh** restores (no auto-reconnect today).
- [ ] **Empty state:** Fresh server, no events yet → "No data yet" or equivalent (client build); chart doesn't break (src build at least doesn't crash).
- [ ] **E2E sanity:** Run `node test/e2e-test.js` with server running → passes.
- [ ] **Chaos (optional):** Run `node test/chaos-suite.js` → ≥95% uptime.

### Device vs simulator (if possible)

- [ ] **Device:** Install on real device; test one accept and one reject (if offer source works).
- [ ] **Location:** If using geofences, test with real location (or simulated location on device).
- [ ] **Accessibility:** Confirm Accessibility permission and PID discovery/setting on device.

---

## 6. Structured Summary

### Test Gaps

| Gap | Severity | Recommendation |
|-----|----------|----------------|
| No PID tests | High | Add tests for store/discover and (if feasible) UI path. |
| No DashboardRelay unit tests | Medium | Test connect, send, reconnect (5s), connection state. |
| No client reconnection | Medium | Implement retry with backoff; add tests. |
| Confirm-before-accept and full accept/reject execution untested | Medium | Add integration or UI tests for confirm flow and executeAccept/executeReject. |
| Daemon scan loop and background behavior untested | Medium | Add tests or documented manual steps. |
| dashboard/src has no error/empty UI | Medium | Use client build or add error/empty handling to src. |
| FilterConfig full load/save and active-hours/geofence branches | Low | Expand CriteriaEngine/FilterConfig tests; consider time/geofence mocks. |
| Shared state and no setUp/tearDown | Low | Add test isolation and cleanup to reduce flakiness. |

### Reliability Risks

1. **Production vs simulator:** PID discovery, Accessibility, private APIs (UIGetScreenImage), background limits, and HID may behave differently on device.
2. **Dashboard:** Browser client does not reconnect; one disconnect requires refresh. Server e2e/chaos pass but client resilience is untested.
3. **Flakiness:** Shared FilterConfig/UserDefaults and lack of test isolation can cause order-dependent or environment-dependent failures.
4. **Missing coverage:** PID, full accept/reject path, and DashboardRelay are critical for production but not covered by tests.

### Manual Test Checklist (condensed)

- Daemon: start/stop, background, PID, FilterConfig changes.
- Accept/reject: happy accept, reject, confirm-before-accept, geofence (if used), history and filters.
- Dashboard: server up/down, disconnect/recovery (refresh), empty state, e2e (and optionally chaos).
- Device: install, one accept/reject, location, Accessibility/PID if applicable.

---

## 7. Production Readiness Score: **5.5 / 10**

**Justification:**

- **Strengths:** Core decision logic (CriteriaEngine) and persistence (HistoryStore) are tested. Server WebSocket and stress (e2e, chaos) give confidence in the dashboard backend. Key accept/reject branches are covered in unit tests.
- **Deductions:**  
  - **−1.5:** No tests for PID (critical for offer source on device).  
  - **−1:** Full accept/reject execution (tap, conflict, history, relay) and confirm UI untested.  
  - **−1:** Daemon lifecycle (scan loop, background, error handling) only partially tested.  
  - **−0.5:** Dashboard client has no reconnection; one build (src) has no error/empty UI.  
  - **−0.5:** Simulator vs device differences (AX, private API, background, HID) unverified; flakiness risk from shared state.

**Verdict:** Suitable for a **controlled "live"** tomorrow if you run the manual checklist and accept that PID, full execution path, and device behavior are validated manually. For a **hard production** launch, raise coverage for PID and DashboardRelay, add client reconnection and consistent error/empty handling, and improve test isolation to reduce flakiness.
