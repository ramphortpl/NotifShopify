import SwiftUI

@MainActor
struct ContentView: View {
    private enum Field { case title, message }

    @Environment(\.openURL) private var openURL
    @AppStorage("count") private var count = 3
    @AppStorage("intervalValue") private var intervalValue = 10
    @AppStorage("intervalUnit") private var unit = IntervalUnit.seconds
    @AppStorage("notificationTitle") private var notificationTitle = "Notification {n}"
    @AppStorage("notificationMessage") private var notificationMessage = "Personnalise ce texte dans l'app ✏️"
    @FocusState private var focusedField: Field?
    @State private var scheduledDates: [Date] = []
    @State private var isScheduling = false
    @State private var notificationsDenied = false

    private var intervalSeconds: Int { intervalValue * unit.seconds }

    var body: some View {
        NavigationStack {
            Form {
                if notificationsDenied {
                    Section {
                        Text("Les notifications sont désactivées pour cette app.")
                        Button("Ouvrir les Réglages") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }
                }

                if let next = scheduledDates.first {
                    Section("En cours") {
                        LabeledContent("Restantes", value: "\(scheduledDates.count)")
                        LabeledContent("Prochaine dans") {
                            Text(next, style: .timer)
                                .monospacedDigit()
                        }
                        Button("Tout arrêter", role: .destructive, action: stop)
                    }
                }

                Section {
                    let preview = NotificationScheduler.fill(title: notificationTitle, message: notificationMessage, number: 1)
                    NotificationPreview(title: preview.title, message: preview.body)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Titre")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Titre de la notification", text: $notificationTitle)
                            .focused($focusedField, equals: .title)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Message")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Message de la notification", text: $notificationMessage, axis: .vertical)
                            .lineLimit(1...5)
                            .focused($focusedField, equals: .message)
                    }
                    Button(action: NotificationScheduler.playSound) {
                        Label("Écouter le son", systemImage: "speaker.wave.2.fill")
                    }
                } header: {
                    Text("Notification")
                } footer: {
                    Text("Écris {n} pour afficher le numéro de la notification (1, 2, 3…).")
                }

                Section {
                    Stepper(value: $count, in: 1...64) {
                        Label("\(count) notification\(count > 1 ? "s" : "")", systemImage: "bell.fill")
                            .font(.title3.weight(.semibold))
                    }
                } header: {
                    Text("Nombre de notifications")
                } footer: {
                    Text("64 au maximum (limite d'iOS).")
                }

                Section {
                    Stepper(value: $intervalValue, in: unit.range) {
                        Label(unit.every(intervalValue), systemImage: "timer")
                    }
                    Picker("Unité", selection: $unit) {
                        ForEach(IntervalUnit.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Intervalle")
                } footer: {
                    Text(summary)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                launchButton
            }
            .navigationTitle("Notif")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { focusedField = nil }
                }
            }
        }
        .onChange(of: unit) {
            intervalValue = min(max(intervalValue, unit.range.lowerBound), unit.range.upperBound)
        }
        .task {
            await loadState()
        }
        .task(id: scheduledDates) {
            await removeDeliveredWhenDue()
        }
    }

    private var launchButton: some View {
        Button(action: start) {
            Label(scheduledDates.isEmpty ? "Lancer" : "Relancer", systemImage: "paperplane.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isScheduling)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var summary: String {
        let first = shortDuration(intervalSeconds)
        if count == 1 {
            return "Ta notification arrivera dans \(first)."
        }
        return "La première arrivera dans \(first), la dernière dans \(shortDuration(intervalSeconds * count))."
    }

    private func loadState() async {
        notificationsDenied = await NotificationScheduler.isDenied()
        scheduledDates = await NotificationScheduler.pendingDates()
    }

    /// Retire de « En cours » les notifications déjà arrivées, au moment où elles arrivent.
    private func removeDeliveredWhenDue() async {
        guard let next = scheduledDates.first else { return }
        try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow)))
        guard !Task.isCancelled else { return }
        let now = max(next, .now)
        scheduledDates.removeAll { $0 <= now }
    }

    private func start() {
        focusedField = nil
        isScheduling = true
        Task {
            defer { isScheduling = false }
            let granted = await NotificationScheduler.requestAuthorization()
            notificationsDenied = !granted
            guard granted else { return }
            scheduledDates = await NotificationScheduler.schedule(
                count: count,
                every: TimeInterval(intervalSeconds),
                title: notificationTitle,
                message: notificationMessage
            )
        }
    }

    private func stop() {
        NotificationScheduler.cancelAll()
        scheduledDates = []
    }
}

/// Imite une bannière de notification iOS, avec le logo de l'app.
private struct NotificationPreview: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text("maintenant")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
}
