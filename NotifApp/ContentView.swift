import SwiftUI

@MainActor
struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage("count") private var count = 3
    @AppStorage("intervalValue") private var intervalValue = 10
    @AppStorage("intervalUnit") private var unit = IntervalUnit.seconds
    @State private var scheduledDates: [Date] = []
    @State private var isScheduling = false
    @State private var notificationsDenied = false

    private var intervalSeconds: Int { intervalValue * unit.seconds }

    var body: some View {
        NavigationStack {
            Form {
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

                Section {
                    Button(action: start) {
                        Label(scheduledDates.isEmpty ? "Lancer" : "Relancer", systemImage: "paperplane.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isScheduling)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
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
            }
            .navigationTitle("Notif")
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

    /// Retire chaque notification de « En cours » au moment où elle arrive.
    private func removeDeliveredWhenDue() async {
        guard let next = scheduledDates.first else { return }
        try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow)))
        guard !Task.isCancelled else { return }
        let now = max(next, .now)
        scheduledDates.removeAll { $0 <= now }
    }

    private func start() {
        isScheduling = true
        Task {
            defer { isScheduling = false }
            let granted = await NotificationScheduler.requestAuthorization()
            notificationsDenied = !granted
            guard granted else { return }
            scheduledDates = await NotificationScheduler.schedule(
                count: count,
                every: TimeInterval(intervalSeconds),
                intervalText: unit.quantity(intervalValue)
            )
        }
    }

    private func stop() {
        NotificationScheduler.cancelAll()
        scheduledDates = []
    }
}

#Preview {
    ContentView()
}
