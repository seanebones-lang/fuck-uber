import ActivityKit
import Foundation
import UIKit

// MARK: - Destro Live Activity (iOS 16.1+)
// Lock screen / Dynamic Island: scan status, active app, session earnings.

@available(iOS 16.1, *)
struct DestroLiveActivity: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var status: String
    var activeApp: String
    var sessionEarnings: Double
    var timeOnline: TimeInterval
  }

  var fixedStatus: String
}

@available(iOS 16.1, *)
func updateDestroLiveActivity(status: String, activeApp: String, sessionEarnings: Double, timeOnline: TimeInterval) {
  let state = DestroLiveActivity.ContentState(status: status, activeApp: activeApp, sessionEarnings: sessionEarnings, timeOnline: timeOnline)
  Task {
    for activity in Activity<DestroLiveActivity>.activities {
      await activity.update(ActivityContent(state: state, staleDate: nil))
    }
  }
}

@available(iOS 16.1, *)
func startDestroLiveActivity() {
  guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
  let att = DestroLiveActivity(fixedStatus: "Destro")
  let state = DestroLiveActivity.ContentState(status: "🟢 SCANNING", activeApp: "—", sessionEarnings: 0, timeOnline: 0)
  Task {
    _ = try? await Activity.request(attributes: att, content: ActivityContent(state: state, staleDate: nil), pushType: nil)
  }
}

@available(iOS 16.1, *)
func endDestroLiveActivity() {
  Task {
    for activity in Activity<DestroLiveActivity>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
}
