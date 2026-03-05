import UIKit
import Accessibility

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  var daemon: ProdDaemon?

  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    daemon = ProdDaemon()
    daemon?.startScanning()
    return true
  }
}