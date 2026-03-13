import Foundation
import CoreLocation

// MARK: - GeofenceZone (for FilterConfig persistence; GeofenceManager in Phase 5)

struct GeofenceZone: Codable, Equatable {
  var latitude: Double
  var longitude: Double
  var radiusMeters: Double
  var isAcceptZone: Bool
  var name: String

  var coordinate: CLLocationCoordinate2D {
    get { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    set { latitude = newValue.latitude; longitude = newValue.longitude }
  }
}

// MARK: - FilterConfig
// Persisted criteria for auto-accept. Used by ProdDaemon and Filters UI.

struct FilterConfig {
  /// Service id from bundle id (e.g. "com.ubercab.driver" -> "uber").
  static func service(from bundleId: String) -> String {
    bundleId.contains("uber") ? "uber" : "lyft"
  }

  private static func key(_ name: String, service: String) -> String { "destro.filter.\(service).\(name)" }
  private static let keyMinPrice = "destro.filter.minPrice"
  private static let keyMinPerMile = "destro.filter.minPerMile"
  private static let keyAutoAccept = "destro.filter.autoAccept"
  private static let keyRequireConfirmBeforeAccept = "destro.filter.requireConfirmBeforeAccept"
  private static let keyAutoReject = "destro.filter.autoReject"
  private static let keyMinHourlyRate = "destro.filter.minHourlyRate"
  private static let keyMaxPickupDistance = "destro.filter.maxPickupDistance"
  private static let keyMinPassengerRating = "destro.filter.minPassengerRating"
  private static let keyMinSurgeMultiplier = "destro.filter.minSurgeMultiplier"
  private static let keyBlockedRideTypes = "destro.filter.blockedRideTypes"
  private static let keyActiveHoursStart = "destro.filter.activeHoursStart"
  private static let keyActiveHoursEnd = "destro.filter.activeHoursEnd"
  private static let keyGeofenceZones = "destro.filter.geofenceZones"

  static func minPrice(service: String) -> Double {
    let k = key("minPrice", service: service)
    var v = UserDefaults.standard.double(forKey: k)
    if v <= 0 { v = UserDefaults.standard.double(forKey: keyMinPrice); if v <= 0 { v = 7.0 }; UserDefaults.standard.set(v, forKey: k) }
    return v > 0 ? v : 7.0
  }
  static func setMinPrice(_ value: Double, service: String) { UserDefaults.standard.set(max(0, value), forKey: key("minPrice", service: service)) }

  static func minPricePerMile(service: String) -> Double {
    let k = key("minPerMile", service: service)
    var v = UserDefaults.standard.double(forKey: k)
    if v <= 0 { v = UserDefaults.standard.double(forKey: keyMinPerMile); if v <= 0 { v = 0.90 }; UserDefaults.standard.set(v, forKey: k) }
    return v > 0 ? v : 0.90
  }
  static func setMinPricePerMile(_ value: Double, service: String) { UserDefaults.standard.set(max(0, value), forKey: key("minPerMile", service: service)) }

  static func autoAccept(service: String) -> Bool {
    let k = key("autoAccept", service: service)
    if UserDefaults.standard.object(forKey: k) == nil {
      let legacy = UserDefaults.standard.object(forKey: keyAutoAccept) as? Bool ?? true
      UserDefaults.standard.set(legacy, forKey: k)
      return legacy
    }
    return UserDefaults.standard.object(forKey: k) as? Bool ?? true
  }
  static func setAutoAccept(_ value: Bool, service: String) { UserDefaults.standard.set(value, forKey: key("autoAccept", service: service)) }

  static func requireConfirmBeforeAccept(service: String) -> Bool {
    let k = key("requireConfirmBeforeAccept", service: service)
    if UserDefaults.standard.object(forKey: k) == nil {
      let legacy = (UserDefaults.standard.object(forKey: keyRequireConfirmBeforeAccept) as? Bool) ?? true
      UserDefaults.standard.set(legacy, forKey: k)
      return legacy
    }
    return (UserDefaults.standard.object(forKey: k) as? Bool) ?? true
  }
  static func setRequireConfirmBeforeAccept(_ value: Bool, service: String) { UserDefaults.standard.set(value, forKey: key("requireConfirmBeforeAccept", service: service)) }

