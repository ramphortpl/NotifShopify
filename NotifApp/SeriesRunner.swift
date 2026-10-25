import AVFoundation
import UIKit

/// Fait avancer la série en cours.
///
/// - iOS ne garde que 64 notifications programmées par app : pour une série plus longue, l'app
///   programme la suite au fur et à mesure que les notifications arrivent.
/// - iOS ne joue qu'un son de notification à la fois et saute les autres : en vitesse Rapide ou
///   Turbo avec « Un son par notification », les notifications partent sans son et l'app joue
///   elle-même un « cha-ching » à l'arrivée de chacune, en laissant les sons se superposer.
///
/// Pour continuer écran verrouillé, l'app reste active en arrière-plan grâce à une piste muette
/// (mode audio), seulement tant qu'il reste quelque chose à faire.
@MainActor
final class SeriesRunner {
    static let shared = SeriesRunner()

    private let silence: AVAudioPlayer?
    /// Plusieurs lecteurs du même son : à 2 notifications par seconde, jusqu'à 3 « cha-ching » (1,4 s)
    /// se chevauchent.
    private let chaChings: [AVAudioPlayer]
    private var nextChaChing = 0
    private var refillTask: Task<Void, Never>?
    private var soundTask: Task<Void, Never>?
    /// Il reste des notifications à confier à iOS.
    private var refilling = false
    private var keptAlive = false

    private init() {
        silence = Self.player(for: "silence.wav")
        chaChings = (0..<4).compactMap { _ in Self.player(for: NotificationScheduler.soundFile) }
        silence?.numberOfLoops = -1

        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            // Après un appel, Siri… : relance la piste muette si la série en a encore besoin.
            guard let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: rawType) == .ended else { return }
            MainActor.assumeIsolated {
                guard let self, self.keptAlive else { return }
                self.keptAlive = false
                self.updateKeepAlive()
            }
        }
        center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            // App fermée de force pendant que c'est elle qui joue les sons : iOS reprend la main.
            MainActor.assumeIsolated {
                if self?.soundTask != nil {
                    NotificationScheduler.handOverSoundToSystem()
                }
            }
        }
    }

    /// Remplace la série en cours.
    func start(_ series: Series) {
        stop()
        NotificationScheduler.start(series)
        resume()
    }

    /// Reprend la série enregistrée (aussi au lancement de l'app) : programme la suite et,
    /// si besoin, joue les sons.
    func resume() {
        guard let series = NotificationScheduler.savedSeries else { return }

        if refillTask == nil {
            refillTask = Task { [weak self] in
                while let series = NotificationScheduler.savedSeries {
                    let done = await NotificationScheduler.refill(series)
                    guard !Task.isCancelled else { return }
                    if done { break }
                    self?.refilling = true
                    self?.updateKeepAlive()
                    // 64 notifications d'avance : on complète par paquets d'environ 16.
                    try? await Task.sleep(for: .seconds(max(1, min(series.interval * 16, 60))))
                    guard !Task.isCancelled else { return }
                }
                self?.refilling = false
                self?.refillTask = nil
                self?.updateKeepAlive()
            }
        }

        if series.appPlaysSound, soundTask == nil {
            let dates = series.remainingDates()
            soundTask = Task { [weak self] in
                for date in dates {
                    try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
                    guard !Task.isCancelled else { return }
                    self?.playChaChing()
                }
                // Laisse le dernier son se terminer.
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.soundTask = nil
                self?.updateKeepAlive()
            }
            updateKeepAlive()
        }
    }

    func stop() {
        refillTask?.cancel()
        refillTask = nil
        soundTask?.cancel()
        soundTask = nil
        refilling = false
        chaChings.forEach { $0.stop() }
        updateKeepAlive()
    }

    private func playChaChing() {
        guard !chaChings.isEmpty else { return }
        let player = chaChings[nextChaChing % chaChings.count]
        nextChaChing += 1
        player.currentTime = 0
        player.play()
    }

    /// Garde l'app active en arrière-plan tant qu'il reste des notifications à programmer ou des sons à jouer.
    private func updateKeepAlive() {
        let needed = refilling || soundTask != nil
        guard needed != keptAlive else { return }
        keptAlive = needed
        let session = AVAudioSession.sharedInstance()
        if needed {
            try? session.setCategory(.playback, mode: .default, options: .mixWithOthers)
            try? session.setActive(true)
            silence?.play()
        } else {
            silence?.stop()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private nonisolated static func player(for file: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: file, withExtension: nil) else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        return player
    }
}
