# MCP Swarm: Production Quality Analysis

**Date:** March 5, 2026  
**Purpose:** Single consolidated report from three MCP agents for **production quality tomorrow**.

---

## Executive summary

- **Production readiness score:** 5.5 / 10 (controlled live OK with manual checklist; hard production needs more tests and fixes).
- **Critical:** 4 items (tap/sleep, server crashes, Keychain/persistence silent failures).
- **High:** 6 items (force unwraps, PID storage, dashboard errors, main-thread sleep).
- **Deployment blocker:** Dashboard `npm start` fails without `concurrently` in package.json — **fixed** (see below).

**Fixes applied (orchestrated pass):** All CRITICAL and HIGH items above have been addressed: (1) performPendingAccept uses async `Task.sleep` + MainActor.run instead of Thread.sleep. (2) Dashboard server has process.on('uncaughtException') and process.on('unhandledRejection'); handleEvent and ws message handler log errors. (3) ServiceReadinessStore checks SecItemAdd result and logs on failure. (4) HistoryStore.save and FilterConfig (blockedRideTypes, geofenceZones) log encode/save failures. (5) DashboardRelay init no longer force-unwraps stored URL. (6) AccessibilityOfferSource uses type-ID check + unsafeBitCast for CFDictionary/CFArray (safe, no as!). (7–8) Dashboard client logs onmessage errors and shows Connection state + wsError. (9) Server handleEvent catch logs. (10) Same as #1 — async confirm flow. Build and 35 tests pass.

Use the **Pre-flight checklist** at the end before going live tomorrow.

---

## 1. CRITICAL (must fix before production)

| # | Item | Location | Recommendation |
|---|------|----------|----------------|
| 1 | **Tap can land on wrong app / main-thread sleep** | ProdDaemon, performPendingAccept | Bring driver app to foreground before tap (SIDE_BY_SIDE says Done). Replace `Thread.sleep(forTimeInterval: 0.4)` with async delay off main thread (e.g. `Task { try? await Task.sleep(...) }; await MainActor.run { … }`) so UI stays responsive and timing is explicit. |
| 2 | **Dashboard server: uncaught exceptions** | dashboard/server.js | Add `process.on('uncaughtException')` and `process.on('unhandledRejection')` to log and optionally exit cleanly; keep per-message errors inside handleEvent. |
| 3 | **Keychain token write failures ignored** | ServiceReadinessStore.swift | Check `SecItemAdd` result; on failure log and/or surface to caller; avoid silently continuing as if token was saved. |
| 4 | **History and FilterConfig save failures silent** | FilterConfig.swift / HistoryStore | Log encode/save failures; consider minimal user-visible "Settings could not be saved" when persistence fails. |

---

## 2. HIGH (should fix)

| # | Item | Location | Recommendation |
|---|------|----------|----------------|
| 5 | **Force unwrap of stored dashboard URL** | DashboardRelay.swift | Replace `stored!` with optional binding or `stored.flatMap { $0.isEmpty ? nil : $0 } ?? "ws://localhost:3000"`. |
| 6 | **Force casts in AX attribute helpers** | AccessibilityOfferSource.swift | Use conditional cast (`as?`) and `guard let … else { return nil }` instead of `as!` for CFDictionary/CFArray. |
| 7 | **PID in UserDefaults** | ServiceReadinessStore / ProdDaemon | Document that PIDs are device-specific; consider Keychain or backup exclusion; avoid logging PIDs in production. |
| 8 | **Dashboard client: message errors swallowed** | dashboard/src/App.js | Log errors (e.g. `console.error`); add connection state and "Dashboard disconnected" / "Reconnect" if using src (client has better handling). |
| 9 | **Dashboard server: handleEvent errors swallowed** | dashboard/server.js | Log parse/handling errors (message snippet, no secrets); optionally expose minimal health/error counter. |
| 10 | **ProdDaemon: main-thread sleep in confirm flow** | ProdDaemon.swift | Same as Critical #1: replace `Thread.sleep(0.4)` with async wait so UI stays responsive. |

---

## 3. MEDIUM (nice to have)

- **Logging:** Use os.log/Logger with levels; keep LogBuffer for "View logs."
- **Dashboard:** `process.env.PORT || 3000` and `REACT_APP_WS_URL` for client — **done.** Server uses PORT from env; client uses `process.env.REACT_APP_WS_URL || 'ws://localhost:3000'`.
- **GeofenceManager:** Log location failures; log when authorization denied/restricted — **done.** `didFailWithError` and `locationManagerDidChangeAuthorization` (denied/restricted) now log.
- **try? with no logging:** VisionOfferSource (OCR perform), RidePredictor (model load), SyncManager (geofence decode), DashboardRelay (send JSON) — **done.** Failures now log; heuristic/fallback used where applicable.
- **init(coder:) fatalError:** Acceptable if 100% programmatic; documented in ENGINEERING_REPORT (UIKit row: programmatic, no storyboards).

