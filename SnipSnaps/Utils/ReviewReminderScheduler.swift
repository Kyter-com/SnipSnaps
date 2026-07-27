import Foundation
import UserNotifications

enum ReviewReminderScheduler {
  static let enabledKey = "reviewReminderEnabled"
  static let hourKey = "reviewReminderHour"
  static let minuteKey = "reviewReminderMinute"

  static let defaultHour = 19
  static let defaultMinute = 0

  private static let requestIdentifier = "com.kyter.SnipSnaps.dailyReviewReminder"

  static func authorizationStatus() async -> UNAuthorizationStatus {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    return settings.authorizationStatus
  }

  @discardableResult
  static func requestAndSchedule(hour: Int, minute: Int) async throws -> Bool {
    let center = UNUserNotificationCenter.current()
    let status = await authorizationStatus()
    let allowed: Bool

    switch status {
    case .authorized, .provisional:
      allowed = true
    #if os(iOS)
    case .ephemeral:
      allowed = true
    #endif
    case .notDetermined:
      allowed = try await center.requestAuthorization(options: [.alert, .sound])
    case .denied:
      allowed = false
    @unknown default:
      allowed = false
    }

    guard allowed else {
      cancel()
      return false
    }

    try await schedule(hour: hour, minute: minute)
    return true
  }

  static func rescheduleIfEnabled(hour: Int, minute: Int) async throws {
    let defaults = UserDefaults.standard
    guard defaults.bool(forKey: enabledKey) else { return }
    let status = await authorizationStatus()
    guard allowsScheduling(status) else {
      cancel()
      return
    }
    try await schedule(hour: hour, minute: minute)
    if !defaults.bool(forKey: enabledKey) {
      cancel()
    }
  }

  static func restoreIfEnabled() async {
    let defaults = UserDefaults.standard
    guard defaults.bool(forKey: enabledKey) else { return }

    let status = await authorizationStatus()
    guard allowsScheduling(status) else {
      if status == .denied || status == .notDetermined {
        defaults.set(false, forKey: enabledKey)
      }
      cancel()
      return
    }

    let storedHour = defaults.object(forKey: hourKey) as? Int
    let storedMinute = defaults.object(forKey: minuteKey) as? Int
    try? await schedule(
      hour: storedHour ?? defaultHour,
      minute: storedMinute ?? defaultMinute
    )
    if !defaults.bool(forKey: enabledKey) {
      cancel()
    }
  }

  static func cancel() {
    UNUserNotificationCenter.current()
      .removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
  }

  private static func allowsScheduling(_ status: UNAuthorizationStatus) -> Bool {
    switch status {
    case .authorized, .provisional:
      return true
    #if os(iOS)
    case .ephemeral:
      return true
    #endif
    case .notDetermined, .denied:
      return false
    @unknown default:
      return false
    }
  }

  private static func schedule(hour: Int, minute: Int) async throws {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])

    let content = UNMutableNotificationContent()
    content.title = "A quick SnipSnaps review?"
    content.body = "Take a minute to clear a little photo clutter."
    content.sound = .default

    var components = DateComponents()
    components.calendar = .current
    components.hour = min(max(hour, 0), 23)
    components.minute = min(max(minute, 0), 59)

    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
    let request = UNNotificationRequest(
      identifier: requestIdentifier,
      content: content,
      trigger: trigger
    )
    try await center.add(request)
  }
}
