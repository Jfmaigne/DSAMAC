import SwiftUI

// MARK: - Vue de diagnostic Kerberos / AD

struct KerberosDiagnosticView: View {
    @StateObject private var diagnosticService = KerberosDiagnosticService()

    /// Domaine AD à tester (pré-rempli depuis LDAPConfigView)
    let domain: String
    /// Serveur AD à tester (peut être vide)
    let server: String

    @State private var filterCategory: DiagnosticEntry.Category? = nil
    @State private var showOnlyProblems: Bool = false
    @State private var copiedToClipboard: Bool = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {

            // ── En-tête ──────────────────────────────────────────────────
            header

            Divider()

            // ── Barre de filtres ─────────────────────────────────────────
            filterBar

            Divider()

            // ── Contenu ──────────────────────────────────────────────────
            if diagnosticService.isRunning {
                progressView
            } else if diagnosticService.entries.isEmpty {
                emptyState
            } else {
                logList
            }

            Divider()

            // ── Pied de page ─────────────────────────────────────────────
            footer
        }
        .frame(minWidth: 700, idealWidth: 800, minHeight: 500, idealHeight: 600)
        .onAppear {
            diagnosticService.runFullDiagnostic(domain: domain, server: server)
        }
    }

    // MARK: - Sous-vues

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "stethoscope")
                .font(.system(size: 28))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Diagnostic Kerberos / Active Directory")
                    .font(.title3).bold()
                HStack(spacing: 8) {
                    if !domain.isEmpty {
                        Label(domain, systemImage: "building.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !server.isEmpty {
                        Label(server, systemImage: "server.rack")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Machine : \(ProcessInfo.processInfo.hostName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                diagnosticService.runFullDiagnostic(domain: domain, server: server)
            } label: {
                Label("Relancer", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(diagnosticService.isRunning)
        }
        .padding()
        .background(.regularMaterial)
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            // Filtre par catégorie
            Picker("Catégorie", selection: $filterCategory) {
                Text("Toutes").tag(nil as DiagnosticEntry.Category?)
                ForEach(DiagnosticEntry.Category.allCases, id: \.rawValue) { cat in
                    Text(cat.rawValue).tag(cat as DiagnosticEntry.Category?)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Problèmes seulement", isOn: $showOnlyProblems)
                .toggleStyle(.switch)
                .controlSize(.small)

            Spacer()

            // Compteurs
            if !diagnosticService.entries.isEmpty {
                HStack(spacing: 8) {
                    badge(count: filteredEntries.filter { $0.status == .success }.count, color: .green, icon: "checkmark.circle.fill")
                    badge(count: filteredEntries.filter { $0.status == .warning }.count, color: .orange, icon: "exclamationmark.triangle.fill")
                    badge(count: filteredEntries.filter { $0.status == .error }.count, color: .red, icon: "xmark.circle.fill")
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var progressView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Diagnostic en cours…")
                .font(.headline)
            Text("Vérification de Kerberos, DNS, réseau et LDAP")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "stethoscope")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Lancez le diagnostic pour vérifier la configuration")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("Lancer le diagnostic") {
                diagnosticService.runFullDiagnostic(domain: domain, server: server)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var logList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(filteredEntries) { entry in
                    DiagnosticEntryRow(entry: entry)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var footer: some View {
        HStack {
            if !diagnosticService.summary.isEmpty {
                Text(diagnosticService.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Bouton Copier
            Button {
                let report = diagnosticService.exportReport()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report, forType: .string)
                copiedToClipboard = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copiedToClipboard = false
                }
            } label: {
                Label(copiedToClipboard ? "Copié !" : "Copier le rapport", systemImage: copiedToClipboard ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .disabled(diagnosticService.entries.isEmpty)

            // Bouton Exporter fichier
            Button {
                exportToFile()
            } label: {
                Label("Exporter…", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(diagnosticService.entries.isEmpty)

            Button("Fermer") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Helpers

    private var filteredEntries: [DiagnosticEntry] {
        diagnosticService.entries.filter { entry in
            if let cat = filterCategory, entry.category != cat { return false }
            if showOnlyProblems && (entry.status != .error && entry.status != .warning) { return false }
            return true
        }
    }

    private func badge(count: Int, color: Color, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.caption2)
            Text("\(count)")
                .font(.caption2.monospacedDigit())
        }
    }

    private func exportToFile() {
        let report = diagnosticService.exportReport()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "DSAMAC_diagnostic_\(formattedDate()).txt"
        panel.title = "Exporter le rapport de diagnostic"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? report.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    private func formattedDate() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HHmmss"
        return fmt.string(from: Date())
    }
}

// MARK: - Ligne de log individuelle

private struct DiagnosticEntryRow: View {
    let entry: DiagnosticEntry
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Ligne titre (toujours visible)
            HStack(spacing: 8) {
                Image(systemName: entry.status.icon)
                    .foregroundStyle(statusColor)
                    .font(.system(size: 13))

                Text(entry.category.rawValue)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(categoryColor.opacity(0.15))
                    .foregroundStyle(categoryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(entry.title)
                    .font(.callout)
                    .fontWeight(entry.status == .error ? .semibold : .regular)
                    .lineLimit(isExpanded ? nil : 1)

                Spacer()

                if !entry.detail.isEmpty {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                if !entry.detail.isEmpty {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            }

            // Détail (dépliable)
            if isExpanded && !entry.detail.isEmpty {
                Text(entry.detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 32)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowBackground)
        )
    }

    private var statusColor: Color {
        switch entry.status {
        case .success:  return .green
        case .warning:  return .orange
        case .error:    return .red
        case .info:     return .blue
        }
    }

    private var categoryColor: Color {
        switch entry.category {
        case .kerberos:     return .purple
        case .dns:          return .blue
        case .ldap:         return .teal
        case .network:      return .orange
        case .environment:  return .indigo
        case .system:       return .gray
        }
    }

    private var rowBackground: Color {
        switch entry.status {
        case .error:    return Color.red.opacity(0.06)
        case .warning:  return Color.orange.opacity(0.04)
        default:        return Color.clear
        }
    }
}

// MARK: - Preview

#if DEBUG
struct KerberosDiagnosticView_Previews: PreviewProvider {
    static var previews: some View {
        KerberosDiagnosticView(domain: "example.local", server: "dc01.example.local")
    }
}
#endif
