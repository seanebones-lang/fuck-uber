# Destro — Mystro-Style iOS App for Uber/Lyft Drivers

For quality checklist and swarm-perfection order, see [SWARM_PERFECTION_ORDER.md](SWARM_PERFECTION_ORDER.md).

## What it does
- **One toggle:** Tap GO to cycle between Uber and Lyft driver apps and evaluate offers.
- **Criteria:** Min trip $, min $/mi, max pickup, no shared, ≤1 stop, geofence, active hours. Auto-accept or confirm-before-accept.
- **Offers in Destro:** You see offers in Destro; accept/reject taps happen via Accessibility when the driver app is in front.

## Quick reference (build, run, test)
| Goal | Command |
|------|---------|
| **Install deps** | `pnpm i` (root), `cd dashboard && npm i` (dashboard) |
| **Build iOS app** | `cd ios && open Mystro.xcodeproj` → scheme **Destro** → Cmd+R |
| **Build dashboard** | `pnpm run build` (builds dashboard) |
| **Run dashboard** | `cd dashboard && npm start` (server + client on port 3000) |
| **Run shared tests** | `pnpm test` (Vitest, `shared/`) |
| **Benchmark** | `pnpm run benchmark` (criteria check ± WebSocket mock) |
| **E2E / Chaos** | See [test/README.md](test/README.md) — start dashboard first, then `node test/e2e-test.js` or `node test/chaos-suite.js` |

---

## Ready to run (checklist)

1. **Open project:** `cd ios && open Mystro.xcodeproj` → scheme **Destro**, select your device or simulator.
2. **Signing:** Destro target → Signing & Capabilities → set your **Team**. Ensure **App Groups** is added with `group.com.destro.app` (main app and widget).
3. **Build & run:** Cmd+R. Install on device (or use TestFlight; see Deploy below).
4. **On device:**
   - **Settings → Accessibility** → turn **Destro** ON (required for offer reading).
   - **Settings → Destro** → Background App Refresh ON (optional).
5. **Link a service:** In Destro tap **GO**; when prompted, tap **Link** or **Open (↗️)** for Uber/Lyft Driver. **Open (↗️)** opens the driver app from Destro (Mystro-style). Sign in there, return to Destro, tap **GO** again.
6. **Offer reading:** Destro switches between the Uber and Lyft driver apps (via Accessibility + URL schemes, like Mystro). You can stay in Destro; when a request appears it shows in the Offer card. Enable **Settings → Accessibility → Destro** so we can read the driver app screens.
7. **Dashboard (optional):** On Mac run `cd dashboard && npm i && npm start`. In Destro **Menu → Dashboard URL…** set `ws://<your-mac-ip>:3000`.

---

## Deploy
1. `cd ios && open Mystro.xcodeproj` (scheme **Destro**).
2. Signing & Capabilities → set Team; ensure **App Groups** includes `group.com.destro.app` for Destro and DestroWidgetExtension.
3. **TestFlight:** Product → Archive (destination: Any iOS Device). Organizer → Distribute App → App Store Connect → Upload. Add build to TestFlight and invite testers.
4. Install from TestFlight on your device.
5. Settings > Destro > Accessibility/BG App Refresh ON.
6. `cd dashboard && npm i && npm start` (localhost:3000 charts).

*Optional – local IPA for development only:* From ios directory, `./deploy/ipa.sh` → Destro.ipa (set teamID in `ios/ExportOptions.plist`). Use for ad‑hoc installs or Xcode Devices; for distribution use TestFlight above.

## Dashboard
Root dashboard.js has been removed (stub); use dashboard/ for the WebSocket dashboard.

## Using Destro

