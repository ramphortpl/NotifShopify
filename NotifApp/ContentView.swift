import SwiftUI

@MainActor
struct ContentView: View {
    private enum Field { case title, message, orderFrom, orderTo, count }

    @Environment(\.openURL) private var openURL
    @AppStorage("count") private var count = 3
    @AppStorage("speed") private var speed = Speed.normal
    @AppStorage("intervalValue") private var intervalValue = 10
    @AppStorage("intervalUnit") private var unit = IntervalUnit.seconds
    @AppStorage("orderTitle") private var notificationTitle = "Commande #{n}"
    @AppStorage("orderMessage") private var notificationMessage = "50,00 €, 1 article de Boutique en ligne • Tarilo"
    @AppStorage("orderFrom") private var orderFrom = "1000"
    @AppStorage("orderTo") private var orderTo = "1099"
    @FocusState private var focusedField: Field?
    /// Texte du champ « nombre », recopié dans `count` à chaque frappe.
    @State private var countText = ""
    @State private var scheduledDates: [Date] = []
    @State private var isScheduling = false
    @State private var notificationsDenied = false

    /// Intervalle ramené dans les valeurs permises (un ancien réglage à 1 s devient 2 s).
    private var clampedIntervalValue: Int {
        min(max(intervalValue, unit.range.lowerBound), unit.range.upperBound)
    }

    /// Secondes entre deux notifications.
    private var interval: TimeInterval {
        speed.fixedInterval ?? TimeInterval(clampedIntervalValue * unit.seconds)
    }

    /// Tranche des numéros de commande ; un champ vide ou invalide prend une valeur par défaut.
    private var orderRange: ClosedRange<Int> {
        let clamp = { (value: Int) in min(max(value, 0), 999_999_999) }
        let from = clamp(Int(orderFrom) ?? 1000)
        let to = clamp(Int(orderTo) ?? from)
        return min(from, to)...max(from, to)
    }

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
                    let preview = NotificationScheduler.fill(
                        title: notificationTitle,
                        message: notificationMessage,
                        number: orderRange.lowerBound
                    )
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
                    Button {
                        NotificationScheduler.playSound()
                    } label: {
                        Label("Écouter le son", systemImage: "speaker.wave.2.fill")
                    }
                } header: {
                    Text("Notification")
                } footer: {
                    Text("{n} est remplacé par le numéro de commande.")
                }

                Section {
                    LabeledContent("De") {
                        TextField("1000", text: $orderFrom)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .orderFrom)
                    }
                    LabeledContent("À") {
                        TextField("1099", text: $orderTo)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .orderTo)
                    }
                } header: {
                    Text("Numéros de commande")
                } footer: {
                    Text(orderFooter)
                }

                Section {
                    Stepper(value: $count, in: 1...NotificationScheduler.maxCount) {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(.tint)
                            TextField("1", text: $countText)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .count)
                                .fixedSize()
                            Text(count > 1 ? "notifications" : "notification")
                        }
                        .font(.title3.weight(.semibold))
                    }
                } header: {
                    Text("Nombre de notifications")
                } footer: {
                    Text(countFooter)
                }

                Section {
                    Picker("Vitesse", selection: $speed) {
                        ForEach(Speed.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    if speed == .normal {
                        Stepper(value: $intervalValue, in: unit.range) {
                            Label(unit.every(clampedIntervalValue), systemImage: "timer")
                        }
                        Picker("Unité", selection: $unit) {
                            ForEach(IntervalUnit.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text("Vitesse")
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
            intervalValue = clampedIntervalValue
        }
        .onChange(of: countText) {
            if let value = Int(countText) {
                count = min(max(value, 1), NotificationScheduler.maxCount)
            }
        }
        .onChange(of: count) {
            if focusedField != .count { countText = String(count) }
        }
        .onChange(of: focusedField) {
            // En quittant le champ, affiche le nombre retenu (ex. 5000 devient 999).
            if focusedField != .count { countText = String(count) }
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

    private var orderFooter: String {
        let text = "Chaque notification reçoit un numéro au hasard dans cette tranche, en ordre croissant."
        guard orderRange.count < count else { return text }
        return text + " La tranche contient moins de numéros que de notifications : certains se répéteront."
    }

    private var countFooter: String {
        let text = "Jusqu'à \(NotificationScheduler.maxCount)."
        guard count > NotificationScheduler.maxPending else { return text }
        return text + " iOS n'en garde que \(NotificationScheduler.maxPending) d'avance : l'app programme la suite"
            + " au fur et à mesure. Pendant la série, laisse-la en arrière-plan (ne la ferme pas depuis le"
            + " sélecteur d'apps) ; l'iPhone peut être verrouillé."
    }

    private var summary: String {
        var text = ""
        switch speed {
        case .normal: break
        case .fast: text = "Une notification par seconde. "
        case .turbo: text = "Deux notifications par seconde. "
        }
        text += count == 1
            ? "Ta notification arrivera dans \(shortDuration(interval))."
            : "La première arrivera dans \(shortDuration(interval)), la dernière dans \(shortDuration(interval * Double(count)))."
        if speed != .normal {
            text += " C'est plus rapide que le « cha-ching » (1,4 s) : iOS ne joue qu'un son à la fois,"
                + " donc certaines notifications n'auront pas de son."
        } else if unit == .seconds && clampedIntervalValue == unit.range.lowerBound {
            text += " \(unit.range.lowerBound) s minimum en vitesse normale : le « cha-ching » dure 1,4 s"
                + " et iOS ne joue qu'un son de notification à la fois."
        }
        return text
    }

    private func loadState() async {
        intervalValue = clampedIntervalValue
        countText = String(count)
        notificationsDenied = await NotificationScheduler.isDenied()
        // App relancée pendant une série : reprend là où elle en est.
        if let series = NotificationScheduler.savedSeries, !series.remainingDates().isEmpty {
            scheduledDates = series.remainingDates()
            SeriesRunner.shared.resume()
        } else {
            NotificationScheduler.savedSeries = nil
        }
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
            let series = Series(
                start: .now,
                interval: interval,
                numbers: NotificationScheduler.orderNumbers(count: count, in: orderRange),
                title: notificationTitle,
                message: notificationMessage
            )
            SeriesRunner.shared.start(series)
            scheduledDates = series.remainingDates()
        }
    }

    private func stop() {
        SeriesRunner.shared.stop()
        NotificationScheduler.cancel()
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
