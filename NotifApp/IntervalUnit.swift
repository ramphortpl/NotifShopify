import Foundation

/// Vitesse des notifications : intervalle réglable, ou plus rapide que son minimum de 2 s.
enum Speed: String, CaseIterable, Identifiable {
    case normal, fast, turbo

    var id: Self { self }

    var title: String {
        switch self {
        case .normal: "Normale"
        case .fast: "Rapide"
        case .turbo: "Turbo"
        }
    }

    /// Intervalle imposé par la vitesse ; `nil` pour l'intervalle réglable.
    var fixedInterval: TimeInterval? {
        switch self {
        case .normal: return nil
        case .fast: return 1
        case .turbo: return 0.5
        }
    }
}

enum IntervalUnit: String, CaseIterable, Identifiable {
    case seconds, minutes, hours

    var id: Self { self }

    var seconds: Int {
        switch self {
        case .seconds: 1
        case .minutes: 60
        case .hours: 3600
        }
    }

    /// Valeurs accessibles avec les boutons − / +.
    /// 2 s minimum : le « cha-ching » dure 1,4 s et iOS ne joue qu'un son de notification à la fois,
    /// donc à 1 s d'intervalle une notification sur deux arriverait pendant le son de la précédente
    /// et resterait muette.
    var range: ClosedRange<Int> {
        switch self {
        case .seconds: 2...59
        case .minutes: 1...59
        case .hours: 1...24
        }
    }

    var title: String {
        switch self {
        case .seconds: "Secondes"
        case .minutes: "Minutes"
        case .hours: "Heures"
        }
    }

    private var singular: String {
        switch self {
        case .seconds: "seconde"
        case .minutes: "minute"
        case .hours: "heure"
        }
    }

    /// « Toutes les minutes », « Toutes les 10 secondes »
    func every(_ value: Int) -> String {
        value == 1 ? "Toutes les \(singular)s" : "Toutes les \(value) \(singular)s"
    }
}

/// « 0,5 s », « 50 s », « 1 h 30 min »
func shortDuration(_ seconds: TimeInterval) -> String {
    if seconds < 60, seconds.rounded() != seconds {
        return String(format: "%.1f s", seconds).replacingOccurrences(of: ".", with: ",")
    }
    let total = Int(seconds.rounded())
    let parts = [(total / 3600, "h"), (total % 3600 / 60, "min"), (total % 60, "s")]
    return parts.filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }.joined(separator: " ")
}
