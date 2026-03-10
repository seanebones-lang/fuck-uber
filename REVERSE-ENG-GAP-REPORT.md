# Reverse-engineering gap report

*Swarm run: full Mystro clone pivot + reverse-engineering gaps + iOS-only improvements.*

---

## 1. Current feature inventory (summary)

| Area | Status | Notes |
|------|--------|--------|
| **Driver app control** | Implemented | AX offer read + Vision fallback; AX accept/reject + HID fallback; daemon cycle; confirm-before-accept; ride completion poller. |
| **Filters & criteria** | Implemented | FilterConfig + CriteriaEngine + DynamicRuleEngine; geofence; all DecisionReason cases. |
| **Dashboard / relay** | Implemented | WebSocket server (port 3000), React client, connection status, chart; no persistence. |
| **Earnings & conflict** | Implemented | EarningsTracker, ConflictManager, HistoryStore, AppGroupStore for widget. |
| **UI** | Implemented | Dashboard, filters, history, widgets, intents; **Live Activity** start/end exist but **update never called** (stale). |
| **Geofence** | Implemented | GeofenceManager + CriteriaEngine; accept/avoid zones. |
| **Vision / HID** | Partial / stub | Vision no-op on stock iOS without screen capture; HID no-op on stock. DiDi/DoorDash UI-only. RidePredictor ETA placeholder. |

---

## 2. Mystro clone feature checklist

*Public Mystro features (reviews, mystrodriver.com, Quick Start): multi-app (Uber, Lyft, delivery), one toggle online, open driver apps only from app (↗️), Accessibility-only reading, auto accept/reject with filters (fare, $/mi, $/hr, distance, job type), 5s/30s countdown, dashboard (dashboard.mystro.studio), conflict handling, earnings, geofence.*

| Feature | In Destro | Partial | Missing | Notes |
|---------|-----------|---------|---------|--------|
| Offer detection (AX) | ✓ | | | Primary. |
| Accept / Reject (AX + HID fallback) | ✓ | | | HID no-op on stock. |
| Filters: min price, $/mi, pickup, surge, ride type, geofence, hours | ✓ | | | |
| Dashboard / WebSocket | ✓ | | | No persistence. |
| Earnings / session | ✓ | | | |
| Conflict (one app active) | ✓ | | | |
| Confirm-before-accept | ✓ | | | |
| Multi-app cycling | ✓ | | | |
| Open from app (↗️) | ✓ | | | |
| Widgets / Shortcuts | ✓ | | | |
| 5s / 30s countdown | | ✓ | | Not explicit in UI. |
| Delivery / other platforms | | | ✓ | DiDi/DoorDash UI only. |
| Per-service tabs | | | ? | Verify vs Mystro. |

---

## 3. Reverse-engineering surface & gaps

- **Accessibility (private):** Primary for offer read, accept/reject, frontmost PID. Fallback accept point when AXFrame unavailable (e.g. Misaka26 partial AX). App Review risk.
- **HID (IOKit):** Fallback tap injection; **no-op on stock iOS** when API unavailable; no user feedback when tap fails.
- **URL schemes:** `destro://` + driver `bundleId://` used when AppSwitcher (FBS/SBS) unavailable on stock iOS.
- **Vision:** OCR fallback; **returns nil on stock iOS** without injected screen capture.
- **AppSwitcher:** FBS/SBS when available; **no-op on stock**; `isAppRunning` may false-negative on stock.
- **PID:** Frontmost AX + optional SBS; `discoverPIDSync` can block (semaphore wait). Comments: “stock iOS” vs “Misaka26” throughout; no single “what works where” for users.

---

## 4. Missed or incomplete (sweep)

*Sweep: TODO/FIXME/HACK/stock iOS/jailbreak/Misaka/placeholder. Searched: ios/, dashboard/client, shared, test.*

