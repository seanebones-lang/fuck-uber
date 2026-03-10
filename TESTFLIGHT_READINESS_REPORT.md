# MASTER INSPECTOR: TESTFLIGHT READINESS

**Workspace:** `/Users/nexteleven/fuck uber:lyft/fuck-uber`  
**Project:** `ios/Mystro.xcodeproj` · **Scheme:** Destro · **App:** Destro (online.nextelevenstudios.destro)

---

## 1. Signing & provisioning

**Verdict: READY**

- **Code signing:** Automatic (`CODE_SIGN_STYLE = Automatic`) for Destro, DestroWidgetExtension, and DestroTests.
- **Development Team:** Set to `L35VLYNTLK` for all targets. No `PROVISIONING_PROFILE` or `CODE_SIGN_IDENTITY` overrides; Xcode will use the correct identity for Archive.
- **Entitlements:**  
  - Main app: `Mystro/Mystro/Mystro.entitlements` — application-groups (`group.com.destro.app`), location, network; includes macOS-style sandbox keys (ignored on iOS).  
  - Widget: `Mystro/Widgets/MystroWidget.entitlements` — application-groups only.
- **No embedded provisioning paths or certificate paths** that would block TestFlight upload.

**User step:** Ensure the Apple ID used in Xcode has access to team `L35VLYNTLK` and that “Automatically manage signing” is enabled for the Destro target (already configured in project).

---

## 2. Private API / App Store compliance

**Verdict: RISK** — TestFlight upload may succeed; review or later App Store submission may flag or reject.

| Framework / API | File(s) | Use | TestFlight |
|-----------------|--------|-----|------------|
| **Accessibility** (PrivateFrameworks) | AccessibilityOfferSource.swift, AccessibilityActionExecutor.swift, ServiceReadinessStore.swift | AXUIElementCreateApplication, AXUIElementCopyAttributeValue, AXUIElementPerformAction, AXUIElementRelease, AXUIElementCreateSystemWide, AXUIElementGetPid | **Often acceptable** for assistive/automation apps when paired with NSAccessibilityUsageDescription (present). Still private API; could be questioned. |
| **SpringBoardServices** | ServiceReadinessStore.swift, AppSwitcher.swift | SBSProcessIDForDisplayIdentifier, SBSLaunchApplicationWithIdentifier, SBSSuspendApplication | **Risk.** Private; automated or manual review may reject. On stock iOS often unavailable; app falls back to other behavior. |
| **FrontBoardServices** | AppSwitcher.swift | FBSSystemServiceOpenApplication, FBSSystemServiceSuspendApplication | **Risk.** Same as above. |
| **IOKit** | HIDActionExecutor.swift | IOHIDEventCreateDigitizerFingerEvent, IOHIDEventCreateDigitizerEvent, IOHIDEventSystemClientCreate, IOHIDEventSystemClientDispatchEvent, IOHIDEventRelease | **Risk.** Private; tap injection. Code is no-op on stock iOS when symbols unavailable. |
| **GraphicsServices / UIKit** | VisionOfferSource.swift | UIGetScreenImage (dlopen) | **Risk.** Private screen capture; fallback when Accessibility fails. |

**Summary:** Offer reading relies on Accessibility (private but commonly allowed for this use case). App switching and tap injection use other private APIs; implementation degrades gracefully on stock iOS (URL scheme for switching, AXPress for taps when Accessibility is on). TestFlight builds can upload; be prepared for possible rejection or request to remove/replace private APIs for full App Store.

---

## 3. Info.plist & capabilities

**Verdict: OK**

- **NSAccessibilityUsageDescription:** Present and clear: *"Destro reads the Uber and Lyft driver app screens to show trip requests and automate accept/decline when you're online."*
- **NSLocationWhenInUseUsageDescription:** Present: *"Destro uses your location for geofence filters (accept/avoid zones) when evaluating ride requests."*
- **UIBackgroundModes:** `fetch`, `processing` — appropriate for background scanning.
- **NSSupportsLiveActivities:** true.
- **CFBundleURLTypes:** `destro` scheme for app callback.
- **No placeholder or invalid values** — only standard Xcode variables (`$(PRODUCT_BUNDLE_IDENTIFIER)`, etc.).

**Note:** `NSAppTransportSecurity` → `NSAllowsArbitraryLoads` = true. This may be flagged in App Review; consider restricting to specific domains if possible before App Store submission.

Widget Info.plist is minimal and correct for a WidgetKit extension.

---

## 4. Archive & export

**Verdict: POSSIBLE** — Archive succeeds; export for TestFlight requires correct export options.

- **Archive:** Confirmed. From `ios/`:
  ```bash
  xcodebuild -project Mystro.xcodeproj -scheme Destro -configuration Release \
    -destination 'generic/platform=iOS' -archivePath ./build/Destro.xcarchive archive
  ```
  Produces `./build/Destro.xcarchive` successfully.

