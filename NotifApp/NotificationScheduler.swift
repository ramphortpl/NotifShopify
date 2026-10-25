import AudioToolbox
import Foundation
import UserNotifications

/// Une série de notifications, enregistrée pour pouvoir la reprendre si l'app est relancée.
struct Series: Codable {
    /// Rend les identifiants uniques : une notification qui reprend l'identifiant d'une notification
    /// déjà reçue la remplace dans le centre de notifications.
    var id = UUID()
    var start: Date
    var interval: TimeInterval
    var numbers: [Int]
    var title: String
    var message: String
    /// Les notifications partent sans son et c'est l'app qui joue chaque « cha-ching »
    /// (voir `SeriesRunner`) : à grande vitesse, iOS en sauterait.
    var appPlaysSound: Bool

    /// Arrivée de la notification `index` (la première arrive après un intervalle).
    func date(at index: Int) -> Date {
        start.addingTimeInterval(interval * Double(index + 1))
    }

    /// Dates des notifications pas encore arrivées.
    func remainingDates(after now: Date = .now) -> [Date] {
        numbers.indices.map(date(at:)).filter { $0 > now }
    }
}

/// Programme et annule les séries de notifications locales.
enum NotificationScheduler {
    /// iOS ne garde que les 64 prochaines notifications programmées d'une app : au-delà, la suite
    /// est programmée au fur et à mesure (voir `SeriesRunner`).
    static let maxPending = 64
    static let maxCount = 999

    /// Son des notifications : fichier du bundle, moins de 30 s (1,4 s ici).
    static let soundFile = "cha_ching.caf"
    private static let seriesKey = "series"
    private static let dateKey = "date"

    private static var center: UNUserNotificationCenter { .current() }

    /// Série en cours, enregistrée dans les réglages de l'app.
    static var savedSeries: Series? {
        get {
            UserDefaults.standard.data(forKey: seriesKey).flatMap { try? JSONDecoder().decode(Series.self, from: $0) }
        }
        set {
            UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: seriesKey)
        }
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

    /// Remplace la série en cours ; `refill` programme ensuite ses notifications.
    static func start(_ series: Series) {
        center.removeAllPendingNotificationRequests()
        savedSeries = series
    }

    /// Programme les prochaines notifications de la série sans dépasser 64 en attente.
    /// Renvoie `true` quand toutes celles à venir sont programmées.
    static func refill(_ series: Series) async -> Bool {
        let pending = Set(await center.pendingNotificationRequests().map(\.identifier))
        var free = maxPending - pending.count
        let sound = UNNotificationSound(named: UNNotificationSoundName(soundFile))
        for index in series.numbers.indices {
            let identifier = "serie-\(series.id.uuidString)-\(index + 1)"
            // Déjà passée ou trop proche pour qu'iOS la livre à l'heure.
            let delay = series.date(at: index).timeIntervalSinceNow
            guard delay > 0.2, !pending.contains(identifier) else { continue }
            guard free > 0 else { return false }

            let text = fill(title: series.title, message: series.message, number: series.numbers[index])
            let content = UNMutableNotificationContent()
            content.title = text.title
            content.body = text.body
            content.sound = series.appPlaysSound ? nil : sound
            content.threadIdentifier = "serie"
            content.userInfo = [dateKey: series.date(at: index).timeIntervalSince1970]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            free -= 1
        }
        return true
    }

    /// L'app va être fermée : les notifications à venir reprennent le son d'iOS, puisque l'app ne sera
    /// plus là pour le jouer. Bloque au plus 3 secondes, le temps qu'iOS enregistre les changements.
    static func handOverSoundToSystem() {
        if var series = savedSeries {
            series.appPlaysSound = false
            savedSeries = series
        }
        let fetched = DispatchSemaphore(value: 0)
        let pending = Box<[UNNotificationRequest]>([])
        center.getPendingNotificationRequests { requests in
            pending.value = requests
            fetched.signal()
        }
        guard fetched.wait(timeout: .now() + 1) == .success else { return }

        let added = DispatchGroup()
        let sound = UNNotificationSound(named: UNNotificationSoundName(soundFile))
        for request in pending.value where request.content.sound == nil {
            guard let timestamp = request.content.userInfo[dateKey] as? TimeInterval,
                  let content = request.content.mutableCopy() as? UNMutableNotificationContent else { continue }
            let delay = Date(timeIntervalSince1970: timestamp).timeIntervalSinceNow
            guard delay > 0.5 else { continue }
            content.sound = sound
            added.enter()
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger)) { _ in
                added.leave()
            }
        }
        _ = added.wait(timeout: .now() + 2)
    }

    /// Annule la série : les notifications pas encore arrivées ne partiront pas.
    static func cancel() {
        center.removeAllPendingNotificationRequests()
        savedSeries = nil
    }

    /// Joue dans l'app le son des notifications (muet si l'iPhone est en mode silencieux).
    static func playSound() {
        guard let url = Bundle.main.url(forResource: soundFile, withExtension: nil) else { return }
        var soundID: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &soundID) == kAudioServicesNoError else { return }
        let id = soundID
        AudioServicesPlaySystemSoundWithCompletion(id) {
            AudioServicesDisposeSystemSoundID(id)
        }
    }
}

/// Récupère le résultat d'un callback pour l'attendre de façon synchrone.
private final class Box<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
