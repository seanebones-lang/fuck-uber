# Destro – Iteration & Improvements Backlog

**Backlog v1.2** · **Purpose:** Concrete next steps to iterate and improve the app.  
**Last updated:** March 2026

---

## Recently completed (this pass)

- **History filter:** All / Accept / Reject segmented control in `HistoryViewController` so drivers can filter decisions.
- **Filters UI:** Min passenger rating (0–5) and min surge multiplier fields in `FiltersViewController`; values read from/written to `FilterConfig` and used by `CriteriaEngine`.
- **Rush hour note:** Info text in Filters screen: "Rush hour (7–9a, 4–7p): min $/mile is 10% higher."
- **Docs:** `MASTER_INSPECTOR_REPORT.md` — all `mystro.pid` references updated to `destro.pid`.
- **Reject tap failure feedback:** When `executeReject` returns false, daemon posts `.destroRejectTapFailed`; dashboard shows "Reject tap failed" alert (mirrors accept tap failure).
- **Blocked ride types in Filters UI:** Section "Blocked ride types (auto-reject when offer matches)" with a switch per `RideType` (UberX, Uber XL, Uber Black, Lyft Standard, Lyft XL, Lyft Lux, Other); persisted via `FilterConfig.blockedRideTypes`. `RideType.displayName` added for labels.
- **Rush hour indicator on dashboard:** When `DynamicRuleEngine.isCurrentlyRushHour` is true, a label shows "Rush hour: min $/mile +10%" below the relay line; hidden when not rush hour. Refreshes on viewWillAppear and updateStatusText.
- **Haptic on accept/reject:** Light impact feedback when auto-accept tap succeeds, when auto-reject tap succeeds, and when user confirms accept in the confirm-before-accept flow.
- **Unit tests:** FilterConfig round-trip for minPassengerRating and minSurgeMultiplier; CriteriaEngine tests for lowPassengerRating and belowSurgeThreshold; DynamicRuleEngine tests for isCurrentlyRushHour and rushHourDescription.
- **Set PID on service card:** Each Uber/Lyft card has a "Set PID" button that opens a single-app PID alert (bundleId + serviceName); dashboard shows one text field and saves to that app only. Manual PID entry is now available from the card as well as Menu → Set driver app PID.
- **Doc sync:** ENGINEERING_REPORT §14 "Next improvements" added; points to ITERATION_IMPROVEMENTS.md. Backlog note added that items 1–3 (reject tap failure, blocked ride types, rush hour indicator) are done.
- **History filter test:** Unit test `HistoryFilterTests.testFilterByDecisionCounts` verifies that filtering entries by decision "accept" / "reject" yields expected counts (mirrors HistoryViewController filteredEntries logic).
- **PID on service card:** When a driver app PID is set, the card status line shows " · PID: 1234" so drivers can confirm at a glance without opening Set PID.
- **History empty state:** When there are no entries (or no entries for the selected filter), the History table shows one row: "No decisions yet…" / "No accepted rides for this filter." / "No rejected rides for this filter." instead of a blank list.
- **PID discovery docs:** ServiceReadinessStore documents manual PID entry (Menu → Set driver app PID; Set PID on each service card); `tryPrivatePIDDiscovery` stub comment updated.
- **HistoryStore test:** Unit test `HistoryStoreTests.testAppendAndLoadReturnsEntries` verifies append + load returns the new entry with correct app, price, decision.
- **README + ITERATION_ROADMAP:** README notes scheme **Destro** and project under `ios/Mystro`. ITERATION_ROADMAP_V1.1 updated: Destro app group/bundle IDs, `destro.dashboard.wsURL`, project path `ios/Mystro/Mystro.xcodeproj`, widget path and bundle ID.
- **Dashboard React:** Empty state when `statsHistory.length === 0` ("No data yet. Connect the app and go online…"); WebSocket error/close set `wsError` and show user-visible message; `aria-label` on h1 and stats; chart wrapped in `aria-label="Accepts and rejects over time"` with empty-state message.
- **iOS accessibility:** `accessibilityLabel` on GO/STOP button ("Go online" / "Stop scanning"), status label ("Online" / "Offline" + version), Drive tab ("Drive"), History tab ("History") for VoiceOver.
- **Backlog doc:** "Next improvements" section replaced with single Done list + Remaining (1–6); no duplicate items.
- **ENGINEERING_REPORT §14:** Bullet added for geofence zones UI (FilterConfig/CriteriaEngine support; no Filters UI yet).
- **Filters screen:** Geofence note added: "Geofence zones: config/sync only; in-app zone editing coming later."
- **Tests:** All 35 Destro unit tests passed (shell agent run on iPhone 17 simulator).
- **README:** Geofence sentence added in Using Destro: "Geofence accept/avoid zones are supported in config; in-app zone editing is planned." (dashboard package was already destro-dashboard.)
- **HistoryStore maxEntries test:** `testLoadRespectsMaxEntries` added – appends 210 entries, asserts load().count <= 200.
- **Geofence zones UI:** Filters screen: list of zones (name, lat, lon, radius, Accept/Avoid), Add zone (alert: Name, Lat, Lon, Radius → Add as Accept / Add as Avoid), Delete per row; `refreshGeofenceZoneRows()`, `addGeofenceZoneTapped()`, `deleteGeofenceZoneTapped(_:)`; persisted via `FilterConfig.geofenceZones`.
- **Production hardening (MCP swarm):** All CRITICAL/HIGH/MEDIUM items addressed: performPendingAccept async (no Thread.sleep); dashboard server process handlers + handleEvent/ws message logging; client wsState/wsError + onmessage log; SecItemAdd result check; HistoryStore/FilterConfig save failure logging; DashboardRelay safe init + send JSON log; AX type-ID + unsafeBitCast; GeofenceManager location error/denied logging; env PORT and REACT_APP_WS_URL; try? logging in RidePredictor, VisionOfferSource, SyncManager, DashboardRelay; ENGINEERING_REPORT programmatic-UI note.
- **Mystro-style UX:** Connect via Accessibility only (frontmost-app PID); no PID gate before GO; setup banner "Enable Destro in Settings → Accessibility" + Open Settings; banner hides after first GO; default requireConfirmBeforeAccept = true for new installs; Dashboard URL placeholder; PID alert copy updated; TestFlight deploy path in README/ENGINEERING_REPORT/MCP_SWARM.
- **Tests:** 35 Destro unit tests; build and test pass.