  static func autoReject(service: String) -> Bool {
    let k = key("autoReject", service: service)
    if UserDefaults.standard.object(forKey: k) == nil {
      let legacy = UserDefaults.standard.bool(forKey: keyAutoReject)
      UserDefaults.standard.set(legacy, forKey: k)
      return legacy
    }
    return UserDefaults.standard.bool(forKey: k)
  }
  static func setAutoReject(_ value: Bool, service: String) { UserDefaults.standard.set(value, forKey: key("autoReject", service: service)) }

  static func minHourlyRate(service: String) -> Double {
    let k = key("minHourlyRate", service: service)
    var v = UserDefaults.standard.double(forKey: k)
    if v <= 0 { v = UserDefaults.standard.double(forKey: keyMinHourlyRate); if v <= 0 { v = 30.0 }; UserDefaults.standard.set(v, forKey: k) }
    return v > 0 ? v : 30.0
  }
  static func setMinHourlyRate(_ value: Double, service: String) { UserDefaults.standard.set(value, forKey: key("minHourlyRate", service: service)) }

  static func maxPickupDistance(service: String) -> Double {
    let k = key("maxPickupDistance", service: service)
    var v = UserDefaults.standard.double(forKey: k)
    if v <= 0 { v = UserDefaults.standard.double(forKey: keyMaxPickupDistance); if v <= 0 { v = 10.0 }; UserDefaults.standard.set(v, forKey: k) }
    return v > 0 ? v : 10.0
  }
  static func setMaxPickupDistance(_ value: Double, service: String) { UserDefaults.standard.set(max(0, value), forKey: key("maxPickupDistance", service: service)) }

  static func minPassengerRating(service: String) -> Double {
    let k = key("minPassengerRating", service: service)
    var v = UserDefaults.standard.double(forKey: k)
    if v <= 0 { v = UserDefaults.standard.double(forKey: keyMinPassengerRating); if v <= 0 { v = 4.0 }; UserDefaults.standard.set(v, forKey: k) }
    return v > 0 ? v : 4.0
  }
  static func setMinPassengerRating(_ value: Double, service: String) { UserDefaults.standard.set(value, forKey: key("minPassengerRating", service: service)) }

  static func minSurgeMultiplier(service: String) -> Double {
    let k = key("minSurgeMultiplier", service: service)
    var v = UserDefaults.standard.double(forKey: k)
    if v < 0 { v = UserDefaults.standard.object(forKey: keyMinSurgeMultiplier) != nil ? UserDefaults.standard.double(forKey: keyMinSurgeMultiplier) : 1.0; UserDefaults.standard.set(v, forKey: k) }
    return v >= 0 ? v : 1.0
  }
  static func setMinSurgeMultiplier(_ value: Double, service: String) { UserDefaults.standard.set(value, forKey: key("minSurgeMultiplier", service: service)) }

  static func blockedRideTypes(service: String) -> [RideType] {
    let k = key("blockedRideTypes", service: service)
    guard UserDefaults.standard.data(forKey: k) != nil else {
      let legacy: [RideType] = {
        guard let data = UserDefaults.standard.data(forKey: keyBlockedRideTypes),
              let raw = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return raw.compactMap { RideType(rawValue: $0) }
      }()
      if let data = try? JSONEncoder().encode(legacy.map(\.rawValue)) { UserDefaults.standard.set(data, forKey: k) }
      return legacy
    }
    guard let data = UserDefaults.standard.data(forKey: k), let raw = try? JSONDecoder().decode([String].self, from: data) else { return [] }
    return raw.compactMap { RideType(rawValue: $0) }
  }
  static func setBlockedRideTypes(_ value: [RideType], service: String) {
    let raw = value.map(\.rawValue)
    if let data = try? JSONEncoder().encode(raw) { UserDefaults.standard.set(data, forKey: key("blockedRideTypes", service: service)) }
  }

  static func activeHoursStart(service: String) -> Int {
    let k = key("activeHoursStart", service: service)
    if UserDefaults.standard.object(forKey: k) == nil {
      let legacy = UserDefaults.standard.object(forKey: keyActiveHoursStart) != nil ? UserDefaults.standard.integer(forKey: keyActiveHoursStart) : 0
      let v = (0...23).contains(legacy) ? legacy : 0
      UserDefaults.standard.set(v, forKey: k)
      return v
    }
    let v = UserDefaults.standard.integer(forKey: k)
    return (0...23).contains(v) ? v : 0
  }
  static func setActiveHoursStart(_ value: Int, service: String) { UserDefaults.standard.set(max(0, min(23, value)), forKey: key("activeHoursStart", service: service)) }

