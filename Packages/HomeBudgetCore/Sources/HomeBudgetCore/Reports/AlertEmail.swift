/// The payment-reminder e-mail.
///
/// Styling is inline because mail clients discard stylesheets, and the layout is a table for the
/// same reason.
public enum AlertEmail {
    public static func subject(alertCount: Int, language: Language) -> String {
        switch language {
        case .pl: return "HomeBudget: \(Localization.alertCountLabel(alertCount, language: .pl))"
        case .en: return "HomeBudget: \(alertCount) payment alert\(alertCount == 1 ? "" : "s")"
        }
    }

    public static func html(
        notifications: [Dashboard.NotificationItem],
        language: Language
    ) -> String {
        let heading = language == .pl ? "Alerty płatności" : "Payment alerts"
        let intro = language == .pl
            ? "Poniżej opłaty wymagające uwagi:"
            : "The following bills need attention:"
        let columns = language == .pl
            ? ["Wydatek", "Kwota", "Status", "Termin"]
            : ["Expense", "Amount", "Status", "Due"]
        let footer = language == .pl
            ? "Wiadomość wygenerowana automatycznie przez HomeBudget."
            : "Generated automatically by HomeBudget."

        let rows = notifications.map { item -> String in
            let color = item.status == .overdue ? "#ef4444" : "#f59e0b"
            let label = item.status.uiLabel(language: language).uppercased()
            let message = Localization.notificationMessage(
                status: item.status, daysLeft: item.daysLeft, language: language)

            return """
                <tr style="border-bottom:1px solid #e2e8f0;">
                  <td style="padding:10px;font-weight:bold;color:#0f172a;">\(escape(item.name))</td>
                  <td style="padding:10px;font-weight:bold;color:#059669;white-space:nowrap;">\
                \(escape(NumberFormatting.currency(item.amount, language: language)))</td>
                  <td style="padding:10px;"><span style="background:\(color)15;color:\(color);\
                font-weight:bold;padding:4px 8px;border-radius:4px;font-size:0.85rem;\
                white-space:nowrap;">\(escape(label))</span></td>
                  <td style="padding:10px;color:#64748b;">\(escape(message))</td>
                </tr>
                """
        }

        return """
            <!DOCTYPE html>
            <html><head><meta charset="utf-8"></head>
            <body style="font-family:Arial,sans-serif;background-color:#f8fafc;color:#334155;padding:20px;">
              <div style="max-width:600px;margin:0 auto;background:#ffffff;border-radius:8px;\
            padding:24px;box-shadow:0 4px 6px -1px rgba(0,0,0,0.1);">
                <h2 style="color:#0f172a;margin-top:0;">HomeBudget — \(heading)</h2>
                <p>\(intro)</p>
                <table style="width:100%;border-collapse:collapse;margin-top:16px;">
                  <thead>
                    <tr style="background:#f1f5f9;text-align:left;font-size:0.85rem;color:#475569;">
                      \(columns.map { "<th style=\"padding:8px;\">\(escape($0))</th>" }.joined())
                    </tr>
                  </thead>
                  <tbody>
                    \(rows.joined(separator: "\n"))
                  </tbody>
                </table>
                <p style="margin-top:24px;font-size:0.85rem;color:#94a3b8;text-align:center;">\(footer)</p>
              </div>
            </body></html>
            """
    }

    /// Expense names are user input and land in markup, so the five HTML-significant characters go.
    static func escape(_ text: String) -> String {
        var output = ""
        for character in text {
            switch character {
            case "&": output += "&amp;"
            case "<": output += "&lt;"
            case ">": output += "&gt;"
            case "\"": output += "&quot;"
            case "'": output += "&#39;"
            default: output.append(character)
            }
        }
        return output
    }
}
