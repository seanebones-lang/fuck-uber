---
name: mystro-expert
description: Expert on Mystro (App Store rideshare automation for Uber/Lyft drivers). Use when building or reviewing apps that emulate Mystro, multi-apping, driver automation, Accessibility-based screen reading, or App Store–compliant app switching via URL schemes.
---

# Mystro Expert

Use this skill when working on Destro or any Mystro-like app: multi-app rideshare automation that must stay within Apple’s guidelines (no private APIs).

## What Mystro Is

- **App Store app** for Uber/Lyft (and delivery) drivers. Proves that full multi-app automation (cycle between apps, read offers, accept/reject) is possible with **public APIs only**.
- **Single UI for offers:** Drivers see Uber and Lyft offers **inside the app**, with accept/reject and filters. They do not sit in the Uber or Lyft app.
- **One toggle to go online:** Mystro brings both Uber and Lyft online; users are told to open Uber/Lyft **only from within Mystro** (↗️), not from the home screen.

## Technical Model (Public APIs Only)

1. **App switching**  
   No public API to switch by bundle ID. Use **URL schemes**:  
   - `com.ubercab.driver://` → Uber Driver to front  
   - `me.lyft.driver://` → Lyft Driver to front  
   - App’s own scheme (e.g. `destro://`, `mystro://`) → bring our app back to front

2. **Reading the screen**  
   **Accessibility** (user enables in Settings): read the **focused (frontmost)** app’s UI. So: open driver URL → that app is frontmost → read it. No private APIs, no background-app PID needed.

3. **Cycle (Mystro-style)**  
   - Open Uber URL → wait → read (offer or nil)  
   - Open Lyft URL → wait → read  
   - Open **our app’s URL** → user sees our UI and Offer card  
   Repeat. User stays in our app most of the time; brief flashes to Uber/Lyft while we check.

4. **Accept/Reject**  
   Switch to the correct driver app (URL), perform tap via Accessibility, then open our app’s URL again so the user returns.

## Destro Alignment Checklist

When reviewing or building Destro (or similar), verify:

- [ ] **Own URL scheme** in Info.plist (e.g. `destro://`) so we can bring our app back after reading each driver app.
- [ ] **Daemon cycle** uses driver URL when private “bring to foreground” fails; after each read (or after each full cycle) opens our app’s URL so the user sees our UI.
- [ ] **Confirm-accept path** uses same bring-to-foreground (AppSwitcher + URL fallback), then tap, then **open our app’s URL** so user returns.
- [ ] **Offer display** in our app (e.g. Offer card with price, miles, $/mi, decision); `destroOfferSeen`-style notification with full breakdown.
- [ ] **Accessibility** required and documented (Settings → Accessibility → [App]).
- [ ] Optional: **↗️ “Open Uber/Lyft Driver”** from our app (opens driver URL) so users go online through us, like Mystro. — **Done:** ServiceCard “Open (↗️)” when linked; alerts have “Open [Uber/Lyft] Driver (↗️)”; `openDriverApp(service:)` uses bundle ID scheme.

## Red Flags

- Telling the user to “stay on the driver app” defeats the purpose; we should cycle and show offers in our app.
- Using only private APIs (e.g. SpringBoard) for switching; on stock iOS they fail. Always have URL-scheme fallback.
- Opening `uber://` or `lyft://` (rider apps); use driver bundle IDs as schemes: `com.ubercab.driver://`, `me.lyft.driver://`.

## Reference

- Project doc: [MYSTRO_HOW_IT_WORKS.md](../../../MYSTRO_HOW_IT_WORKS.md) (repo root)
- Mystro iOS manual: mystrodriver.com/iosmanual.html (open Uber/Lyft from Mystro only; go online via one toggle; offers show in Mystro)
