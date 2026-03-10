import Foundation
import CoreLocation

// MARK: - GeofenceManager
// Uses CoreLocation to check if a coordinate is inside accept-only or avoid zones.
// Zones are persisted via FilterConfig.geofenceZones.

final class GeofenceManager: NSObject {

  static let shared = GeofenceManager()

  private(set) var currentLocation: CLLocation?
  private let locationManager = CLLocationManager()

  /// True when location is authorized; when false, geofencing is off and shouldRejectByGeofence returns false.
  private(set) var isLocationUsable: Bool = false

  override init() {
    super.init()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    locationManager.distanceFilter = 50
    updateLocationUsable()
  }

  private func updateLocationUsable() {
    switch locationManager.authorizationStatus {
    case .authorizedWhenInUse, .authorizedAlways:
      isLocationUsable = true
    default:
      isLocationUsable = false
    }
  }

  func requestLocationPermission() {
    locationManager.requestWhenInUseAuthorization()
  }

  func startUpdatingLocation() {
    locationManager.startUpdatingLocation()
  }

  func stopUpdatingLocation() {
    locationManager.stopUpdatingLocation()
  }

  /// True if coordinate is inside at least one accept-only zone (when accept zones exist).
  func isInAcceptZone(coordinate: CLLocationCoordinate2D) -> Bool {
    guard isLocationUsable else { return true }
    let zones = FilterConfig.geofenceZones.filter { $0.isAcceptZone }
    if zones.isEmpty { return true }
    let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    return zones.contains { zone in
      let center = CLLocation(latitude: zone.latitude, longitude: zone.longitude)
      return loc.distance(from: center) <= zone.radiusMeters
    }
  }

  /// True if coordinate is inside any avoid zone.
  func isInAvoidZone(coordinate: CLLocationCoordinate2D) -> Bool {
    guard isLocationUsable else { return false }
    let zones = FilterConfig.geofenceZones.filter { !$0.isAcceptZone }
    let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    return zones.contains { zone in
      let center = CLLocation(latitude: zone.latitude, longitude: zone.longitude)
      return loc.distance(from: center) <= zone.radiusMeters
    }
  }

  /// For CriteriaEngine: reject if outside accept zone or inside avoid zone. When location denied, returns false (geofencing off).
  func shouldRejectByGeofence(pickupCoordinate: CLLocationCoordinate2D?) -> Bool {
    guard isLocationUsable else { return false }
    guard let coord = pickupCoordinate else { return false }
    if isInAvoidZone(coordinate: coord) { return true }
    if !isInAcceptZone(coordinate: coord) {
      let hasAcceptZones = FilterConfig.geofenceZones.contains { $0.isAcceptZone }
      if hasAcceptZones { return true }
    }
    return false
  }
}

extension GeofenceManager: CLLocationManagerDelegate {
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    currentLocation = locations.last
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    print("[Destro] locationManager didFailWithError: \(error.localizedDescription)")
    currentLocation = nil
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    updateLocationUsable()
    switch manager.authorizationStatus {
    case .denied, .restricted:
      print("[Destro] location authorization denied or restricted")
    default:
      break
    }
  }
}
