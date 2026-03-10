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

  func syncToCloud() {
    store.set(FilterConfig.minPrice, forKey: "destro.sync.minPrice")
    store.set(FilterConfig.minPricePerMile, forKey: "destro.sync.minPricePerMile")
    store.set(FilterConfig.minHourlyRate, forKey: "destro.sync.minHourlyRate")
    store.set(FilterConfig.maxPickupDistance, forKey: "destro.sync.maxPickupDistance")
    if let data = try? JSONEncoder().encode(FilterConfig.geofenceZones) {
      store.set(data, forKey: "destro.sync.geofenceZones")
    }
    store.synchronize()
  }

  func pullFromCloud() {
    if store.double(forKey: "destro.sync.minPrice") > 0 {
      FilterConfig.minPrice = store.double(forKey: "destro.sync.minPrice")
    }
    if store.double(forKey: "destro.sync.minPricePerMile") > 0 {
      FilterConfig.minPricePerMile = store.double(forKey: "destro.sync.minPricePerMile")
    }
    if store.double(forKey: "destro.sync.minHourlyRate") > 0 {
      FilterConfig.minHourlyRate = store.double(forKey: "destro.sync.minHourlyRate")
    }
    if store.double(forKey: "destro.sync.maxPickupDistance") > 0 {
      FilterConfig.maxPickupDistance = store.double(forKey: "destro.sync.maxPickupDistance")
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

  /// Export settings as JSON dictionary for backup.
  func exportSettings() -> [String: Any] {
    [
      "minPrice": FilterConfig.minPrice,
      "minPricePerMile": FilterConfig.minPricePerMile,
      "minHourlyRate": FilterConfig.minHourlyRate,
      "maxPickupDistance": FilterConfig.maxPickupDistance,
      "geofenceZones": (try? JSONEncoder().encode(FilterConfig.geofenceZones)).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? []
    ]
  }

  /// Import from exported dictionary.
  func importSettings(_ dict: [String: Any]) {
    if let v = dict["minPrice"] as? Double, v > 0 { FilterConfig.minPrice = v }
    if let v = dict["minPricePerMile"] as? Double, v > 0 { FilterConfig.minPricePerMile = v }
    if let v = dict["minHourlyRate"] as? Double, v > 0 { FilterConfig.minHourlyRate = v }
    if let v = dict["maxPickupDistance"] as? Double, v > 0 { FilterConfig.maxPickupDistance = v }
    if let arr = dict["geofenceZones"] as? [[String: Any]],
       let data = try? JSONSerialization.data(withJSONObject: arr),
       let zones = try? JSONDecoder().decode([GeofenceZone].self, from: data) {
      FilterConfig.geofenceZones = zones
    }
  }
}
