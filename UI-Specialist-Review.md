# UI Specialist Review

Workspace: fuck-uber (Destro/Mystro iOS app + web dashboard).  
Review covers user-facing UI only; changes are described so a developer can implement without code in the report.

---

## iOS (Destro/Mystro)

### Current state (summary)

The main experience lives in **DashboardViewController.swift**: dark theme (background ~0.06, cards ~0.12, orange accent), scrollable stack with relay/dashboard status, rush hour, Offer card, setup banner, "Enabled" section (earnings, daily goal, conflict, I'm back), Uber/Lyft **ServiceCard**s (toggle, Filters, Link/Unlink/Open, Set PID, Auto-accept/reject), "Unlinked" (DiDi, DoorDash), and a fixed bottom bar (Drive | status + GO | History). **FiltersViewController** and **HistoryViewController** are in the same file: filters are a long single-column form; History uses a segmented control and a "Decisions" table. Typography is mostly system fonts (12–24 pt) with semibold section headers; status and secondary text use `textSecondary` (0.65 white). GO has a VoiceOver label; some controls (e.g. service card buttons, Filters fields) lack explicit accessibility or hierarchy cues. Overall it's functional but dense, and the purpose of GO when offline or when nothing is linked is not obvious at a glance.

### Proposed iterations

1. **GO button context when offline**  
   **File:** `DashboardViewController.swift`  
   When `isOnline == false`, add a short contextual label near or under the GO button (e.g. "Tap after linking a service" or "Link Uber or Lyft, then tap GO"). Alternatively set a more descriptive `accessibilityHint` on `goButton` when offline so VoiceOver explains the next step. Keeps the existing "Link a service first" alert but makes the primary action clearer before tap.

2. **Status line contrast and weight**  
   **File:** `DashboardViewController.swift`  
   Increase status line prominence: set `statusLabel.font` to `.systemFont(ofSize: 15, weight: .medium)` (or 14 pt medium) so "You're online" / "You're offline" is easier to scan. Ensure `statusLabel.textColor` stays `DestroUI.accentOrange` when online and consider slightly brighter `textSecondary` when offline if contrast is low on device.

3. **Section headers for Enabled vs Unlinked**  
   **File:** `DashboardViewController.swift`  
   Add clear section headers (or spacing) so "Enabled" and "Unlinked" read as two distinct groups. For example: add a small spacing view or a short divider after the last Enabled card (Lyft) and before the "Unlinked" row, and optionally give "Unlinked" a slightly different treatment (e.g. smaller top margin or a short subtitle like "Tap to link") so the two sections are visually separated.

4. **Accessibility on service cards and key buttons**  
   **File:** `DashboardViewController.swift` (ServiceCard, UnlinkedServiceCard)  
   Add `accessibilityLabel` (and `accessibilityHint` where helpful) on: `goButton` (already present; ensure hint when offline), Filters button ("Filters for [Uber/Lyft]"), Link/Unlink/Open buttons ("Link Uber Driver", "Unlink", "Open Uber Driver app"), and the UnlinkedServiceCard (e.g. "DiDi, tap to link"). In ServiceCard, give the status line (`statusLabel`) an `accessibilityLabel` that combines service name and status (e.g. "Uber, Destro is offline, Not linked") so VoiceOver users get one clear phrase.

5. **Filters screen structure**  
   **File:** `DashboardViewController.swift` (FiltersViewController)  
   Group the long form into clearly labeled sections (e.g. "Pricing", "Ride types", "Schedule", "Geofence") using section headers or grouped rows so drivers can scan and edit by category. Consider collapsible sections or a short table-of-contents at the top if the list stays long.

6. **History empty state and section title**  
   **File:** `DashboardViewController.swift` (HistoryViewController)  
   Keep the existing "No decisions yet…" / "No accepted rides…" text; ensure the empty cell is clearly styled (e.g. centered, secondary color) and that the "Decisions" section header is visible. Optionally add a one-line subtitle under the segment control (e.g. "Accept and reject history") so first-time users understand the screen.

---

## Dashboard (web)

### Current state (summary)

**dashboard/client/src/App.js** is the only UI: a single React component with an h1 "Destro Dashboard", WebSocket to `ws://localhost:3000`, and inline styles only (no separate CSS file). It shows: connection error text (red) when WS fails; two lines of stats (Accepts | Rejects | Uptime; Conflict | Session | Today); a "Last event" line in small gray (12px, #888); and either a Recharts `LineChart` (600×300, accepts/rejects over time) or "No data yet. Connect the app and go online to see the chart." There is no explicit connection status indicator when connected, no dark theme to match the app, and the chart has a fixed size. Readability and hierarchy are adequate but flat; empty and error states could be clearer and more consistent with the app.

### Proposed iterations

1. **Connection status indicator**  
   **File:** `dashboard/client/src/App.js`  
   Add a visible connection status (e.g. "Connected" / "Disconnected") with an icon or color dot next to the title or above the stats. Derive state from WebSocket open/close/error (e.g. `wsConnected` boolean) and style connected as green, disconnected as gray or red so users immediately see whether the dashboard is live.

2. **Chart labels and responsiveness**  
   **File:** `dashboard/client/src/App.js`  
   Give the chart explicit axis labels (e.g. X: "Time", Y: "Count" or "Accepts / Rejects") and ensure the chart container is responsive: e.g. `width: 100%`, `maxWidth: 600`, min height ~300 so it scales on smaller windows and doesn't overflow. Keep or adjust Recharts `ResponsiveContainer` if used, or wrap in a div with the above constraints.

3. **Last-event line for scannability**  
   **File:** `dashboard/client/src/App.js`  
   Style the last-event line for quick scanning: e.g. slightly larger font (14px), higher contrast color (e.g. #aaa or a theme primary), and a clear label "Last event:" before the type/app/reason. Optionally show time and format the line in a small card or bordered block so it reads as a single "latest activity" unit.

4. **Empty state and "no data" message**  
   **File:** `dashboard/client/src/App.js`  
   When `statsHistory.length === 0`, show an explicit empty state: e.g. a short message like "No data yet — connect the app and go online to see the chart" with subdued styling, and ensure it's announced or visible so users don't assume the chart is broken. Align wording with the connection indicator (e.g. "Disconnected" vs "Connected, no events yet").

5. **Global styles / dark theme (optional)**  
   **File:** `dashboard/client/src/App.js` (and optionally new `App.css` or `index.css`)  
   Introduce a minimal set of layout and theme variables (e.g. background, card, text, accent) and apply a dark theme to match the iOS app (dark background, light text, orange accent for key metrics or links). Use a wrapper class or CSS variables so the dashboard feels consistent with the app; keep the existing inline styles as fallback or replace with class-based styles.

---

## Recommended first change

**iOS:** **GO button context when offline** — add a short label or `accessibilityHint` so users understand they must link a service before GO is useful. Highest impact for first-time and accessibility users with minimal layout risk.

**Dashboard:** **Connection status indicator** — add a clear "Connected" / "Disconnected" (with icon or color) so users can immediately tell if the dashboard is receiving data. Reduces confusion when the chart is empty or the URL is wrong.

---

*Report generated from codebase review and MCP agent suggestions. No code written; implement per descriptions above.*
