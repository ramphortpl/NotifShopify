import SwiftUI
import UserNotifications

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @State private var notificationsDenied = false

    var body: some View {
        VStack(spacing: 24) {
            Button(action: sendNotification) {
                Label("Envoyer une notification", systemImage: "bell.badge.fill")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if notificationsDenied {
                VStack(spacing: 8) {
                    Text("Les notifications sont désactivées pour cette app.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Ouvrir les Réglages") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            }
        }
        .padding()
        .task {
            await requestAuthorization()
        }
    }

    // La première fois, iOS affiche la demande d'autorisation ; ensuite il renvoie le choix enregistré.
    @MainActor @discardableResult
    private func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        notificationsDenied = !granted
        return granted
    }

    private func sendNotification() {
        Task { @MainActor in
            guard await requestAuthorization() else { return }

            let content = UNMutableNotificationContent()
            content.title = "Coucou 👋"
            content.body = "Tu as appuyé sur le bouton : la notification fonctionne !"
            content.sound = .default

            // trigger: nil = la notification part immédiatement.
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}

#Preview {
    ContentView()
}
