import Foundation

// MARK: - FilterConfig
// Persisted criteria for auto-accept. Used by ProdDaemon and Filters UI.

struct FilterConfig {
  private static let keyMinPrice = "mystro.filter.minPrice"
  private static let keyMinPerMile = "mystro.filter.minPerMile"
  private static let keyAutoAccept = "mystro.filter.autoAccept"
  private static let keyAutoReject = "mystro.filter.autoReject"

  static var minPrice: Double {
    get {
      let v = UserDefaults.standard.double(forKey: keyMinPrice)
      return v > 0 ? v : 7.0
    }
    set { UserDefaults.standard.set(newValue, forKey: keyMinPrice) }
  }

  static var minPricePerMile: Double {
    get {
      let v = UserDefaults.standard.double(forKey: keyMinPerMile)
      return v > 0 ? v : 0.90
    }
    set { UserDefaults.standard.set(newValue, forKey: keyMinPerMile) }
  }

  static var autoAccept: Bool {
    get { UserDefaults.standard.object(forKey: keyAutoAccept) as? Bool ?? true }
    set { UserDefaults.standard.set(newValue, forKey: keyAutoAccept) }
  }

  static var autoReject: Bool {
    get { UserDefaults.standard.bool(forKey: keyAutoReject) }
    set { UserDefaults.standard.set(newValue, forKey: keyAutoReject) }
  }
}

// MARK: - HistoryEntry

struct HistoryEntry: Codable {
  let id: String
  let date: Date
  let app: String
  let price: Double
  let latencyMs: Int
}

// MARK: - HistoryStore

enum HistoryStore {
  private static let key = "mystro.history.entries"
  private static let maxEntries = 200

  static func append(app: String, price: Double, latencyMs: Int) {
    let entry = HistoryEntry(
      id: UUID().uuidString,
      date: Date(),
      app: app,
      price: price,
      latencyMs: latencyMs
    )
    var list = load()
    list.insert(entry, at: 0)
    if list.count > maxEntries { list = Array(list.prefix(maxEntries)) }
    save(list)
  }

  static func load() -> [HistoryEntry] {
    guard let data = UserDefaults.standard.data(forKey: key),
          let list = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return [] }
    return list
  }

  private static func save(_ list: [HistoryEntry]) {
    guard let data = try? JSONEncoder().encode(list) else { return }
    UserDefaults.standard.set(data, forKey: key)
  }
}