---

## Next improvements (prioritized)

Done (see Recently completed): Reject tap failure, blocked ride types, rush hour indicator, haptic, Set PID on card, PID on card, History empty state, PID docs, HistoryStore test, README/roadmap, Dashboard React UX, iOS accessibility.

Remaining:
1. PID discovery – Stub; manual entry documented. Implement only for Misaka26/jailbreak.
2. Tests – Optional: daemon error path, notification handlers.
3. ~~Geofence zones UI~~ – Done (Filters: list, add, delete zones).
4. CoreML – Optional RidePredictorModel.mlmodelc (longer term); see README / ENGINEERING_REPORT for how to add.
5. Screen capture fallback – Implemented: VisionOfferSource uses UIGetScreenImage + VNRecognizeTextRequest when AX unavailable (jailbreak/Misaka26 or overlay).
6. Doc versioning – Backlog v1.2 in ITERATION_IMPROVEMENTS.md; ENGINEERING_REPORT §14 references live backlog.

---

## Build & test

- **Scheme:** Destro  
- **Project:** `ios/Mystro/Mystro.xcodeproj` (folder still `ios/Mystro`; app name is Destro)  
- **Build:** `cd ios && xcodebuild -scheme Destro -destination 'generic/platform=iOS' build`  
- **Tests:** `@testable import Destro` (module = app target name Destro)

---

*End of backlog.*
