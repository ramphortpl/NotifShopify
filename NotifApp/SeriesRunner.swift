import AVFoundation

/// Fait avancer la série en cours.
///
/// iOS ne garde que 64 notifications programmées par app : pour une série plus longue, l'app
/// programme la suite au fur et à mesure que les notifications arrivent. Pour pouvoir le faire
/// écran verrouillé, elle reste active en arrière-plan grâce à une piste muette (mode audio),
/// jusqu'à ce que les dernières soient programmées. L'app ne joue aucun son : le « cha-ching »
/// reste celui des notifications, joué par iOS.
@MainActor
final class SeriesRunner {
    static let shared = SeriesRunner()

    private let silence: AVAudioPlayer?
    private var loop: Task<Void, Never>?

    private init() {
        silence = Bundle.main.url(forResource: "silence.wav", withExtension: nil)
            .flatMap { try? AVAudioPlayer(contentsOf: $0) }
        silence?.numberOfLoops = -1

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            // Après un appel, Siri… : relance la piste muette si la série en a encore besoin.
            guard let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: rawType) == .ended else { return }
            MainActor.assumeIsolated {
                if self?.loop != nil {
                    self?.keepAlive(true)
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

    /// Programme la suite de la série enregistrée tant qu'il en reste (aussi au lancement de l'app).
    func resume() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while let series = NotificationScheduler.savedSeries {
                let done = await NotificationScheduler.refill(series)
                guard !Task.isCancelled else { return }
                if done { break }
                self?.keepAlive(true)
                // 64 notifications d'avance : on complète par paquets d'environ 16.
                try? await Task.sleep(for: .seconds(max(1, min(series.interval * 16, 60))))
                guard !Task.isCancelled else { return }
            }
            self?.keepAlive(false)
            self?.loop = nil
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        keepAlive(false)
    }

    private func keepAlive(_ active: Bool) {
        let session = AVAudioSession.sharedInstance()
        if active {
            try? session.setCategory(.playback, mode: .default, options: .mixWithOthers)
            try? session.setActive(true)
            silence?.play()
        } else {
            silence?.stop()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
