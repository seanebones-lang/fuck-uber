# Mystro Parity Gaps — Ranked

Gaps between Destro and Mystro-style Uber/Lyft auto-accept/auto-reject, ranked **Blocker** / **High** / **Medium**. Used to drive the parity closure plan.

---

## Blocker

| Gap | Description | Location |
|-----|-------------|----------|
| **Parser–criteria mismatch** | CriteriaEngine uses `passengerRating`, `surgeMultiplier`, `rideType`, `pickupLocation`, `pickupDistanceMiles`, `estimatedHourlyRate` but AccessibilityOfferSource and VisionOfferSource only populate price, miles, shared, stops, acceptPoint, rejectPoint. Filters for rating/surge/ride type/geofence/pickup never fire at runtime. | AccessibilityOfferSource.swift, VisionOfferSource.swift, CriteriaEngine.swift |
| **Single global filter set** | One FilterConfig for both Uber and Lyft. Users cannot have different min $/mile or blocked types per app. | FilterConfig.swift, FiltersViewController, CriteriaEngine |
| **No manual accept/reject when auto off** | When auto-accept is disabled, user sees the offer in the Offer card but has no in-app button to Accept or Reject the current offer; they must switch to the driver app. | DashboardViewController.swift |

---

## High

| Gap | Description | Location |
|-----|-------------|----------|
| **Reject when rejectPoint is nil** | Auto-reject only runs if parser provides `rejectPoint`. If AX/OCR miss the Decline button, reject is skipped and offer is left on screen. | ProdDaemon.swift, AccessibilityOfferSource.swift |
| **No driver app availability check** | openDriverApp(service:) opens URL without checking `canOpenURL`. User gets no feedback if Uber/Lyft Driver is not installed. | DashboardViewController.swift |
| **ConflictManager private-only** | rideAccepted/rideCompleted use AppSwitcher (FrontBoard) only. On stock iOS, sendToBackground/bringToForeground no-op; no URL-scheme fallback. | ConflictManager.swift, ProdDaemon.swift |
| **RidePredictor unused** | ~~RidePredictor exists but is never called~~ **Done:** Optional minRideQualityScore filter; CriteriaEngine calls RidePredictor when threshold > 0. | RidePredictor.swift, CriteriaEngine, FilterConfig |
| **SyncManager not invoked** | ~~syncToCloud/pullFromCloud not called~~ **Done:** pullFromCloud on launch; syncToCloud when filters saved; SyncManager uses Uber profile. | SyncManager.swift, AppDelegate, FiltersViewController |

---

## Medium

| Gap | Description | Location |
|-----|-------------|----------|
| **Destination / trip time not in criteria** | OfferData has dropoffLocation and estimatedMinutes; no rule uses them (e.g. max trip time, destination zone). | CriteriaEngine.swift, DaemonTypes.swift |
| **Vision OCR on stock iOS** | VisionOfferSource uses UIGetScreenImage when no provider is set; that API is private and fails on stock iOS. OCR path only works with injected capture or jailbreak. | VisionOfferSource.swift |
| **Dashboard stats not persisted** | Server keeps accepts/rejects/earnings in memory; restart loses history. | dashboard/server.js |
| **Per-service filters in UI only** | "Uber Filters" / "Lyft Filters" open same FilterConfig; service name is cosmetic. | FiltersViewController, FilterConfig |

---

## Summary

- **Blocker (3):** Parser–criteria alignment, per-service filters, manual accept/reject in app.
- **High (5):** Reject fallback, app availability check, ConflictManager URL fallback, wire RidePredictor, wire SyncManager.
- **Medium (4):** Destination/trip-time criteria, Vision stock-iOS path, dashboard persistence, per-service filter backend.

Implementation order follows the plan: Priority 0 (core parity) → Priority 1 (reliability) → Priority 2 (completeness) → Validation.