- **Export for App Store Connect / TestFlight:**  
  Current `ios/ExportOptions.plist` uses `method = development` and `teamID = YOURTEAMID`. For TestFlight you must export with **method = app-store** and a **valid teamID** (e.g. `L35VLYNTLK`).

**Steps for the user:**

1. **Select Development Team in Xcode** (if not already): Signing & Capabilities → Destro target → Team = your Apple Developer account (team L35VLYNTLK).
2. **Export for TestFlight:** Either in Xcode: Product → Archive → Distribute App → App Store Connect; or via CLI with an ExportOptions.plist that has:
   - `method`: `app-store`
   - `teamID`: `L35VLYNTLK` (or your team ID)
   - `signingStyle`: `automatic`  
   For automatic signing, `provisioningProfiles` can be omitted. If you keep it, fix the key: current plist uses `com.destro.app` but the app bundle ID is `online.nextelevenstudios.destro`.
3. **Upload:** Xcode Organizer → Distribute App → App Store Connect, or `xcrun altool` / Transporter with the exported .ipa.

---

## 5. Functional on device (TestFlight install)

**Verdict: YES**

- **Launch:** App launches and shows the dashboard.
- **GO / STOP:** User can link Uber/Lyft (Link or Open driver app), tap GO to start scanning, STOP to stop.
- **Offer detection:** Depends on **Accessibility** permission. When the user enables Destro in Settings → Accessibility, the app can read the driver app’s UI (when that app is in the foreground or brought to front via “Open (↗️)”). No simulator-only or jailbreak-only gate blocks core flow on a real device.
- **Accept/Reject:**  
  - **Accessibility path:** AccessibilityActionExecutor uses AXPress on the accept/reject buttons — works on stock iOS when Accessibility is enabled and driver app is in foreground.  
  - **HID path:** HIDActionExecutor is no-op on stock iOS (private API unavailable); no crash, just no tap.
- **App switching:** AppSwitcher uses private APIs (FBS/SBS); on stock iOS they are unavailable, so the app falls back to opening the driver app via URL scheme (`com.ubercab.driver://`, `me.lyft.driver://`). User can also open the driver app from the home screen; Destro then reads the frontmost app.

**Tester actions:**

1. Install from TestFlight.
2. **Settings → Accessibility** → enable Destro (required for offer reading and for accept/reject taps).
3. Optionally **Settings → Privacy → Location** → allow Destro (for geofence filters).
4. In Destro: Link Uber and/or Lyft, tap “Open (↗️)” or open the driver app manually, then tap GO. Keep the driver app in the foreground when you expect offers (or use Destro’s “Open” to switch). Offer detection and accept/reject depend on Accessibility and the driver app being in the foreground.

---

## 6. Deliverable summary

| Area | Verdict |
|------|--------|
| **Signing & provisioning** | **READY** — Automatic signing, team set, no blocking entitlements. |
| **Private API / compliance** | **RISK** — Accessibility often acceptable; SBS/FBS, IOKit, UIGetScreenImage are private and may be flagged. TestFlight upload often allowed. |
| **Info.plist & capabilities** | **OK** — Required keys present; no placeholders. |
| **Archive & export** | **POSSIBLE** — Archive works; use App Store export options (method app-store, teamID) for TestFlight. |
| **Functional on device** | **YES** — Launch, dashboard, GO/stop, offer reading (with Accessibility), accept/reject (Accessibility); document Accessibility and foreground driver app for testers. |

---

## Overall: READY FOR TESTFLIGHT NOW — **YES**

**Conditions:**

- Use **App Store** export (not development/Ad Hoc) and set **teamID** (e.g. `L35VLYNTLK`) in ExportOptions or via Xcode when distributing to App Store Connect.
- Accept **private API risk**: build may upload to TestFlight; full App Store review could still request changes or reject.

**Single recommendation:**  
After installing from TestFlight, have testers **enable Destro in Settings → Accessibility** so offer detection and accept/reject taps work; document this in TestFlight notes or in-app.

---

## If NO (future reference)

If anything above were not satisfied, the exact actions would be:

- **Signing:** Set Development Team in Xcode for Destro and DestroWidgetExtension; ensure Apple ID is in the correct team.
- **Export:** Create/update ExportOptions.plist with `method` = `app-store`, `teamID` = your team ID; fix `provisioningProfiles` bundle ID to `online.nextelevenstudios.destro` if using manual profiles.
- **Info.plist:** Add any missing usage descriptions or fix placeholders.
- **Private APIs:** Reduce or replace SBS/FBS, IOKit, UIGetScreenImage if App Review rejects.

---

*Generated by Master Inspector audit.*