  static func activeHoursEnd(service: String) -> Int {
    let k = key("activeHoursEnd", service: service)
    if UserDefaults.standard.object(forKey: k) == nil {
      let legacy = UserDefaults.standard.object(forKey: keyActiveHoursEnd) != nil ? UserDefaults.standard.integer(forKey: keyActiveHoursEnd) : 23
      let v = (0...23).contains(legacy) ? legacy : 23
      UserDefaults.standard.set(v, forKey: k)
      return v
    }
    let v = UserDefaults.standard.integer(forKey: k)
    return (0...23).contains(v) ? v : 23
  }
  static func setActiveHoursEnd(_ value: Int, service: String) { UserDefaults.standard.set(max(0, min(23, value)), forKey: key("activeHoursEnd", service: service)) }

  /// Optional RidePredictor quality score threshold (0–1). When > 0, offers with score below this are rejected. Default 0 (disabled).
  static func minRideQualityScore(service: String) -> Double {
    let k = key("minRideQualityScore", service: service)
    let v = UserDefaults.standard.double(forKey: k)
    return v >= 0 && v <= 1 ? v : 0
  }
  static func setMinRideQualityScore(_ value: Double, service: String) { UserDefaults.standard.set(max(0, min(1, value)), forKey: key("minRideQualityScore", service: service)) }

  static var minPrice: Double {
    get {
      let v = UserDefaults.standard.double(forKey: keyMinPrice)
      return v > 0 ? v : 7.0
    }
    set { UserDefaults.standard.set(max(0, newValue), forKey: keyMinPrice) }
  }

  static var minPricePerMile: Double {
    get {
      let v = UserDefaults.standard.double(forKey: keyMinPerMile)
      return v > 0 ? v : 0.90
    }
    set { UserDefaults.standard.set(max(0, newValue), forKey: keyMinPerMile) }
  }

  static var autoAccept: Bool {
    get { UserDefaults.standard.object(forKey: keyAutoAccept) as? Bool ?? true }
    set { UserDefaults.standard.set(newValue, forKey: keyAutoAccept) }
  }

  /// When true, matching offers are not auto-tapped; user sees "Accept $X? [Accept] [Decline]". Default true for new installs (Mystro-style safety).
  static var requireConfirmBeforeAccept: Bool {
    get { (UserDefaults.standard.object(forKey: keyRequireConfirmBeforeAccept) as? Bool) ?? true }
    set { UserDefaults.standard.set(newValue, forKey: keyRequireConfirmBeforeAccept) }
  }

  static var autoReject: Bool {
    get { UserDefaults.standard.bool(forKey: keyAutoReject) }
    set { UserDefaults.standard.set(newValue, forKey: keyAutoReject) }
  }

  static var minHourlyRate: Double {
    get {
      let v = UserDefaults.standard.double(forKey: keyMinHourlyRate)
      return v > 0 ? v : 30.0
    }
    set { UserDefaults.standard.set(newValue, forKey: keyMinHourlyRate) }
  }

  static var maxPickupDistance: Double {
    get {
      let v = UserDefaults.standard.double(forKey: keyMaxPickupDistance)
      return v > 0 ? v : 10.0
    }
    set { UserDefaults.standard.set(newValue, forKey: keyMaxPickupDistance) }
  }

  static var minPassengerRating: Double {
    get {
      let v = UserDefaults.standard.double(forKey: keyMinPassengerRating)
      return v > 0 ? v : 4.0
    }
    set { UserDefaults.standard.set(newValue, forKey: keyMinPassengerRating) }
  }

  static var minSurgeMultiplier: Double {
    get {
      let v = UserDefaults.standard.double(forKey: keyMinSurgeMultiplier)
      return v >= 0 ? v : 1.0
    }
    set { UserDefaults.standard.set(newValue, forKey: keyMinSurgeMultiplier) }
  }