### (a) Reverse-engineering / platform
- **ProdDaemon** — Default offer source nil on stock; bring-to-foreground uses private API (Misaka26) or URL fallback.
- **AccessibilityOfferSource** — Fallback accept point (bottom-center) when AXFrame unavailable; may miss button.
- **VisionOfferSource** — Screen capture Misaka26/jailbreak or injected; nil on stock iOS.
- **HIDActionExecutor** — No-op on stock; no “HID unavailable” feedback to user.
- **AppSwitcher** — `isAppRunning` best-effort, may be false on stock.
- **ServiceReadinessStore** — SBS PID optional; relies on frontmost AX.
- **DaemonTypes** — Default ActionExecutor no-op on non-jailbroken; callers may not check return value.

### (b) Feature completeness
- **ServiceReadinessStore** — “Ready” when we have confirmation; Keychain token for future API only.
- **RidePredictor** — `estimatedMinutesToPickup` placeholder (use MKDirections); model load failure only printed.
- **DashboardViewController** — PID alert shown with “stock iOS: not available”; version “iOS 26.2 may have limited support” with no runtime warning.
- **DashboardRelay** — No-op when server unreachable; no UI indication.

### (c) Edge cases / error handling
- **DaemonTypes** — Adaptive fallback (3 nils → 10 cycles); no logging/metrics.
- **VisionOfferSource** — OCR failure only printed.
- **DashboardRelay** — JSON send failure only printed; payload loss possible.
- **DestroUITests** — Fallback "GO" vs "Go online"; brittle if copy changes.

### (d) iOS version / device
- **DashboardViewController** — iOS 26.2 limited support; no in-app check or warning.
- **AppSwitcher** — `isAppRunning` may false-negative on stock.
- **HIDActionExecutor** — No-op on stock; no user-visible “HID unavailable”.

### Summary of highest-risk gaps
1. **Stock iOS / Misaka split** — Offer read, app switch, tap injection degrade or no-op on stock; no single “what works where” for user/support.
2. **Accept point fallback** — Fixed bottom-center when AXFrame unavailable; layout/safe-area can cause wrong or missed taps.
3. **Silent failures** — Vision OCR, CoreML load, relay send only log; no retry or user-visible state.
4. **PID on stock** — PID UI shown with “not available on stock”; confusing; consider hide/disable when not applicable.
5. **iOS 26.2+** — Version string warns “limited support”; no runtime detection or in-app notice.

---

## 5. iOS-only features and improvements

### 1. Current iOS-only feature map

