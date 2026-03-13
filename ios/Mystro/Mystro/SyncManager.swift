import Foundation

// MARK: - SyncManager
// Sync FilterConfig and GeofenceManager zones via NSUbiquitousKeyValueStore (iCloud).
// Export/import settings as JSON for manual backup.

final class SyncManager {

  static let shared = SyncManager()
  private let store = NSUbiquitousKeyValueStore.default

  private init() {
    NotificationCenter.default.addObserver(self, selector: #selector(ubiquitousStoreDidChange), name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store)
  }

  /// Syncs Uber profile and geofence zones to iCloud. Called when user saves filters.
  func syncToCloud() {
    let svc = "uber"
    store.set(FilterConfig.minPrice(service: svc), forKey: "destro.sync.minPrice")
    store.set(FilterConfig.minPricePerMile(service: svc), forKey: "destro.sync.minPricePerMile")
    store.set(FilterConfig.minHourlyRate(service: svc), forKey: "destro.sync.minHourlyRate")
    store.set(FilterConfig.maxPickupDistance(service: svc), forKey: "destro.sync.maxPickupDistance")
    if let data = try? JSONEncoder().encode(FilterConfig.geofenceZones) {
      store.set(data, forKey: "destro.sync.geofenceZones")
    }
    store.synchronize()
  }

  /// Pulls Uber profile and geofence from iCloud. Called on launch.
  func pullFromCloud() {
    let svc = "uber"
    if store.double(forKey: "destro.sync.minPrice") > 0 {
      FilterConfig.setMinPrice(store.double(forKey: "destro.sync.minPrice"), service: svc)
    }
    if store.double(forKey: "destro.sync.minPricePerMile") > 0 {
      FilterConfig.setMinPricePerMile(store.double(forKey: "destro.sync.minPricePerMile"), service: svc)
    }
    if store.double(forKey: "destro.sync.minHourlyRate") > 0 {
      FilterConfig.setMinHourlyRate(store.double(forKey: "destro.sync.minHourlyRate"), service: svc)
    }
    if store.double(forKey: "destro.sync.maxPickupDistance") > 0 {
      FilterConfig.setMaxPickupDistance(store.double(forKey: "destro.sync.maxPickupDistance"), service: svc)
    }
    if let data = store.data(forKey: "destro.sync.geofenceZones") {
      do {
        let zones = try JSONDecoder().decode([GeofenceZone].self, from: data)
        FilterConfig.geofenceZones = zones
      } catch {
        print("[Destro] SyncManager pullFromCloud geofenceZones decode failed: \(error.localizedDescription)")
      }
    }
  }

  @objc private func ubiquitousStoreDidChange(_ n: Notification) {
    DispatchQueue.main.async { SyncManager.shared.pullFromCloud() }
  }

  /// Export settings as JSON dictionary for backup (Uber profile + geofence).
  func exportSettings() -> [String: Any] {
    let svc = "uber"
    return [
      "minPrice": FilterConfig.minPrice(service: svc),
      "minPricePerMile": FilterConfig.minPricePerMile(service: svc),
      "minHourlyRate": FilterConfig.minHourlyRate(service: svc),
      "maxPickupDistance": FilterConfig.maxPickupDistance(service: svc),
      "geofenceZones": (try? JSONEncoder().encode(FilterConfig.geofenceZones)).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? []
    ]
  }

  /// Import from exported dictionary into Uber profile.
  func importSettings(_ dict: [String: Any]) {
    let svc = "uber"
    if let v = dict["minPrice"] as? Double, v > 0 { FilterConfig.setMinPrice(v, service: svc) }
    if let v = dict["minPricePerMile"] as? Double, v > 0 { FilterConfig.setMinPricePerMile(v, service: svc) }
    if let v = dict["minHourlyRate"] as? Double, v > 0 { FilterConfig.setMinHourlyRate(v, service: svc) }
    if let v = dict["maxPickupDistance"] as? Double, v > 0 { FilterConfig.setMaxPickupDistance(v, service: svc) }
    if let arr = dict["geofenceZones"] as? [[String: Any]],
       let data = try? JSONSerialization.data(withJSONObject: arr),
       let zones = try? JSONDecoder().decode([GeofenceZone].self, from: data) {
      FilterConfig.geofenceZones = zones
    }
  }
}
