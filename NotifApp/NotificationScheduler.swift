import Foundation
import UserNotifications

/// Programme et annule les séries de notifications locales.
enum NotificationScheduler {
    private static let dateKey = "date"

    private static var center: UNUserNotificationCenter { .current() }

    /// Ne déclenche pas la demande d'autorisation.
    static func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    /// La première fois, iOS affiche la demande d'autorisation ; ensuite il renvoie le choix enregistré.
    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Remplace la série en cours par `count` notifications espacées de `interval` secondes,
    /// la première arrivant après un intervalle. Renvoie les dates d'arrivée prévues.
    static func schedule(count: Int, every interval: TimeInterval, intervalText: String) async -> [Date] {
        center.removeAllPendingNotificationRequests()
        guard count > 0 else { return [] }

        let start = Date()
        var dates: [Date] = []
        for index in 1...count {
            let delay = interval * Double(index)
            let date = start.addingTimeInterval(delay)

            let content = UNMutableNotificationContent()
            content.title = "Notification \(index) sur \(count)"
            content.body = index == count ? "C'était la dernière ! 🎉" : "Prochaine dans \(intervalText)."
            content.sound = .default
            content.threadIdentifier = "serie"
            content.userInfo = [dateKey: date.timeIntervalSince1970]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let request = UNNotificationRequest(identifier: "serie-\(index)", content: content, trigger: trigger)
            try? await center.add(request)
            dates.append(date)
        }
        return dates
    }

    static func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    /// Dates des notifications encore à venir, pour retrouver la série quand l'app est rouverte.
    static func pendingDates() async -> [Date] {
        await center.pendingNotificationRequests()
            .compactMap { $0.content.userInfo[dateKey] as? TimeInterval }
            .map(Date.init(timeIntervalSince1970:))
            .filter { $0 > .now }
            .sorted()
    }
}