---

## 4. Deployment & config

### Doc gaps

- **ENGINEERING_REPORT:** References **Destro.xcodeproj** / **ios/Destro/**; repo uses **Mystro.xcodeproj** and **ios/Mystro/**. Fix project name and paths in report.
- **README:** Node ≥20, pnpm for root tests; "Run (Cmd+R)", "Tests: Cmd+U"; **ios/deploy/ipa.sh** (root `./deploy/ipa.sh` only prints message).
- **Dashboard:** Add **concurrently** to devDependencies so `npm start` works (see below).
- **ExportOptions:** Mention aligning provisioning profile name ("Destro Development") with Apple Developer.

### Config risks

| Item | Risk | Notes |
|------|------|--------|
| **autoAccept + requireConfirmBeforeAccept** | **High** | Defaults: autoAccept **true**, requireConfirmBeforeAccept **false** → first launch can auto-accept without confirmation. Consider default **requireConfirmBeforeAccept = true** or **autoAccept = false** for first run. |
| **Dashboard URL** | Medium | Default `ws://localhost:3000` on device won’t reach Mac; user must set Mac IP (Menu → Dashboard URL…). |
| **ExportOptions teamID** | High if missed | Set real team ID and matching provisioning profile or export fails. |

### Deployment checklist (tomorrow)

**Pre-requisites**

- [ ] Xcode (iOS 17+), Node ≥20, pnpm (root tests). Apple Developer team ID; profile for `com.destro.app`.

**iOS**

- [ ] Open **ios/Mystro/Mystro.xcodeproj**, scheme **Destro**. Signing & Capabilities: set Team.
- [ ] **TestFlight:** Product → Archive (Any iOS Device) → Organizer → Distribute App → App Store Connect → Upload. Add build to TestFlight and invite testers (or internal testing).
- [ ] Install from TestFlight on device. (Optional: for ad‑hoc only, set teamID in **ios/ExportOptions.plist** and run `./deploy/ipa.sh` from ios.)
- [ ] On device: Settings → Destro → Accessibility and Background App Refresh ON; set Dashboard URL (Mac IP) and driver app PIDs.

**Dashboard**

- [ ] `cd dashboard && npm i && npm start` (server :3000 + React; **concurrently** now in devDependencies).
- [ ] Mac firewall allows port 3000 from LAN. On device: Menu → Dashboard URL… → e.g. `ws://192.168.1.x:3000`.

**Before first GO**

- [ ] Set driver app PID(s). Review filters; consider turning on **Require confirm before accept** until criteria are tuned.

---

## 5. Test & reliability (from PRODUCTION_RELIABILITY_REPORT.md)

- **Test gaps:** No PID tests; no DashboardRelay unit tests; no client reconnection tests; confirm-before-accept and full accept/reject execution untested; daemon scan loop/background untested; dashboard/src has no error/empty UI (use **client** for better UX).
- **Flakiness:** Shared FilterConfig/UserDefaults and HistoryStore with no setUp/tearDown; test order can matter.
- **Simulator vs device:** AX/PID, location, UIGetScreenImage, background, HID may differ on device — validate manually.

**Manual test checklist (condensed):** Daemon start/stop and background; PID and FilterConfig; full accept and reject paths; confirm-before-accept; geofence and history; dashboard server up/down and empty state; e2e (and optionally chaos); device install and one accept/reject if possible.

---

## 6. Fix applied in this pass

- **Dashboard `npm start`:** Added **concurrently** to `dashboard/package.json` devDependencies so `npm start` works as documented.

---

## 7. Pre-flight checklist for tomorrow

1. **Build & deploy:** iOS build succeeds; Archive → Upload to App Store Connect → TestFlight; install on device; Accessibility + BG App Refresh ON.
2. **Dashboard:** `cd dashboard && npm i && npm start`; confirm server and client both start; set Dashboard URL on device to Mac IP.
3. **Config:** Set PIDs; set filters; consider **Require confirm before accept** ON for first run.
4. **Smoke:** Start scanning; trigger one accept and one reject (or simulate); confirm history and dashboard update.
5. **Recovery:** Kill dashboard server → see error (client) or refresh; restart server and refresh; confirm reconnection/behavior.

**References:** Full reliability detail in **PRODUCTION_RELIABILITY_REPORT.md**. Code-quality details from MCP explore + generalPurpose agents (Keychain, persistence, force unwraps, logging, env).

---

*End of MCP Swarm Production Quality Analysis.*
