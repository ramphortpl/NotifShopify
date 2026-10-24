import AVFoundation
import UIKit

/// Joue « cha-ching » depuis l'app pour les séries rapprochées.
///
/// iOS ne joue qu'un son de notification à la fois et saute ceux qui arrivent pendant qu'un autre
/// joue. Pour ces séries, les notifications partent donc sans son et l'app relance « cha-ching »
/// à chaque arrivée, en coupant le précédent. Une piste muette en boucle garde l'app active en
/// arrière-plan (mode audio) jusqu'à la fin de la série.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    private let chaChing: AVAudioPlayer?
    private let silence: AVAudioPlayer?
    private var series: Task<Void, Never>?

    private init() {
        chaChing = Self.player(for: NotificationScheduler.soundFile)
        silence = Self.player(for: "silence.wav")
        silence?.numberOfLoops = -1

        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            // Après un appel, Siri… : relance la piste muette.
            guard let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: rawType) == .ended else { return }
            MainActor.assumeIsolated { self?.resume() }
        }
        center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            // App fermée de force pendant une série : iOS reprend la main sur le son.
            MainActor.assumeIsolated {
                if self?.series != nil {
                    NotificationScheduler.handOverSoundToSystem()
                }
            }
        }
    }

    /// Bouton « Écouter le son ».
    func preview() {
        activateSession()
        restartChaChing()
    }

    /// Joue « cha-ching » à chacune des dates, puis libère l'audio.
    func play(at dates: [Date]) {
        stop()
        guard !dates.isEmpty else { return }
        activateSession()
        silence?.play()
        series = Task { [weak self] in
            for date in dates {
                try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                self?.restartChaChing()
            }
            // Laisse le dernier son se terminer.
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        series?.cancel()
        series = nil
        chaChing?.stop()
        silence?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func resume() {
        guard series != nil else { return }
        activateSession()
        silence?.play()
    }

    private func restartChaChing() {
        chaChing?.currentTime = 0
        chaChing?.play()
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: .mixWithOthers)
        try? session.setActive(true)
    }

    private nonisolated static func player(for file: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: file, withExtension: nil) else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        return player
    }
}
