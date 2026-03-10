# Master Inspector Report — Destro iOS App & Dashboard

**Scope:** iOS app (ProdDaemon, DaemonHolder, ServiceReadinessStore, CriteriaEngine, FilterConfig, AccessibilityOfferSource/ActionExecutor, DashboardViewController, AppDelegate, MystroIntents, MystroLiveActivity, AppGroupStore, DashboardRelay, DaemonTypes), Widget (MystroWidget), Dashboard (server.js, client App.js).

**Applied fixes (post-report):** Intents now start/end Live Activity, set wasScanning, start/stop GeofenceManager, and post destroDaemonDidStartScanning for UI sync. daemonDidBecomeIdle ends Live Activity. findPID removed; duplicate state = .scanning removed. Server: guard for invalid data, explicit accept/reject counting, getStats(). Client: earnings/conflict_state handling, null check, console.warn in catch. startDestroLiveActivity uses "🟢 SCANNING". Widget reload on writeStatus/writeSessionEarnings.

---

## 1. Executive summary

- **Correctness:** A few issues: App Intents (Go Online/Offline) do not start/end Live Activity or update UI state; dashboard WebSocket has no reconnection; server stats.uptime is static.
- **Conciseness:** Minor redundancy in ProdDaemon (duplicate state assignment), widget view (duplicate layout for default family), and dashboard VC (repeated offer-string building).
- **Functionality:** Dead code in ProdDaemon (`findPID`); widget does not refresh when app group is written; intents leave Live Activity and dashboard relay out of sync with “online” state.
- **Overall:** Core daemon, criteria, accessibility, and dashboard relay logic are sound. Priority fixes: intents + Live Activity, optional widget timeline reload, and dashboard reconnection/uptime.

---

## 2. Correctness issues

| Location | Issue | Suggested fix |
|----------|--------|----------------|
| **MystroIntents.swift** (GoOnlineIntent, GoOfflineIntent) | Going online/offline via Siri/Shortcuts does not start/end Live Activity, does not set DashboardViewController’s `isOnline`, and does not start/stop GeofenceManager or conflict callback. | In GoOnlineIntent: after `startScanning()`, call `startDestroLiveActivity()` (if iOS 16.1+), `GeofenceManager.shared.startUpdatingLocation()`, and persist “wasScanning”/“isOnline” for UI. In GoOfflineIntent: call `endDestroLiveActivity()`, `GeofenceManager.shared.stopUpdatingLocation()`, and clear “wasScanning”. |
| **dashboard/client/src/App.js** | WebSocket is created once in `useEffect` with empty deps; on close there is no reconnection. | Add reconnect logic (e.g. exponential backoff or fixed interval) and re-run connection setup on close/error, or use a stable ref + cleanup so one reconnecting loop runs. |
| **dashboard/server.js** | `stats.uptime` is never updated (hardcoded 99.95). | Either remove uptime from UI or compute from server start (e.g. `(Date.now() - serverStart) / 3600000` or similar) and include in `stats` sent on `connected`. |
| **ProdDaemon.swift** (performPendingAccept) | Uses `offerSource` and `actionExecutor` at perform time; if they were swapped after storing the pending offer, the wrong source/executor could be used. | Document that pending confirm is short-lived and must not change offerSource/actionExecutor, or capture the executor/source at confirm-request time and use that for perform. |
| **CriteriaEngine.swift** (active hours) | Overnight window (start > end) logic is correct: reject when `hour < start && hour > end`. No bug. | — |

---

## 3. Conciseness improvements (optional)

| Location | Issue | Suggested fix |
|----------|--------|----------------|
| **ProdDaemon.swift** ~239–241 | `self.state = .scanning` is set twice in the scan loop (after cooldown and again after bringDestroToForeground). | Keep a single assignment to `.scanning` before the cycle sleep. |
| **MystroWidget.swift** (DestroWidgetView) | `default` case uses `content`, which duplicates the same VStack as accessoryRectangular (status, lastApp, session earnings). | Use one shared body layout for `.systemSmall`/`.systemMedium`/`.systemLarge` and `.accessoryRectangular`, or a single helper view. |
| **DashboardViewController.swift** | `offerSeen` and `confirmAcceptRequested` build very similar offer message strings (app, price, miles, $/mi, pickup, surge, rideType, reason). | Extract a helper e.g. `formatOfferBreakdown(info: [String: Any]) -> String` and use it in both. |

