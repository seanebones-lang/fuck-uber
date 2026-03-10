# Destro – Ride-Share Driver App Expert Rating & Improvements

**Perspective:** Fresh eyes as a ride-share driver app expert. Rate the app on what matters to drivers, then list concrete improvements.

---

## 1. Expert Rating (out of 10)

| Dimension | Score | Notes |
|-----------|--------|--------|
| **Reliability** | 8/10 | Bring-to-foreground before tap, daemon/UI sync, tap-failure alert, 15s ride-completion delay. Loses points: AX/parsing can break on app updates; no in-app “last seen offer” fallback. |
| **Earnings clarity** | 7/10 | Session + today $ and trip count on dashboard; Siri “What are my earnings?”; widget shows session $. Missing: breakdown by app (Uber vs Lyft) visible at a glance; daily goal progress not surfaced in main UI. |
| **Safety & control** | 8/10 | Auto-accept can be turned off; filters (min $, $/mi) editable; “I’m back” for manual trip end; tap failed → alert. Missing: no “confirm before accept” mode; no undo after accept. |
| **Driver-specific logic** | 7/10 | Min price, $/mile, hourly rate, pickup distance, passenger rating, surge, ride type, geofence, active hours. Dynamic rules (rush hour, idle, battery). **Bug:** stops logic rejects 0-stop (direct) trips – see below. |
| **Onboarding & setup** | 6/10 | GO blocked until a service is “linked”; PID alert at GO if missing; Dashboard URL + Accessibility explained in README. Missing: first-run tooltip or short in-app “Enable Accessibility + set PIDs” checklist. |
| **Filters & criteria UX** | 6/10 | Only min trip $ and min $/mile in Filters screen; other criteria (hourly, pickup, rating, surge, blocked types, hours) live in FilterConfig but no UI. Drivers can’t set these without code/defaults. |
| **History & audit** | 7/10 | History tab with date, app, price, latency, decision/reason. Good for “why did this get rejected?” Missing: filter by accept/reject; export. |
| **Multi-app flow** | 9/10 | Uber + Lyft side by side; conflict manager sends other app to background on accept; ride-completion poller brings other back; “I’m back” manual. Clear. |
| **Polish** | 8/10 | Resume scanning?, View logs, Dashboard connected indicator, error alert when daemon stops. Feels solid. |

**Overall: 7.5/10** – Strong core (reliability, multi-app, safety). Main gaps: **stops bug**, **filters UI** (expose more criteria), **earnings breakdown**, **lightweight onboarding**.

---

## 2. Critical Fix: Stops Logic

**Issue:** `CriteriaEngine` uses `if offer.stops != 1 { return .reject(reason: .tooManyStops) }`. That rejects **0-stop** (direct A→B) trips and only accepts exactly 1 stop. For drivers, “at most one waypoint” means accept **0 or 1** stops, reject **2+**.

**Fix:** Reject only when there are more than one stop:

```swift
if offer.stops > 1 { return .reject(reason: .tooManyStops) }
```

**Status:** Implemented in CriteriaEngine (reject when `stops > 1`). Unit test `testZeroStops_accepts` added.

---

## 3. High-Impact Improvements

### 3.1 Expose more filters in the Filters screen (driver-facing)

- **Current:** FiltersViewController only has Min trip ($) and Min $/mile.
- **Add (from FilterConfig):** Min hourly rate ($/hr), Max pickup distance (mi), Min passenger rating, Min surge (multiplier), Auto-accept / Auto-reject toggles, Active hours (start/end). Optional: blocked ride types (e.g. UberXL off).
- **Benefit:** Drivers can tune behavior without relying on defaults or code.

### 3.2 Earnings breakdown at a glance

- **Current:** One line: “Session: $X (Y/hr) · Today: $Z (N trips)”.
- **Add:** Second line or row: “Uber: $A · Lyft: $B” (EarningsTracker already has uberTotal/lyftTotal).
- **Benefit:** Drivers see which app is making money this session/today.

### 3.3 First-run / checklist

- **Current:** README and menu (Dashboard URL, Set PID, About). No in-app checklist.
- **Add:** Optional “Setup checklist” in menu or a small banner when Accessibility is off or PID missing: “To scan offers: 1) Enable Destro in Accessibility 2) Set driver app PIDs (Menu → Set driver app PID).”
- **Benefit:** Fewer “why isn’t it working?” moments.

### 3.4 “Why was this rejected?” in History

- **Current:** History shows decision and reason (e.g. `reject:below_min_price`).
- **Improve:** Make reason human-readable in the cell (e.g. “Rejected: below min price”) and/or add a short legend in the History header (e.g. “Reject reasons: below_min_price = below your min trip $”).
- **Benefit:** Drivers can tune filters from real rejections.

---

## 4. Medium / Nice-to-Have

- **Confirm before accept (optional mode):** FilterConfig or UI: “Require confirm before accept” – when on, daemon doesn’t tap accept; instead shows a notification or in-app “Accept $X? [Yes] [No].” Good for cautious drivers.
- **Daily goal in main UI:** EarningsTracker has `dailyGoalProgress()` and `dailyGoal`; show a thin progress bar or “Daily: $X / $Y” under today’s earnings.
- **Export history:** Menu → “Export history” → share CSV or JSON (date, app, price, decision, reason) for taxes or analysis.
- **Rush hour / dynamic note:** In Filters or status: “Rush hour: min $/mile is 10% higher (7–9a, 4–7p).” So drivers know why some offers are rejected.

---

## 5. Summary of Recommended Changes

| Priority | Item | Effort |
|----------|------|--------|
| **P0** | Fix stops: accept 0 or 1, reject 2+ | ✅ Done |
| **P1** | Filters UI: add min hourly, max pickup, rating, surge, auto-accept/reject, active hours | ✅ Done |
| **P1** | Earnings: show Uber vs Lyft breakdown on dashboard | ✅ Done |
| **P2** | Setup checklist or banner when Accessibility off / PID missing | ✅ Done |
| **P2** | History: human-readable reject reasons | ✅ Done |
| **P3** | Daily goal in main UI; export history; optional confirm-before-accept | ✅ All done |

---

*Document generated from a ride-share driver app expert perspective. P0–P3 implemented, including confirm-before-accept (Filters: "Require confirm before accept").*
