import Foundation
import UserNotifications

/// Programme et annule les séries de notifications locales.
enum NotificationScheduler {
    /// Son de toutes les notifications : fichier du bundle, moins de 30 s (sinon iOS joue le son par défaut).
    static let soundFile = "cha_ching.caf"
    /// En dessous de cet intervalle, iOS sauterait des sons : les notifications partent sans son
    /// et c'est l'app qui joue « cha-ching » (voir `SoundPlayer`).
    static let appSoundMaxInterval: TimeInterval = 60

    /// Notification encore à venir.
    struct Pending {
        let date: Date
        /// C'est l'app qui doit jouer son son.
        let appPlaysSound: Bool
    }

    private static let dateKey = "date"

    private static var center: UNUserNotificationCenter { .current() }

    private static var systemSound: UNNotificationSound {
        UNNotificationSound(named: UNNotificationSoundName(soundFile))
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

        let start = Date()
        var dates: [Date] = []
        for (offset, number) in numbers.enumerated() {
            let delay = interval * Double(offset + 1)
            let date = start.addingTimeInterval(delay)
            let text = fill(title: title, message: message, number: number)

            let content = UNMutableNotificationContent()
            content.title = text.title
            content.body = text.body
            content.sound = interval < appSoundMaxInterval ? nil : systemSound
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

    /// Notifications encore à venir, pour retrouver la série quand l'app est rouverte.
    static func pending() async -> [Pending] {
        await center.pendingNotificationRequests()
            .compactMap { request -> Pending? in
                guard let date = fireDate(of: request), date > .now else { return nil }
                return Pending(date: date, appPlaysSound: request.content.sound == nil)
            }
            .sorted { $0.date < $1.date }
    }

    /// L'app va être fermée : les notifications à venir dont elle devait jouer le son reprennent
    /// le son système. Bloque au plus 3 secondes, le temps qu'iOS enregistre les changements.
    static func handOverSoundToSystem() {
        let fetched = DispatchSemaphore(value: 0)
        let pending = Box<[UNNotificationRequest]>([])
        center.getPendingNotificationRequests { requests in
            pending.value = requests
            fetched.signal()
        }
        guard fetched.wait(timeout: .now() + 1) == .success else { return }

        let added = DispatchGroup()
        for request in pending.value where request.content.sound == nil {
            guard let date = fireDate(of: request), date.timeIntervalSinceNow > 0.5,
                  let content = request.content.mutableCopy() as? UNMutableNotificationContent else { continue }
            content.sound = systemSound
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: date.timeIntervalSinceNow, repeats: false)
            added.enter()
            center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger)) { _ in
                added.leave()
            }
        }
        _ = added.wait(timeout: .now() + 2)
    }

    private static func fireDate(of request: UNNotificationRequest) -> Date? {
        (request.content.userInfo[dateKey] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
    }
}

/// Récupère le résultat d'un callback pour l'attendre de façon synchrone.
private final class Box<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
