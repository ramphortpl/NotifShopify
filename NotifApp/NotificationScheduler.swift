import AudioToolbox
import Foundation
import UserNotifications

/// Programme et annule les séries de notifications locales.
enum NotificationScheduler {
    private static let dateKey = "date"
    /// Son de toutes les notifications : fichier du bundle, moins de 30 s (sinon iOS joue le son par défaut).
    private static let soundFile = "cha_ching.caf"

    private static var center: UNUserNotificationCenter { .current() }

    /// Ne déclenche pas la demande d'autorisation.
    static func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    /// La première fois, iOS affiche la demande d'autorisation ; ensuite il renvoie le choix enregistré.
    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Remplace {n} par le numéro de la notification. Si le titre et le message sont vides,
    /// met un titre par défaut : une notification sans texte ne s'afficherait pas.
    static func fill(title: String, message: String, number: Int) -> (title: String, body: String) {
        let filledTitle = title.replacingOccurrences(of: "{n}", with: "\(number)")
        let filledBody = message.replacingOccurrences(of: "{n}", with: "\(number)")
        if (filledTitle + filledBody).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ("Notification \(number)", "")
        }
        return (filledTitle, filledBody)
    }

    /// Remplace la série en cours par `count` notifications espacées de `interval` secondes,
    /// la première arrivant après un intervalle. Renvoie les dates d'arrivée prévues.
    static func schedule(count: Int, every interval: TimeInterval, title: String, message: String) async -> [Date] {
        center.removeAllPendingNotificationRequests()
        guard count > 0 else { return [] }

        let start = Date()
        var dates: [Date] = []
        for index in 1...count {
            let delay = interval * Double(index)
            let date = start.addingTimeInterval(delay)
            let text = fill(title: title, message: message, number: index)

            let content = UNMutableNotificationContent()
            content.title = text.title
            content.body = text.body
            content.sound = UNNotificationSound(named: UNNotificationSoundName(soundFile))
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

    /// Joue le son des notifications dans l'app (muet si l'iPhone est en mode silencieux).
    static func playSound() {
        guard let url = Bundle.main.url(forResource: soundFile, withExtension: nil) else { return }
        var soundID: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &soundID) == kAudioServicesNoError else { return }
        let id = soundID
        AudioServicesPlaySystemSoundWithCompletion(id) {
            AudioServicesDisposeSystemSoundID(id)
        }
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
