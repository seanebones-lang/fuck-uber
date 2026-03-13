import UIKit
import BackgroundTasks
import WidgetKit

// MARK: - DaemonHolder
/// Single injectable dependency for the daemon. Use instead of (UIApplication.shared.delegate as? AppDelegate)?.daemon.
@MainActor
final class DaemonHolder {
  static let shared = DaemonHolder()
  var daemon: ProdDaemon?
  private init() {}
}

// MARK: - AppDelegate

@main
@MainActor
class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  var daemon: ProdDaemon? {
    get { DaemonHolder.shared.daemon }
    set { DaemonHolder.shared.daemon = newValue }
  }
  var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

  private static let bgRefreshTaskId = "online.nextelevenstudios.destro.refresh"

  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    window = UIWindow(frame: UIScreen.main.bounds)
    window?.rootViewController = DashboardViewController()
    window?.makeKeyAndVisible()
    let d = ProdDaemon()
    d.offerSource = AdaptiveFallbackOfferSource(
      primary: AccessibilityOfferSource(),
      fallback: VisionOfferSource()
    )
    d.actionExecutor = FallbackActionExecutor(
      primary: AccessibilityActionExecutor(),
      fallback: HIDActionExecutor()
    )
    daemon = d
    GeofenceManager.shared.requestLocationPermission()
    SyncManager.shared.pullFromCloud()
    registerBackgroundRefreshTask()
    return true
  }

  private func registerBackgroundRefreshTask() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.bgRefreshTaskId, using: nil) { task in
      guard let refreshTask = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      self.handleBackgroundRefresh(task: refreshTask)
    }
  }

  private func handleBackgroundRefresh(task: BGAppRefreshTask) {
    let request = BGAppRefreshTaskRequest(identifier: Self.bgRefreshTaskId)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    try? BGTaskScheduler.shared.submit(request)

    task.expirationHandler = {
      task.setTaskCompleted(success: false)
    }
    WidgetCenter.shared.reloadAllTimelines()
    task.setTaskCompleted(success: true)
  }

  func applicationDidEnterBackground(_ application: UIApplication) {
    // iOS limits background time; scanning may pause. We schedule a refresh task to update widgets.
    guard daemon?.isScanning == true else { return }
    scheduleBackgroundRefresh()
    backgroundTaskID = application.beginBackgroundTask { [weak self] in
      self?.endBackgroundTask(application)
    }
  }

  private func scheduleBackgroundRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: Self.bgRefreshTaskId)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      // Scheduling can fail if system denies; ignore.
    }
  }

  func applicationWillEnterForeground(_ application: UIApplication) {
    endBackgroundTask(application)
  }

  private func endBackgroundTask(_ application: UIApplication) {
    guard backgroundTaskID != .invalid else { return }
    application.endBackgroundTask(backgroundTaskID)
    backgroundTaskID = .invalid
  }
}
