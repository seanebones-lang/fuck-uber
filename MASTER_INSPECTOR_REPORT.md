# Destro – Master Inspector Report: Production Readiness

**Date:** March 2026  
**Scope:** Can you actually use Destro to log into Uber/Lyft and have all features work? What’s missing? What should be improved?

---

## 1. Are the pathways there to “log in” to Uber and Lyft?

**Short answer: Yes, but only in the way Destro is designed – there is no in-app OAuth.**

- **What exists:**  
  - You install **Uber Driver** and **Lyft Driver** from the App Store.  
  - In Destro you see **Uber** and **Lyft** cards. Tapping **Link** (or the unlinked state) shows: *“Open the [Uber/Lyft] driver app to sign in. Destro will use it when you’re online.”*  
  - You tap **Open Uber** (or **Open Lyft**) → the system opens the driver app (`uber://` or the app).  
  - Destro then **marks that service as “linked”** (`ServiceReadinessStore.markLinked(bundleId)`).  
  - **GO** is only enabled if at least one enabled service is “linked” (`canGoOnline()`).

- **What “linked” means:**  
  “I have this driver app and will use it.” Destro does **not** log you into Uber/Lyft itself. You sign in inside the Uber/Lyft driver apps; linking in Destro just tells the app “include this app when I tap GO.”

- **Verdict:** The pathways are there: install driver apps → Link in Destro → open driver app and sign in there. No extra “log into your Uber/Lyft account” flow inside Destro.

---

## 2. Will all features work? (Reality check)

| Feature | Stock iOS (no Misaka26) | With Misaka26 / jailbreak-style |
|--------|---------------------------|----------------------------------|
| **Link Uber/Lyft** | ✅ Yes (mark linked, open app) | ✅ Yes |
| **GO / STOP** | ✅ Starts/stops daemon | ✅ Same |
| **Offer reading (see trip requests)** | ❌ No | ⚠️ Only if PID is set (see below) |
| **Auto-accept / auto-reject (tap)** | ❌ No (HID private API) | ✅ Yes, if entitlements allow |
| **Conflict handling (other app background/foreground)** | ❌ No (FrontBoard private API) | ✅ Yes |
| **Filters, criteria, min $, geofence** | ✅ Evaluated when offer exists | ✅ Same |
| **Dashboard (WebSocket)** | ✅ Yes (set URL in menu) | ✅ Yes |
| **Widget / Live Activity** | ✅ Status, earnings | ✅ Same |
| **Location / geofence** | ✅ CoreLocation | ✅ Same |
| **Ride completion detection** | ❌ No offers → no detection | ✅ When offers are read |
| **Siri / Shortcuts** | ✅ Intents run | ✅ Same |

So:

- **On stock iOS:** You can “link” and tap GO, but the app **cannot read** the Uber/Lyft screens or **tap** Accept/Decline. You get filters, dashboard, widget, and Siri, but **no automated offer handling**.
- **On Misaka26 (or similar):** Full automation **depends on** (1) **PID** for each driver app and (2) **Accessibility** permission, or you still get no offer reading.

---

## 3. What is missing? (Blockers for “actually use”)

### 3.1 PID for offer reading (critical)

- **AccessibilityOfferSource** reads the driver app’s UI via **AX** and **requires the app’s process ID (PID)**.  
- **`ServiceReadinessStore.discoverPID(for:)`** tries private discovery (`tryPrivatePIDDiscovery`) then falls back to **stored** PID (`destro.pid.<bundleId>` in UserDefaults).  
- **`tryPrivatePIDDiscovery`** is a **stub** (returns `nil`). So PID only exists if something else sets `destro.pid.com.ubercab.driver` and `destro.pid.me.lyft.driver`.

**Missing:**  
- **No UI** to set or view PID. There is no Settings screen or service-card option to “Set process ID” or “Enter PID” for Uber/Lyft.  
- So on a normal install (including many Misaka26 setups), **offer reading never works** unless the user (or a tweak) writes PID into UserDefaults by some other means.

**Consequence:** Without PID, `fetchOffer` is always `nil` for the AX source → fallback to Vision → Vision uses `UIGetScreenImage` (private), which fails on stock and may be restricted on 26.2. Result: **no offers**, so no auto-accept/reject and no ride-completion detection.

### 3.2 Accessibility permission

- To read **another app’s** UI (AX with PID), iOS requires **Destro to be enabled in Settings → Accessibility** (and possibly “Full access” or similar, depending on OS).  
- **Info.plist** has no `NSAccessibilityUsageDescription` (or equivalent). The app doesn’t prompt or explain that the user must turn on Accessibility for Destro.  
- **Missing:** Clear in-app or doc instruction: “Enable Destro in Settings → Accessibility so it can read the driver app when offer reading is used.”

### 3.3 User feedback when offer reading / tap is unavailable

