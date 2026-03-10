# How Mystro Works (and why Destro should match it)

Mystro is on the App Store and uses only **public APIs** (Accessibility + URL schemes). This doc summarizes how it works so Destro can do the same.

---

## What Mystro does

- **Single place for offers:** You see Uber and Lyft offers **inside Mystro**, with accept/reject buttons. You don’t have to sit in the Uber or Lyft app.
- **Go online through Mystro:** One toggle in Mystro brings **both** Uber and Lyft online. You don’t open the driver apps from the home screen first.
- **Open Uber/Lyft from Mystro only:** Mystro tells you to use the ↗️ icon **inside Mystro** to open Uber or Lyft, not the home screen or app switcher. If you open from the home screen, “it may not recognize that it’s online.”
- **Screen reading:** Mystro uses **Accessibility** (“Enable Screen Reading”, “Mystro Accessibility Service”) to read the driver app screens and show offers in Mystro.

---

## How it works technically (public APIs)

1. **Bringing an app to the front**  
   There is no public API to “switch to app by bundle ID.” The public way is **URL schemes**.  
   - Open `com.ubercab.driver://` → Uber Driver comes to the front.  
   - Open `me.lyft.driver://` → Lyft Driver comes to the front.  
   So Mystro (and Destro) **open the driver app via its URL** when they need to read that app.

2. **Reading the screen**  
   With **Accessibility** permission, the app can use the **focused (frontmost) application** and read its UI. So:  
   - Open Uber URL → Uber is frontmost → read Uber’s screen (offer or not).  
   - Open Lyft URL → Lyft is frontmost → read Lyft’s screen.  
   - No private APIs; no need to know PIDs of background apps.

3. **Showing offers in Mystro (not in the driver app)**  
   So the device must return to **Mystro** so the user sees the offer there. That implies:  
   - Mystro registers a **URL scheme** (e.g. `mystro://`).  
   - Cycle: open Uber URL → read → open Lyft URL → read → **open Mystro URL** → Mystro is frontmost again, show offer in Mystro’s UI.  
   So the user stays in Mystro most of the time and sees brief switches to Uber/Lyft while Mystro “checks,” then sees the offer and accept/reject in Mystro.

4. **Accept/Reject**  
   When the user taps Accept in Mystro, Mystro must trigger the accept in the correct driver app: switch to that app (open its URL), use Accessibility to tap the Accept button, then can open Mystro URL again to come back.

---

## What Destro needs to match this

| Mystro behavior              | Destro implementation |
|-----------------------------|------------------------|
| Open Uber/Lyft from app (↗️) | Open driver app via URL from Destro (e.g. Link or “Open Uber Driver”). |
| Go online via one toggle    | Tap GO in Destro; daemon opens each driver app via URL and reads (we already start this). |
| Offers shown in our app     | After reading each driver app, **open Destro’s URL** so we’re frontmost and show the offer in the Offer card. |
| Cycle Uber ↔ Lyft           | Open Uber URL → read → Open Lyft URL → read → Open **Destro URL** → repeat. |
| Accept/Reject in our app    | When user accepts, open that driver app URL, tap via Accessibility, then open Destro URL again. |

**Implementation notes**

- **Confirm-before-accept:** When the user taps Accept on the confirm dialog, Destro uses the same bring-to-foreground (AppSwitcher + URL fallback), performs the tap, then opens `destro://` so the user returns to Destro.
- **Open driver apps from Destro (↗️):** Mystro tells users to open Uber/Lyft only via the in-app ↗️ icon. Destro currently uses Link to mark a service linked and instructs the user to open the driver app from the home screen. Adding an explicit “Open Uber Driver” / “Open Lyft Driver” button that opens `com.ubercab.driver://` and `me.lyft.driver://` would match Mystro’s UX (and avoid opening the rider app); the daemon already uses these URLs when cycling.

So we need:

1. **Destro URL scheme** (e.g. `destro://`) in Info.plist so we can open ourselves and bring Destro back to the front after reading Uber/Lyft.
2. **Daemon cycle** that, when the private “bring to foreground” API isn’t available, does:  
   - open driver app URL → wait → read → then **open Destro URL** so the user sees Destro and the Offer card.
3. **Open driver apps from Destro** (↗️): Optional UX improvement — add an “Open Uber Driver” / “Open Lyft Driver” button that opens the driver URL so users go online through us (daemon already uses these URLs when cycling).

This stays within Apple’s guidelines: URL schemes and Accessibility only, same as Mystro.
