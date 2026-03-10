# Iteration Roadmap v1.1 – Addendum

**Ref:** ENGINEERING_REPORT.md v1.1  

**Note (Destro rename):** App name is **Destro**; app group `group.com.destro.app`, bundle IDs `com.destro.app` / `com.destro.app.widget`. Xcode project lives under **ios/Mystro**; open `ios/Mystro/Mystro.xcodeproj` and use scheme **Destro**. Dashboard URL key: `destro.dashboard.wsURL`.

## Implemented in this pass

- **ExportOptions.plist:** Template at `ios/ExportOptions.plist` (set `teamID`). Run `./deploy/ipa.sh` from `ios/` for ad‑hoc IPA. For **TestFlight** use Xcode: Product → Archive → Organizer → Distribute App → App Store Connect.
- **Location:** Entitlement `com.apple.security.personal-information.location` set to **true** in Destro.entitlements.
- **App Group:** `group.com.destro.app` (main app and widget). **AppGroupStore** writes status, session earnings, conflict state.
- **PID discovery:** `ServiceReadinessStore.discoverPID(for:)` + `storedPID` / `storePID`. Private API stub returns nil; set PIDs via **Menu → Set driver app PID** or **Set PID** on each service card.
- **DynamicRuleEngine in CriteriaEngine:** CriteriaEngine uses `DynamicRuleEngine.shared.effectiveThresholds(idleMinutes: ProdDaemon.idleMinutesForCriteria)` for minPrice, minPricePerMile, maxPickupDistance. `ProdDaemon.lastDecisionTime` updated on accept/reject.
- **Ride completion:** After accept, `startRideCompletionPoller` runs every 10s; 2 consecutive nil offers for active app → `conflictManager.rideCompleted(wasActiveAppBundleId:)`.
- **Dashboard relay:** **DashboardRelay** (URLSessionWebSocketTask) connects to `ws://localhost:3000`, sends `decision`, `state`, `earnings`, `conflict_state`. Reconnects on failure. On device set URL via `DashboardRelay.shared.setBaseURL("ws://<Mac IP>:3000")` if needed.
- **Adaptive fallback:** **AdaptiveFallbackOfferSource**: after 3 consecutive nils from primary, uses only fallback for 10 cycles. AppDelegate uses it instead of FallbackOfferSource.
- **Tap retry:** HIDActionExecutor retries injectTap up to 3 times with 100 ms delay between attempts.

**Dashboard URL (device → Mac):** DashboardRelay persists the WebSocket URL in UserDefaults (`destro.dashboard.wsURL`). **Menu → Dashboard URL…** lets the user set the Mac’s URL (e.g. `ws://192.168.1.10:3000`).

**Geofence when location denied:** GeofenceManager exposes `isLocationUsable` and updates it in `locationManagerDidChangeAuthorization`. When location is denied or restricted, `shouldRejectByGeofence` returns `false` (geofencing off so offers aren’t incorrectly rejected). `isInAcceptZone` returns `true` and `isInAvoidZone` returns `false` when not usable.

## Misaka26 / iOS 26.2 (March 2026)

- Full jailbreaks **not** available for iOS 26.2 on A18 (iPhone 16). Misaka26 supports up to **26.1** and **26.2 beta 1**; public 26.2 (and patches) break compatibility for many (e.g. MobileGestalt patched). Expect **partial or flaky** private API behavior on 26.2—test AX, HID, and app switching on your firmware.

## Known gaps – risk & effort (v1.1)

| Gap | Risk | Effort | Status |
|-----|------|--------|--------|
| Widget extension target not in Xcode | High | 1–2 h | **Done.** Target DestroWidgetExtension added in project.pbxproj; Widgets group (DestroWidget.swift, Info.plist, DestroWidget.entitlements), embedded in Destro app. Set development team for both Destro and DestroWidgetExtension in Xcode. |
| PID private API (enumeration) | Medium | 2–4 h | Stub returns nil; use stored/manual PID. |
| CoreML RidePredictor | Low | 4–8 h | **Integration done.** RidePredictor tries to load `RidePredictorModel.mlmodelc` (or `.mlmodel`); if present, uses inputs price, miles, surge, timeOfDay, pickupZoneHash and outputs qualityScore, predictedEarnings. Otherwise uses heuristic. Add a trained .mlmodel to the app target and name it RidePredictorModel. |
| UIGetScreenImage on newer iOS | Medium | 2–4 h | May need Misaka26 or other capture path. |

## Widget Extension: Step-by-Step

**Done in project.** The Xcode project now includes:

1. **DestroWidgetExtension** target (app extension), product `DestroWidgetExtension.appex`.
2. **Widgets** group at `ios/Mystro/Widgets` with DestroWidget.swift, Info.plist, MystroWidget.entitlements (app group `group.com.destro.app`).
3. **Embed Foundation Extensions** build phase on Destro target to embed the .appex.
4. Bundle ID for widget: `com.destro.app.widget`. Code signing: set development team for **Destro** and **DestroWidgetExtension** in Signing & Capabilities.

To build: open `ios/Mystro/Mystro.xcodeproj`, select scheme **Destro**, then Build (Cmd+B).

**CoreML RidePredictor:** RidePredictor loads `RidePredictorModel.mlmodelc` if present (inputs: price, miles, surge, timeOfDay, pickupZoneHash; outputs: qualityScore, predictedEarnings). Add a trained .mlmodel to the Destro target and name it RidePredictorModel; otherwise the heuristic is used.