- **Linking:** Use **Link** on the Uber/Lyft card (or **Link Uber Driver** / **Link Lyft Driver** when you tap GO). Do **not** rely on opening an app from Destro—open **Uber Driver** or **Lyft Driver** from your home screen and sign in there. Use **Unlink** on the card if you need to clear and re-link.
- **Dashboard on device:** **Menu → Dashboard URL…** → e.g. `ws://192.168.1.x:3000`. Status shows "Dashboard: connected" when linked.
- **Accessibility:** For offer reading, enable Destro in **Settings → Accessibility**.
- **Driver app PID:** Destro connects the same way Mystro does—using only **Accessibility** (no special permission). It brings the driver app to the front, then reads the frontmost app’s UI, so you don’t need to enter a PID. If that doesn’t work on your device, use **Menu → Set driver app PID…** or **Set PID** on each service card. To get the PID manually: connect the device to a Mac, open Console.app, run the driver app, and filter by process name.
- **Filters:** Tap a service card’s filters to set min trip $, min $/mile, min $/hr, max pickup (mi), auto-accept, auto-reject, **Require confirm before accept** (shows Accept/Decline alert per offer), and active hours (0–23).
- **Menu:** **Export history** (CSV share), **Set daily goal…** (persisted), **View logs** (last 10 lines), Dashboard URL, Set driver app PID, About.

Geofence accept/avoid zones are supported in config; in-app zone editing is available in **Filters** (Geofence zones: Add zone, Delete per row). Optional ML: add **RidePredictorModel.mlmodelc** (or `.mlmodel`) to the app target for on-device ride scoring; inputs: price, miles, surge, timeOfDay, pickupZoneHash; outputs: qualityScore, predictedEarnings. Heuristic used if the model is missing.

**Background:** iOS limits how long apps run in the background. For reliable scanning, keep Destro in the foreground (or on screen); background time is limited and scanning may pause when the app is backgrounded.

## Build IPA (optional – dev / ad‑hoc)
Run from the **ios** directory: `cd ios && ./deploy/ipa.sh`. Set **teamID** in `ios/ExportOptions.plist` before building. For **TestFlight** distribution use Product → Archive and upload via Organizer (see Deploy above).

## Test
- Open Uber Driver/Lyft Driver → Simulate ping → Auto-accept + haptic/notif/log/chart.
- Tests: Cmd+U in Xcode (DestroTests). Run shared criteria test: `pnpm test` (or `vitest run shared/`). Dashboard: `cd dashboard && npm test`.

---

## How it works (stock iOS)

- **Offer reading:** Destro uses **Accessibility** (Settings → Accessibility → Destro) to read the frontmost app’s UI. It brings each driver app to the front via its URL (`com.ubercab.driver://`, `me.lyft.driver://`), reads the screen, then opens `destro://` so you see the offer in Destro. No private “switch app by PID” API is required; URL schemes + frontmost app are enough.
- **Accept/Reject:** When you accept or when auto-accept runs, Destro brings that driver app to the front and uses Accessibility to tap the Accept or Decline button, then returns to Destro. So taps only work when Accessibility is enabled and the driver app is in the foreground when we tap.
- **PID:** You don’t need to set a PID. We use the frontmost application (the one we just opened by URL). Set PID only if automatic detection fails on your device.

## Limitations

- **Accessibility required:** Offer detection and accept/reject taps depend on Destro being enabled in Settings → Accessibility. If Uber or Lyft change their app layout, parsing or button positions may need updates.
- **Foreground:** For reliable scanning, keep Destro in the foreground (or on screen). Background time is limited; scanning may pause when the app is backgrounded.
- **Personal use:** iOS-only. Use at your own risk; ensure compliance with platform and driver app terms.

  **Console:** "Couldn't read values in CFPrefsPlistSource... group.com.destro.app" is a known system warning when the app group isn’t available (e.g. Simulator); the app handles it and uses safe defaults. "[S:N] Error received: Connection invalidated" is from URLSession when the dashboard WebSocket closes (e.g. app backgrounded); normal—status will show "Dashboard: disconnected".

iOS-only, personal use. TestFlight-ready.