- If PID is missing or AX fails, the daemon keeps scanning but gets no offers.  
- **Missing:** Any alert or status like “Offer reading unavailable – set driver app PID in Settings” or “Tap injection not available on this device.”  
- So the user can think “GO is on” but nothing is happening, with no explanation.

### 3.4 Firmware / Misaka26 compatibility

- **ENGINEERING_REPORT** and **ITERATION_ROADMAP** already state: full jailbreaks not available for **iOS 26.2** on A18 (iPhone 16); Misaka26 supports up to **26.1** and **26.2 beta 1**; public 26.2 can be unstable.  
- So on **your** device (e.g. iPhone 16 / 26.2), private APIs (AX, HID, FrontBoard) may be **partial or flaky**. That’s an environment limitation, not something “missing” in the code, but it affects “ready to actually use.”

---

## 4. What needs to be improved?

### 4.1 Must-have for “actually use” (especially with Misaka26)

1. **PID entry in the app**  
   - Add a way to set (and optionally display) PID for each linked service (e.g. Uber, Lyft).  
   - Examples: Settings → “Driver app process ID” with two fields (Uber PID, Lyft PID), or on the service card: “Set PID” that stores into `destro.pid.<bundleId>`.  
   - Document or hint: “Get PID from your environment (e.g. Misaka26 / system tool) and enter it here so Destro can read the driver app.”

2. **Accessibility instruction**  
   - In-app (e.g. first GO or in Settings) and/or README: “For offer reading, enable Destro in **Settings → Accessibility**.”  
   - Optionally add `NSAccessibilityUsageDescription` in Info.plist if you use any public Accessibility API that shows the system prompt.

3. **Clear feedback when automation can’t run**  
   - When user taps GO: if no PID is set for any enabled app (or AX clearly unavailable), show a one-time or dismissible alert: “Offer reading needs the driver app’s process ID (see Settings). Until then, automation won’t run.”  
   - Optionally, when a tap fails (e.g. HID not available), surface a short message so the user knows tap injection isn’t active.

### 4.2 Should-have

4. **Implement or document PID discovery**  
   - Either implement `tryPrivatePIDDiscovery` using a Misaka26- or jailbreak-appropriate API (e.g. SpringBoardServices / sysctl) so PID is discovered when possible, or document the exact steps (or a small helper script) to obtain and set PID for Uber/Lyft.

5. **Ride completion and conflict**  
   - Ride completion today depends on “no offer” for two consecutive 10s polls. If offer reading never works (no PID), this never triggers. Once PID and AX work, this path is there; consider a “I’m back” / “Trip ended” manual button as fallback.

6. **Dashboard URL on device**  
   - Already supported (Menu → Dashboard URL). Ensure README or in-app help says: “On device, set your Mac’s IP (e.g. `ws://192.168.1.x:3000`) so the phone can reach the dashboard.”

### 4.3 Nice-to-have

7. **Stock iOS behavior**  
   - On stock iOS, either hide or disable “GO” (or show “Not available on this device”) so it’s clear that full automation isn’t supported without Misaka26/jailbreak-style access.

8. **Version / compatibility note in app**  
   - e.g. in About or first launch: “Optimized for Misaka26 / iOS 26.1; iOS 26.2 may have limited support.”

---

## 5. Summary: Ready to actually use?

| Question | Answer |
|----------|--------|
| **Can I “log in” to Uber and Lyft?** | Yes – by opening the driver apps and signing in there; in Destro you “Link” each service so GO can use it. |
| **Are all pathways there?** | Link/open app pathway: yes. **PID pathway is missing in the UI** – no way to set PIDs for offer reading. |
| **Will all features work?** | **No** on stock iOS (no offer read, no tap, no app switch). **Only with Misaka26 + PID set + Accessibility** will offer read, tap, and conflict handling work. |
| **What is missing?** | (1) **UI to set PID** for Uber/Lyft, (2) **Accessibility** guidance (and optionally plist), (3) **User-visible feedback** when offer read or tap is unavailable. |
| **What needs to be improved?** | Add PID entry and Accessibility instructions; add feedback when automation can’t run; optionally implement or document PID discovery; consider fallback “Trip ended” and clearer stock-iOS behavior. |

**Bottom line:** The app is **not** “ready to actually use” for full automation until you (or a tweak) can set PIDs for the driver apps and enable Accessibility. With **PID entry UI + Accessibility instructions + clear feedback** (and a compatible device/Misaka26 setup), the code paths are in place for offer reading, auto-accept/reject, and conflict handling to work.

---

## Implementations (post-inspection)

- **PID entry:** Menu → Set driver app PID… (Uber/Lyft PIDs stored via ServiceReadinessStore).
- **GO-time alert when no PID set:** prompt to set PID or go anyway; message includes Accessibility instruction.
- **NSAccessibilityUsageDescription** added to Info.plist.
- **Manual "I'm back" button** when ride active (calls conflictManager.rideCompleted).
- **README:** Dashboard URL, Accessibility, PID setup.
- **About:** compatibility note (Misaka26 / 26.1; 26.2 limited).