  static var blockedRideTypes: [RideType] {
    get {
      guard let data = UserDefaults.standard.data(forKey: keyBlockedRideTypes),
            let raw = try? JSONDecoder().decode([String].self, from: data) else { return [] }
      return raw.compactMap { RideType(rawValue: $0) }
    }
    set {
      let raw = newValue.map(\.rawValue)
      do {
        let data = try JSONEncoder().encode(raw)
        UserDefaults.standard.set(data, forKey: keyBlockedRideTypes)
      } catch {
        print("[Destro] failed to save blocked ride types: \(error)")
      }
    }
  }

  static var activeHoursStart: Int {
    get {
      guard UserDefaults.standard.object(forKey: keyActiveHoursStart) != nil else { return 0 }
      let v = UserDefaults.standard.integer(forKey: keyActiveHoursStart)
      return v >= 0 && v <= 23 ? v : 0
    }
    set { UserDefaults.standard.set(max(0, min(23, newValue)), forKey: keyActiveHoursStart) }
  }

  static var activeHoursEnd: Int {
    get {
      guard UserDefaults.standard.object(forKey: keyActiveHoursEnd) != nil else { return 23 }
      let v = UserDefaults.standard.integer(forKey: keyActiveHoursEnd)
      return v >= 0 && v <= 23 ? v : 23
    }
    set { UserDefaults.standard.set(max(0, min(23, newValue)), forKey: keyActiveHoursEnd) }
  }

  static var geofenceZones: [GeofenceZone] {
    get {
      guard let data = UserDefaults.standard.data(forKey: keyGeofenceZones),
            let list = try? JSONDecoder().decode([GeofenceZone].self, from: data) else { return [] }
      return list
    }
    set {
      do {
        let data = try JSONEncoder().encode(newValue)
        UserDefaults.standard.set(data, forKey: keyGeofenceZones)
      } catch {
        print("[Destro] failed to save geofence zones: \(error)")
      }
    }
  }
}

// MARK: - HistoryEntry

struct HistoryEntry: Codable {
  let id: String
  let date: Date
  let app: String
  let price: Double
  let latencyMs: Int
  /// Present when we record a decision (accept or reject) with reason.
  let decision: String?
  let reason: String?

  enum CodingKeys: String, CodingKey {
    case id, date, app, price, latencyMs, decision, reason
  }

  init(id: String, date: Date, app: String, price: Double, latencyMs: Int, decision: String? = nil, reason: String? = nil) {
    self.id = id
    self.date = date
    self.app = app
    self.price = price
    self.latencyMs = latencyMs
    self.decision = decision
    self.reason = reason
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    date = try c.decode(Date.self, forKey: .date)
    app = try c.decode(String.self, forKey: .app)
    price = try c.decode(Double.self, forKey: .price)
    latencyMs = try c.decode(Int.self, forKey: .latencyMs)
    decision = try c.decodeIfPresent(String.self, forKey: .decision)
    reason = try c.decodeIfPresent(String.self, forKey: .reason)
  }
}

// MARK: - HistoryStore

enum HistoryStore {
  private static let key = "destro.history.entries"
  private static let maxEntries = 200

  static func append(app: String, price: Double, latencyMs: Int) {
    append(app: app, price: price, latencyMs: latencyMs, decision: .accept(reason: .meetsCriteria))
  }

  static func append(app: String, price: Double, latencyMs: Int, decision: RideDecision) {
    let (decisionStr, reasonStr): (String, String) = {
      switch decision {
      case .accept(let r): return ("accept", r.rawValue)
      case .reject(let r): return ("reject", r.rawValue)
      }
    }()
    let entry = HistoryEntry(
      id: UUID().uuidString,
      date: Date(),
      app: app,
      price: price,
      latencyMs: latencyMs,
      decision: decisionStr,
      reason: reasonStr
    )
    var list = load()
    list.insert(entry, at: 0)
    if list.count > maxEntries { list = Array(list.prefix(maxEntries)) }
    save(list)
  }

  static func appendDecision(app: String, offer: OfferData, decision: RideDecision) {
    append(app: app, price: offer.price, latencyMs: 0, decision: decision)
  }

  static func load() -> [HistoryEntry] {
    guard let data = UserDefaults.standard.data(forKey: key),
          let list = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return [] }
    return list
  }

  private static func save(_ list: [HistoryEntry]) {
    do {
      let data = try JSONEncoder().encode(list)
      UserDefaults.standard.set(data, forKey: key)
    } catch {
      print("[Destro] failed to save history: \(error)")
    }
  }
}