| Category | File(s) | What it does |
|----------|---------|----------------|
| **App Intents / Siri Shortcuts** | `Mystro/MystroIntents.swift` | AppIntents: `GoOnlineIntent`, `GoOfflineIntent`, `GetEarningsIntent`, `SetMinimumPriceIntent` (with `@Parameter` for minimum $). `DestroShortcuts` (AppShortcutsProvider) exposes phrases/short titles for Siri and Shortcuts. No `.intentdefinition`; intents are code-only. |
| **Widgets** | `Widgets/MystroWidget.swift`, `Widgets/Info.plist`, `Widgets/MystroWidget.entitlements` | WidgetKit: `DestroProvider` (TimelineProvider), `DestroWidget` (StaticConfiguration), `DestroWidgetBundle`. Reads App Group UserDefaults (`status`, `lastApp`, `sessionEarnings`). Supports `.systemSmall`, `.systemMedium`, `.systemLarge`. iOS 17+ `containerBackground(for: .widget)`. |
| **Live Activities** | `Mystro/MystroLiveActivity.swift`, `Mystro/Info.plist` | ActivityKit: `DestroLiveActivity` (ActivityAttributes + ContentState: status, activeApp, sessionEarnings, timeOnline). `startDestroLiveActivity()` / `endDestroLiveActivity()` called from DashboardViewController on go online/offline. `updateDestroLiveActivity()` is **defined but never called**—Live Activity content is not updated during scan. `NSSupportsLiveActivities` = true. |
| **Background Modes** | `Mystro/Info.plist`, `Mystro/AppDelegate.swift` | `UIBackgroundModes`: `fetch`, `processing`. AppDelegate uses `beginBackgroundTask` / `endBackgroundTask` when entering background while scanning (no BGTaskScheduler/BGAppRefreshTask). |
| **URL schemes** | `Mystro/Info.plist`, `Mystro/ProdDaemon.swift` | `destro` scheme (CFBundleURLTypes, Editor). ProdDaemon opens `destro://` via `UIApplication.shared.open` to bring app to foreground after reading each driver app. No custom `application(_:open:options:)` handler. |
| **Accessibility (UI)** | `Mystro/DashboardViewController.swift`, `Mystro/Info.plist` | `accessibilityLabel` / `accessibilityHint` / `isAccessibilityElement` on Drive/History tabs, Go button, status, filters, link/unlink, open. `NSAccessibilityUsageDescription` for reading Uber/Lyft screens. |
| **Accessibility (AX – reading/acting)** | `Mystro/AccessibilityOfferSource.swift`, `Mystro/AccessibilityActionExecutor.swift`, `Mystro/ServiceReadinessStore.swift` | Private AX (dlopen): AXUIElementCreateApplication, AXRole/AXTitle/AXValue/AXFrame/AXChildren, traverse tree to parse offers and find accept/reject buttons. ActionExecutor uses AXPress. ServiceReadinessStore uses AXUIElementCreateSystemWide + AXFocusedApplication for frontmost PID. |
| **HID** | `Mystro/HIDActionExecutor.swift`, `Mystro/AppDelegate.swift`, `Mystro/Info.plist` | Fallback executor: IOHIDEvent (IOHIDEventCreateDigitizerFingerEvent, IOHIDEventSystemClientDispatchEvent, etc.) for tap injection when AX fails. `UIApplicationSupportsIndirectInputEvents` = true. |
| **Vision** | `Mystro/VisionOfferSource.swift` | Fallback offer source: Vision framework (`VNRecognizeTextRequest`, `VNImageRequestHandler`, `VNRecognizedTextObservation`) to parse offer text from screenshots when AX unavailable. |
| **App switching (private)** | `Mystro/AppSwitcher.swift` | FBSSystemService/FrontBoard dlopen: `bringToForeground(bundleId:)`, `sendToBackground(bundleId:)`; no-op when private API unavailable (URL scheme used instead). |
| **Notifications** | `Mystro/ProdDaemon.swift`, `Mystro/DashboardViewController.swift`, etc. | In-app only: `NotificationCenter` for `destroOfferSeen`, `destroConfirmAcceptRequested`, `destroAcceptTapFailed`, `destroRejectTapFailed`, `destroDaemonDidBecomeIdle`, relay connection. No UNUserNotificationCenter, push, local notifications, or notification content extension. |
| **App Group** | `Mystro/AppGroupStore.swift`, `Mystro/Mystro.entitlements`, `Widgets/MystroWidget.entitlements` | `group.com.destro.app` for sharing scan status, lastApp, sessionEarnings, conflictState between app and widget. ProdDaemon/Dashboard write; widget reads on timeline. |
| **Scene lifecycle** | `Mystro/Info.plist`, `Mystro/AppDelegate.swift` | `UIApplicationSceneManifest` with `UIApplicationSupportsMultipleScenes` = false. Classic AppDelegate + single UIWindow + DashboardViewController; no UISceneDelegate. |
| **Other** | `Mystro/AppDelegate.swift`, `Mystro/ViewController.swift`, `Mystro/LaunchScreen.storyboard` | UIKit lifecycle, `UIScreen.main.bounds`, `UIApplication.openSettingsURLString`, LaunchScreen storyboard. `NSLocationWhenInUseUsageDescription` for geofence. |

---

### 2. Missing or underused iOS capabilities

