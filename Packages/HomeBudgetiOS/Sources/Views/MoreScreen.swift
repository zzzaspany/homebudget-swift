import HomeBudgetCore
import SwiftUI

/// Everything that does not belong on the three screens people open daily: the reserves, the
/// category ceilings, the reports, and where the server lives.
struct MoreScreen: View {
    let session: AutheliaSession
    let model: DashboardModel
    let reminders: ReminderExport

    @State private var exporting: ReportKind?
    @State private var exported: ExportedReport?
    @State private var notice: String?

    private var language: Language { .device }

    var body: some View {
        NavigationStack {
            List {
                if let dashboard = model.dashboard {
                    Section {
                        NavigationLink {
                            SinkingFundsScreen(dashboard: dashboard)
                        } label: {
                            Label(
                                UIString.sectionSinkingFunds(language),
                                systemImage: "arrow.down.to.line")
                        }
                        NavigationLink {
                            CategoryBudgetsScreen(dashboard: dashboard)
                        } label: {
                            Label(
                                UIString.sectionCategoryBudgets(language),
                                systemImage: "chart.bar.horizontal.page")
                        }
                    }
                }

                Section(UIString.sectionReports(language)) {
                    ForEach(ReportKind.allCases) { kind in
                        Button {
                            Task { await export(kind) }
                        } label: {
                            HStack {
                                Label(
                                    kind == .csv
                                        ? UIString.reportCSV(language)
                                        : UIString.reportPDF(language),
                                    systemImage: kind == .csv
                                        ? "tablecells" : "doc.richtext")
                                if exporting == kind {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(exporting != nil)
                    }

                    Button {
                        Task { await sendEmail() }
                    } label: {
                        Label(UIString.actionSendEmail(language), systemImage: "envelope")
                    }
                }

                Section {
                    Button {
                        Task { await syncReminders() }
                    } label: {
                        Label(UIString.remindersSyncPaid(language), systemImage: "checklist.checked")
                    }
                    .disabled(!reminders.hasExported)
                } footer: {
                    if !reminders.hasExported {
                        Text(UIString.actionExportReminders(language))
                    }
                }

                Section(UIString.sectionSettings(language)) {
                    NavigationLink {
                        SettingsScreen(session: session)
                    } label: {
                        Label(UIString.serverAddress(language), systemImage: "server.rack")
                    }
                }
            }
            .navigationTitle(UIString.tabMore(language))
            .sheet(item: $exported) { report in
                ShareLink(item: report.url) {
                    Label(report.url.lastPathComponent, systemImage: "square.and.arrow.up")
                }
                .presentationDetents([.height(160)])
            }
            .alert(
                notice ?? "",
                isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
            ) {
                Button("OK") { notice = nil }
            }
        }
    }

    /// Writes the report to a temporary file, because a share sheet wants a URL and a file the
    /// system can hand to another app — not bytes held in this process.
    private func export(_ kind: ReportKind) async {
        exporting = kind
        defer { exporting = nil }
        do {
            let data = try await APIClient(session: session).report(kind, language: language)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(kind.filename(on: CalendarDate.today()))
            try data.write(to: url, options: .atomic)
            exported = ExportedReport(url: url)
        } catch APIError.signedOut {
            await session.signOut()
        } catch {
            notice = error.localizedDescription
        }
    }

    private func sendEmail() async {
        do {
            try await APIClient(session: session).sendAlertEmail()
            notice = UIString.emailSent(language)
        } catch APIError.signedOut {
            await session.signOut()
        } catch {
            notice = error.localizedDescription
        }
    }

    private func syncReminders() async {
        let paid = await reminders.completedSinceLastSync()
        guard !paid.isEmpty else {
            notice = UIString.remindersSyncNone(language)
            return
        }
        for expenseID in paid {
            guard let summary = model.dashboard?.expenses.first(where: { $0.expense.id == expenseID })
            else { continue }
            await model.pay(summary.expense, amount: nil)
        }
        notice = "\(UIString.remindersSyncDone(language)) \(paid.count)"
    }
}

/// A file on disk, identified by its URL so `sheet(item:)` can present it.
struct ExportedReport: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Where the server lives.
///
/// Kept editable rather than compiled in, so the same build works against a laptop during
/// development and the real host afterwards.
struct SettingsScreen: View {
    let session: AutheliaSession
    @State private var address: String = ServerSettings.load().baseURL.absoluteString
    @State private var saved = false

    private var language: Language { .device }

    var body: some View {
        Form {
            Section {
                TextField(UIString.serverAddress(language), text: $address)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } footer: {
                Text(UIString.serverAddressHint(language))
            }

            Section {
                Button(UIString.actionSave(language)) {
                    // A change only takes effect on the next launch: the session, its cookie store
                    // and every in-flight request are built around the address the app started
                    // with, and quietly swapping it underneath them would be worse than saying so.
                    if let url = URL(string: address.trimmingCharacters(in: .whitespaces)),
                        url.scheme != nil
                    {
                        ServerSettings.save(url)
                        saved = true
                    }
                }
                .disabled(URL(string: address)?.scheme == nil)
            }
        }
        .navigationTitle(UIString.serverAddress(language))
        .navigationBarTitleDisplayMode(.inline)
        .alert(UIString.serverAddressHint(language), isPresented: $saved) {
            Button("OK") { saved = false }
        }
    }
}