---

## 4. Functionality gaps / dead code

| Location | Issue | Suggested fix |
|----------|--------|----------------|
| **ProdDaemon.swift** ~318–322 | `findPID(bundle:)` is private and never called; PID is obtained via `ServiceReadinessStore.discoverPID`/storedPID. | Remove `findPID(bundle:)` (dead code). |
| **MystroIntents.swift** | GoOnlineIntent / GoOfflineIntent do not start/end Live Activity. | See Correctness: call `startDestroLiveActivity()` / `endDestroLiveActivity()` from intents when going online/offline. |
| **Widget** | Widget reads App Group in `currentEntry()`; timeline policy is `.after(30)`. Main app does not call `WidgetCenter.shared.reloadAllTimelines()` when writing status/earnings. | Optionally call `WidgetCenter.shared.reloadAllTimelines()` after `AppGroupStore.writeStatus` / `writeSessionEarnings` so widget updates sooner than 30s. |
| **dashboard/server.js** | `lastEventAt` is updated in handleEvent but not sent to clients in `stats`. | Include `lastEventAt` in the `stats` object sent on `connected` if the client should show “last activity” time. |
| **DashboardViewController** (updateDaemonEnabledApps) | When online and user toggles an app off so `ids` becomes empty, `daemon.startScanning()` is not called (guard only calls start when `!ids.isEmpty`). Setting `enabledBundleIds = []` triggers `stopScanning()` in didSet. | No change needed; behavior is correct: empty list stops scanning. |

---

## 5. Recommended fixes (prioritized, up to 10)

| # | File(s) | Change type | Description |
|---|---------|-------------|-------------|
| 1 | **MystroIntents.swift** | Correctness | In GoOnlineIntent: after `startScanning()` and `startSession()`, call `startDestroLiveActivity()` (if iOS 16.1+), `GeofenceManager.shared.startUpdatingLocation()`, and set UserDefaults “wasScanning”/“hasGoneOnlineOnce” as in performGoOnline. In GoOfflineIntent: call `endDestroLiveActivity()`, `GeofenceManager.shared.stopUpdatingLocation()`, and clear “wasScanning” before/after `stopScanning()` and `endSession()`. |
| 2 | **dashboard/client/src/App.js** | Correctness | Add WebSocket reconnection on close/error (e.g. setTimeout to open a new WebSocket and re-attach handlers) so the dashboard recovers without a full page reload. |
| 3 | **ProdDaemon.swift** | Dead code | Remove private `findPID(bundle:)` (lines ~318–322); callers use ServiceReadinessStore only. |
| 4 | **ios/Mystro (main app)** | Functionality | After `AppGroupStore.writeStatus` / `writeSessionEarnings` (e.g. in Metrics.pubScan, pubAccept, or ProdDaemon idle path), optionally call `WidgetCenter.shared.reloadAllTimelines()` so the widget refreshes without waiting for the 30s timeline. |
| 5 | **ProdDaemon.swift** | Conciseness | Remove the duplicate `self.state = .scanning` (keep one before the cycle sleep). |
| 6 | **dashboard/server.js** | Correctness | Either stop exposing a static `stats.uptime` (99.95) or compute real uptime from server start and include it in `stats` sent on `connected`. |
| 7 | **MystroWidget.swift** | Conciseness | Unify the default (system sizes) and accessoryRectangular layout into one shared view or helper to avoid duplicated status/lastApp/sessionEarnings VStack. |
| 8 | **DashboardViewController.swift** | Conciseness | Extract shared offer-breakdown string formatting from `offerSeen` and `confirmAcceptRequested` into a single helper. |
| 9 | **DashboardRelay / DashboardViewController** | Optional | When going online via Intent, UI does not show “You’re online” until the user opens the app; consider posting a notification that the dashboard VC can observe to set `isOnline` and update status (or document that intents are best-effort and UI sync happens on next open). |
| 10 | **dashboard/server.js** | Functionality | Include `lastEventAt` in the `stats` object sent to clients on `connected` if the client should display last activity time. |

---

*Report generated by Master Inspector. No builds or tests were run; findings are from static reading and pattern search.*