| Capability | Priority | Effort | Notes |
|------------|----------|--------|--------|
| **Live Activity content updates during scan** | **High** | Quick win | `updateDestroLiveActivity()` exists but is never called. ProdDaemon already writes status/lastApp/earnings to AppGroupStore; call `updateDestroLiveActivity` from the same code paths (e.g. where `AppGroupStore.writeStatus` is called) so Lock Screen / Dynamic Island show live progress. |
| **Shortcuts with more parameters** | **High** | Quick win | Add intents e.g. “Set minimum $/mile”, “Set max pickup distance”, “Go online on Uber only” (service parameter). Expose as App Shortcuts with clear phrases. |
| **Widget configuration (IntentConfiguration)** | **Medium** | Medium | Allow user to choose what the widget shows (e.g. status only vs status + earnings, or compact vs detailed). Use `IntentConfiguration` + a custom Intent for widget family or content preference. |
| **Lock Screen widgets** | **Medium** | Quick win | Add `.accessoryCircular` / `.accessoryRectangular` / `.accessoryInline` to widget `supportedFamilies` so Destro appears on Lock Screen (iOS 16+). |
| **BGTaskScheduler for background refresh** | **Medium** | Medium | Info.plist has `fetch` and `processing` but no `BGTaskScheduler`/`BGAppRefreshTask` usage. Register a refresh task to periodically wake and e.g. update widget or re-check state; improves “always up to date” feel when app is not in foreground. |
| **Local / push notifications** | **Medium** | Medium | No UNUserNotificationCenter. Add: (1) local notification when offer meets filters (e.g. “High-value offer on Uber”) or when accept/reject fails; (2) optional push for critical alerts. Improves Mystro-like “see offer without opening app.” |
| **Notification Content Extension** | **Low** | Medium | If push/local notifications are added, add a Notification Content Extension to show offer summary (price, miles, app) in the notification. |
| **Focus filters** | **Low** | Larger effort | Integrate with Focus (e.g. “When Driving focus is on, only show Destro widget / allow scans”). Requires Focus filter API and UX for enabling. |
| **Control Center integration** | **Low** | Medium | Control Center module to “Go online” / “Go offline” / “Session earnings” without opening app. Uses Control Center extension APIs. |
| **Haptics** | **Low** | Quick win | Add UIImpactFeedbackGenerator / UINotificationFeedbackGenerator on key actions: go online/offline, offer accepted/rejected, tap failed. |
| **Accessibility improvements** | **Medium** | Medium | Improve VoiceOver: group offer cards as accessibility elements, announce “Offer: $X, Y mi” when new offer appears; ensure all filter and service cards have clear labels and hints. |
| **iPad layout** | **Low** | Larger effort | Info.plist supports iPad orientations but layout is phone-first. Add iPad-optimized layout (e.g. sidebar, split view for filters vs dashboard) for a full Mystro clone. |
| **Watch app** | **Low** | Larger effort | watchOS companion: view status, session earnings, optionally “Go online” / “Go offline” via Watch. |

---

### 3. Recommended next steps

- **Call `updateDestroLiveActivity` from scan loop**  
  Where ProdDaemon (or Dashboard) updates `AppGroupStore.writeStatus` / `writeSessionEarnings`, also call `updateDestroLiveActivity(status:activeApp:sessionEarnings:timeOnline:)` so Live Activity reflects current state. Pass `EarningsTracker.shared.sessionEarnings().total` and elapsed time online.

- **Add Lock Screen widget families**  
  In `MystroWidget.swift`, add `.accessoryCircular`, `.accessoryRectangular`, and optionally `.accessoryInline` to `supportedFamilies`, and add small views for each so Destro is visible on Lock Screen.

- **Extend App Intents**  
  Add parameters to existing intents (e.g. min $/mile, max pickup) and new intents: “Set max pickup distance”, “Go online on [Uber | Lyft] only”. Register new phrases in `DestroShortcuts`.

- **Introduce BGTaskScheduler**  
  Register `BGAppRefreshTask` (and optionally `BGProcessingTask`) in AppDelegate, schedule after going to background when scanning. In the task, update App Group data (and optionally call `updateDestroLiveActivity`) and refresh widget timeline.

- **Add local notifications for offers**  
  Request notification permission; when an offer is seen and meets filters (or on accept/reject failure), post a local notification with body like “Uber: $X.X – Y mi” so the user can react without having the app open.

- **Improve accessibility of offer and filter UI**  
  Make offer cards and filter rows proper accessibility elements with labels/hints; add live region or announcement when a new offer appears so VoiceOver users get the same at-a-glance info.

- **Add haptic feedback**  
  Trigger light impact on go online/offline and success notification on accept/reject; error notification on tap failed.
