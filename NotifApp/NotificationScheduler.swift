import AudioToolbox
import Foundation
import UserNotifications

/// Programme et annule les séries de notifications locales.
enum NotificationScheduler {
    private static let dateKey = "date"

    private static var center: UNUserNotificationCenter { .current() }

    /// iOS ne joue qu'un son de notification à la fois : celui d'une notification qui arrive
    /// pendant qu'un autre joue est sauté. En dessous de cet intervalle, on prend donc une
    /// version courte du « cha-ching » (0,7 s au lieu de 1,4 s) qui se termine avant la suivante.
    static let shortSoundMaxInterval: TimeInterval = 3

    /// Son des notifications (fichier du bundle, moins de 30 s).
    static func soundFile(every interval: TimeInterval) -> String {
        interval < shortSoundMaxInterval ? "cha_ching_court.caf" : "cha_ching.caf"
    }

    /// Ne déclenche pas la demande d'autorisation.
    static func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    /// La première fois, iOS affiche la demande d'autorisation ; ensuite il renvoie le choix enregistré.
    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// `count` numéros au hasard dans `range`, en ordre croissant comme de vraies commandes,
    /// sans doublon quand la tranche est assez grande.
    static func orderNumbers(count: Int, in range: ClosedRange<Int>) -> [Int] {
        guard range.count >= count else {
            return (0..<count).map { _ in Int.random(in: range) }.sorted()
        }
        var picked = Set<Int>()
        while picked.count < count {
            picked.insert(Int.random(in: range))
        }
        return picked.sorted()
    }

    /// Remplace {n} par le numéro de commande. Si le titre et le message sont vides,
    /// met un titre par défaut : une notification sans texte ne s'afficherait pas.
    static func fill(title: String, message: String, number: Int) -> (title: String, body: String) {
        let filledTitle = title.replacingOccurrences(of: "{n}", with: "\(number)")
        let filledBody = message.replacingOccurrences(of: "{n}", with: "\(number)")
        if (filledTitle + filledBody).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ("Notification \(number)", "")
        }
        return (filledTitle, filledBody)
    }

    /// Remplace la série en cours par une notification par numéro, espacées de `interval` secondes,
    /// la première arrivant après un intervalle. Renvoie les dates d'arrivée prévues.
    static func schedule(numbers: [Int], every interval: TimeInterval, title: String, message: String) async -> [Date] {
        center.removeAllPendingNotificationRequests()

        let sound = UNNotificationSound(named: UNNotificationSoundName(soundFile(every: interval)))
        let start = Date()
        var dates: [Date] = []
        for (offset, number) in numbers.enumerated() {
            let delay = interval * Double(offset + 1)
            let date = start.addingTimeInterval(delay)
            let text = fill(title: title, message: message, number: number)

            let content = UNMutableNotificationContent()
            content.title = text.title
            content.body = text.body
            content.sound = sound
            content.threadIdentifier = "serie"
            content.userInfo = [dateKey: date.timeIntervalSince1970]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let request = UNNotificationRequest(identifier: "serie-\(offset + 1)", content: content, trigger: trigger)
            try? await center.add(request)
            dates.append(date)
        }
        return dates
    }

    static func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    /// Joue dans l'app le son qu'auront les notifications (muet si l'iPhone est en mode silencieux).
    static func playSound(every interval: TimeInterval) {
        guard let url = Bundle.main.url(forResource: soundFile(every: interval), withExtension: nil) else { return }
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
