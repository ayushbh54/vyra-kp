import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

  private let notificationChannelName = "com.vyra.parent/notifications"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    UNUserNotificationCenter.current().delegate = self

    // Request notification permissions for lock screen, banner, sound, and badge
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if let error = error {
        print("Vyra Parent: UNUserNotificationCenter auth error: \(error)")
      } else {
        print("Vyra Parent: UNUserNotificationCenter permission granted: \(granted)")
      }
    }

    application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)

    let registrar = self.registrar(forPlugin: "SystemNotificationService")
    if let messenger = registrar?.messenger() {
      let channel = FlutterMethodChannel(name: notificationChannelName, binaryMessenger: messenger)
      channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
        guard let self = self else { return }
        switch call.method {
        case "requestPermissions":
          UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
              result(granted)
            }
          }
        case "showSystemNotification":
          guard let args = call.arguments as? [String: Any],
                let title = args["title"] as? String,
                let body = args["body"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Title and body required", details: nil))
            return
          }
          let notifId = (args["id"] as? String) ?? "vyra_alert_\(Date().timeIntervalSince1970)"
          self.postLocalSystemNotification(id: notifId, title: title, body: body, payload: args)
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Posts a real iOS system notification to Notification Center and Lock Screen with sound
  private func postLocalSystemNotification(id: String, title: String, body: String, payload: [String: Any]?) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    if let payload = payload {
      content.userInfo = payload
    }

    // Trigger immediately (0.1s delay to allow iOS to present banner)
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        print("Vyra Parent: Failed to add system notification: \(error)")
      }
    }
  }

  /// Present banner + sound even when parent app is in the foreground
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  /// Background Fetch: Periodically queries Supabase for urgent Harshit Watchdog alerts
  override func application(
    _ application: UIApplication,
    performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    // Check Supabase REST endpoint for recent alerts in background
    let urlString = "https://wtlqlkkduescumpggttm.supabase.co/rest/v1/notifications?is_important=eq.true&order=id.desc&limit=3"
    guard let url = URL(string: urlString) else {
      completionHandler(.noData)
      return
    }

    var request = URLRequest(url: url)
    request.addValue("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind0bHFsa2tkdWVzY3VtcGdndHRtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5NTkyNjksImV4cCI6MjEwNjUzNTI2OX0.KvgoiPasLnyiWV4kBc-ZeByQQ57RUOsFePDazk2mot0", forHTTPHeaderField: "apikey")
    request.addValue("Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind0bHFsa2tkdWVzY3VtcGdndHRtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5NTkyNjksImV4cCI6MjEwNjUzNTI2OX0.KvgoiPasLnyiWV4kBc-ZeByQQ57RUOsFePDazk2mot0", forHTTPHeaderField: "Authorization")

    let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      guard let self = self, let data = data, error == nil else {
        completionHandler(.failed)
        return
      }

      do {
        if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let latest = jsonArray.first {
          let title = (latest["title"] as? String) ?? "🚨 Vyra Watchdog Alert"
          let text = (latest["text"] as? String) ?? "New alert from monitored device"
          let id = (latest["id"] as? String) ?? "bg_\(Date().timeIntervalSince1970)"

          let defaults = UserDefaults.standard
          let lastSeenId = defaults.string(forKey: "vyra_last_bg_alert_id")
          if lastSeenId != id {
            defaults.set(id, forKey: "vyra_last_bg_alert_id")
            self.postLocalSystemNotification(id: id, title: title, body: text, payload: latest)
            completionHandler(.newData)
            return
          }
        }
        completionHandler(.noData)
      } catch {
        completionHandler(.failed)
      }
    }
    task.resume()
  }
}
