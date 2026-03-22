import Foundation
import Combine

// MARK: - Entrée de log de diagnostic

struct DiagnosticEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let category: Category
    let title: String
    let detail: String
    let status: Status

    enum Category: String, CaseIterable {
        case kerberos   = "Kerberos"
        case dns        = "DNS"
        case ldap       = "LDAP"
        case network    = "Réseau"
        case environment = "Environnement"
        case system     = "Système"
    }

    enum Status {
        case success
        case warning
        case error
        case info

        var icon: String {
            switch self {
            case .success:  return "checkmark.circle.fill"
            case .warning:  return "exclamationmark.triangle.fill"
            case .error:    return "xmark.circle.fill"
            case .info:     return "info.circle.fill"
            }
        }

        var colorName: String {
            switch self {
            case .success:  return "green"
            case .warning:  return "orange"
            case .error:    return "red"
            case .info:     return "blue"
            }
        }
    }
}

// MARK: - Service de diagnostic Kerberos

@MainActor
final class KerberosDiagnosticService: ObservableObject {

    @Published var entries: [DiagnosticEntry] = []
    @Published var isRunning: Bool = false
    @Published var summary: String = ""

    /// Lance le diagnostic complet
    func runFullDiagnostic(domain: String = "", server: String = "") {
        isRunning = true
        entries = []
        summary = ""

        // Tout se fait en tâche de fond pour ne pas bloquer l'UI
        let dom = domain
        let srv = server
        Task.detached { [weak self] in
            var allEntries: [DiagnosticEntry] = []

            // 1. Informations système
            allEntries += Self.diagnoseSystem()

            // 2. Variables d'environnement Kerberos
            allEntries += Self.diagnoseEnvironment()

            // 3. Configuration Kerberos (krb5.conf)
            allEntries += Self.diagnoseKerberosConfig()

            // 4. Tickets Kerberos (klist avec toutes les variantes)
            allEntries += Self.diagnoseKerberosTickets()

            // 5. DNS SRV pour le domaine
            if !dom.isEmpty {
                allEntries += Self.diagnoseDNS(domain: dom)
            }

            // 6. Connectivité réseau vers le serveur
            if !srv.isEmpty {
                allEntries += Self.diagnoseNetwork(server: srv, domain: dom)
            } else if !dom.isEmpty {
                allEntries += Self.diagnoseNetwork(server: "", domain: dom)
            }

            // 7. Test ldapsearch basique
            if !dom.isEmpty {
                allEntries += Self.diagnoseLDAP(domain: dom, server: srv)
            }

            // Résumé
            let errors = allEntries.filter { $0.status == .error }.count
            let warnings = allEntries.filter { $0.status == .warning }.count
            let successes = allEntries.filter { $0.status == .success }.count
            let summaryText = "✅ \(successes)  ⚠️ \(warnings)  ❌ \(errors)  —  \(allEntries.count) vérifications effectuées"

            await MainActor.run {
                self?.entries = allEntries
                self?.summary = summaryText
                self?.isRunning = false
            }
        }
    }

    /// Exporte le rapport complet en texte brut
    func exportReport() -> String {
        var lines: [String] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        lines.append("═══════════════════════════════════════════════════════════")
        lines.append("  DSAMAC — Rapport de diagnostic Kerberos / AD")
        lines.append("  Généré le : \(dateFormatter.string(from: Date()))")
        lines.append("  Machine   : \(ProcessInfo.processInfo.hostName)")
        lines.append("  Utilisateur: \(NSUserName())")
        lines.append("═══════════════════════════════════════════════════════════")
        lines.append("")

        var currentCategory: DiagnosticEntry.Category?
        for entry in entries {
            if entry.category != currentCategory {
                currentCategory = entry.category
                lines.append("───────────────────────────────────────────────────────────")
                lines.append("  [\(entry.category.rawValue)]")
                lines.append("───────────────────────────────────────────────────────────")
            }
            let icon: String
            switch entry.status {
            case .success:  icon = "✅"
            case .warning:  icon = "⚠️"
            case .error:    icon = "❌"
            case .info:     icon = "ℹ️"
            }
            lines.append("\(icon) \(entry.title)")
            if !entry.detail.isEmpty {
                // Indenter chaque ligne du détail
                for detailLine in entry.detail.components(separatedBy: "\n") {
                    lines.append("    \(detailLine)")
                }
            }
            lines.append("")
        }

        lines.append("═══════════════════════════════════════════════════════════")
        lines.append(summary)
        lines.append("═══════════════════════════════════════════════════════════")

        return lines.joined(separator: "\n")
    }

    // MARK: - Diagnostic système

    private static func diagnoseSystem() -> [DiagnosticEntry] {
        var entries: [DiagnosticEntry] = []

        // Version macOS
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .system,
            title: "macOS \(osVersion)",
            detail: "Host: \(ProcessInfo.processInfo.hostName)\nUtilisateur: \(NSUserName())",
            status: .info
        ))

        // Vérifier si l'app est sandboxée
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .system,
            title: isSandboxed ? "Application sandboxée (App Sandbox actif)" : "Application non sandboxée",
            detail: isSandboxed
                ? "⚠️ La sandbox peut empêcher l'accès au cache Kerberos.\nContainer: \(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] ?? "?")"
                : "L'app a accès au cache Kerberos du système.",
            status: isSandboxed ? .warning : .success
        ))

        // Vérifier la présence de klist
        let klistExists = FileManager.default.fileExists(atPath: "/usr/bin/klist")
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .system,
            title: klistExists ? "/usr/bin/klist trouvé" : "/usr/bin/klist introuvable",
            detail: klistExists ? "" : "L'outil klist est nécessaire pour lister les tickets Kerberos.",
            status: klistExists ? .success : .error
        ))

        // Vérifier la présence de ldapsearch
        let ldapExists = FileManager.default.fileExists(atPath: "/usr/bin/ldapsearch")
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .system,
            title: ldapExists ? "/usr/bin/ldapsearch trouvé" : "/usr/bin/ldapsearch introuvable",
            detail: ldapExists ? "" : "Installez les Command Line Tools : xcode-select --install",
            status: ldapExists ? .success : .error
        ))

        // Vérifier la présence de dig
        let digExists = FileManager.default.fileExists(atPath: "/usr/bin/dig")
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .system,
            title: digExists ? "/usr/bin/dig trouvé" : "/usr/bin/dig introuvable",
            detail: "",
            status: digExists ? .success : .warning
        ))

        return entries
    }

    // MARK: - Variables d'environnement

    private static func diagnoseEnvironment() -> [DiagnosticEntry] {
        var entries: [DiagnosticEntry] = []
        let env = ProcessInfo.processInfo.environment

        let kerberosVars = [
            "KRB5CCNAME", "KRB5_CONFIG", "KRB5_KTNAME", "KRB5_CLIENT_KTNAME",
            "KRB5_DEFAULT_REALM", "KRB5_TRACE",
            "LDAPTLS_REQCERT", "LDAPTLS_CACERT", "LDAPTLS_CACERTDIR",
            "LDAP_OPT_REFERRALS"
        ]

        var found: [String] = []
        var notFound: [String] = []

        for varName in kerberosVars {
            if let value = env[varName] {
                found.append("\(varName) = \(value)")
            } else {
                notFound.append(varName)
            }
        }

        if found.isEmpty {
            entries.append(DiagnosticEntry(
                timestamp: Date(), category: .environment,
                title: "Aucune variable Kerberos/LDAP définie",
                detail: "Variables vérifiées : \(kerberosVars.joined(separator: ", "))\n\nCeci est normal si Kerberos utilise la configuration par défaut.\nLe cache par défaut sur macOS est géré par le KerberosAgent (API:).",
                status: .info
            ))
        } else {
            entries.append(DiagnosticEntry(
                timestamp: Date(), category: .environment,
                title: "\(found.count) variable(s) Kerberos/LDAP définie(s)",
                detail: found.joined(separator: "\n"),
                status: .info
            ))
        }

        // Variable HOME
        if let home = env["HOME"] {
            entries.append(DiagnosticEntry(
                timestamp: Date(), category: .environment,
                title: "HOME = \(home)",
                detail: "",
                status: .info
            ))
        }

        return entries
    }

    // MARK: - Configuration Kerberos

    private static func diagnoseKerberosConfig() -> [DiagnosticEntry] {
        var entries: [DiagnosticEntry] = []

        // Vérifier /etc/krb5.conf
        let krb5Path = "/etc/krb5.conf"
        if FileManager.default.fileExists(atPath: krb5Path) {
            if let content = try? String(contentsOfFile: krb5Path, encoding: .utf8) {
                let preview = content.count > 2000
                    ? String(content.prefix(2000)) + "\n… (tronqué)"
                    : content
                entries.append(DiagnosticEntry(
                    timestamp: Date(), category: .kerberos,
                    title: "/etc/krb5.conf trouvé (\(content.count) octets)",
                    detail: preview,
                    status: .success
                ))
            } else {
                entries.append(DiagnosticEntry(
                    timestamp: Date(), category: .kerberos,
                    title: "/etc/krb5.conf trouvé mais illisible",
                    detail: "Vérifiez les permissions du fichier.",
                    status: .warning
                ))
            }
        } else {
            entries.append(DiagnosticEntry(
                timestamp: Date(), category: .kerberos,
                title: "/etc/krb5.conf absent",
                detail: "macOS utilise la configuration Kerberos par défaut (Heimdal).\nCe fichier n'est pas obligatoire si le DNS est correctement configuré.",
                status: .info
            ))
        }

        // Vérifier la config Kerberos via /Library/Preferences/edu.mit.Kerberos
        let mitPath = "/Library/Preferences/edu.mit.Kerberos"
        if FileManager.default.fileExists(atPath: mitPath) {
            if let content = try? String(contentsOfFile: mitPath, encoding: .utf8) {
                let preview = content.count > 1500
                    ? String(content.prefix(1500)) + "\n… (tronqué)"
                    : content
                entries.append(DiagnosticEntry(
                    timestamp: Date(), category: .kerberos,
                    title: "Config MIT Kerberos trouvée (\(mitPath))",
                    detail: preview,
                    status: .info
                ))
            }
        }

        // Vérifier ~/Library/Preferences/edu.mit.Kerberos
        let userMitPath = NSHomeDirectory() + "/Library/Preferences/edu.mit.Kerberos"
        if FileManager.default.fileExists(atPath: userMitPath) {
            if let content = try? String(contentsOfFile: userMitPath, encoding: .utf8) {
                let preview = content.count > 1500
                    ? String(content.prefix(1500)) + "\n… (tronqué)"
                    : content
                entries.append(DiagnosticEntry(
                    timestamp: Date(), category: .kerberos,
                    title: "Config MIT Kerberos utilisateur trouvée",
                    detail: preview,
                    status: .info
                ))
            }
        }

        return entries
    }

    // MARK: - Tickets Kerberos

    private static func diagnoseKerberosTickets() -> [DiagnosticEntry] {
        var entries: [DiagnosticEntry] = []

        // 1. klist (défaut)
        let (klistOut, klistErr, klistCode) = runCommand("/usr/bin/klist", arguments: [])
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .kerberos,
            title: "klist (cache par défaut) — code \(klistCode)",
            detail: formatCommandOutput(stdout: klistOut, stderr: klistErr),
            status: klistCode == 0 ? .success : .warning
        ))

        // 2. klist -l (lister tous les caches)
        let (klOut, klErr, klCode) = runCommand("/usr/bin/klist", arguments: ["-l"])
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .kerberos,
            title: "klist -l (tous les caches) — code \(klCode)",
            detail: formatCommandOutput(stdout: klOut, stderr: klErr),
            status: klCode == 0 ? .success : .warning
        ))

        // 3. klist -A (tous les tickets de tous les caches)
        let (kaOut, kaErr, kaCode) = runCommand("/usr/bin/klist", arguments: ["-A"])
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .kerberos,
            title: "klist -A (tous les tickets) — code \(kaCode)",
            detail: formatCommandOutput(stdout: kaOut, stderr: kaErr),
            status: kaCode == 0 ? .success : .warning
        ))

        // 4. klist --cache=API: (cache macOS natif — Ticket Viewer)
        let (apiOut, apiErr, apiCode) = runCommand("/usr/bin/klist", arguments: ["--cache=API:"])
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .kerberos,
            title: "klist --cache=API: (Ticket Viewer macOS) — code \(apiCode)",
            detail: formatCommandOutput(stdout: apiOut, stderr: apiErr),
            status: apiCode == 0 ? .success : .warning
        ))

        // 5. klist -v (verbose, cache par défaut)
        let (kvOut, kvErr, kvCode) = runCommand("/usr/bin/klist", arguments: ["-v"])
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .kerberos,
            title: "klist -v (verbose) — code \(kvCode)",
            detail: formatCommandOutput(stdout: kvOut, stderr: kvErr),
            status: kvCode == 0 ? .success : .warning
        ))

        // 6. Vérifier le cache type utilisé
        let (ccOut, _, _) = runCommand("/usr/bin/klist", arguments: ["--version"])
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .kerberos,
            title: "Version klist",
            detail: ccOut.isEmpty ? "(pas de sortie)" : ccOut,
            status: .info
        ))

        // 7. Analyser les résultats pour extraire le principal
        let principal = extractPrincipal(from: klistOut)
            ?? extractPrincipal(from: kaOut)
            ?? extractPrincipal(from: apiOut)
        if let principal = principal {
            entries.append(DiagnosticEntry(
                timestamp: Date(), category: .kerberos,
                title: "✅ Principal détecté : \(principal)",
                detail: "",
                status: .success
            ))
        } else {
            entries.append(DiagnosticEntry(
                timestamp: Date(), category: .kerberos,
                title: "Aucun principal Kerberos détecté",
                detail: "Le ticket est peut-être dans un cache non accessible à l'app (sandbox ?).\nEssayez : kinit utilisateur@DOMAINE dans le Terminal, ou vérifiez les entitlements de l'app.",
                status: .error
            ))
        }

        return entries
    }

    // MARK: - DNS

    private static func diagnoseDNS(domain: String) -> [DiagnosticEntry] {
        var entries: [DiagnosticEntry] = []

        // SRV _ldap._tcp
        let (srvOut, srvErr, srvCode) = runCommand("/usr/bin/dig", arguments: ["+short", "SRV", "_ldap._tcp.\(domain)"])
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .dns,
            title: "DNS SRV _ldap._tcp.\(domain) — code \(srvCode)",
            detail: formatCommandOutput(stdout: srvOut, stderr: srvErr),
            status: srvCode == 0 && !srvOut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .success : .warning
        ))

        // SRV _kerberos._tcp
        let (krbOut, krbErr, krbCode) = runCommand("/usr/bin/dig", arguments: ["+short", "SRV", "_kerberos._tcp.\(domain)"])
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .dns,
            title: "DNS SRV _kerberos._tcp.\(domain) — code \(krbCode)",
            detail: formatCommandOutput(stdout: krbOut, stderr: krbErr),
            status: krbCode == 0 && !krbOut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .success : .warning
        ))

        // SRV _kerberos._udp
        let (kuOut, kuErr, kuCode) = runCommand("/usr/bin/dig", arguments: ["+short", "SRV", "_kerberos._udp.\(domain)"])
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .dns,
            title: "DNS SRV _kerberos._udp.\(domain) — code \(kuCode)",
            detail: formatCommandOutput(stdout: kuOut, stderr: kuErr),
            status: kuCode == 0 && !kuOut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .success : .info
        ))

        // SRV _gc._tcp (Global Catalog)
        let (gcOut, gcErr, gcCode) = runCommand("/usr/bin/dig", arguments: ["+short", "SRV", "_gc._tcp.\(domain)"])
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .dns,
            title: "DNS SRV _gc._tcp.\(domain) (Global Catalog) — code \(gcCode)",
            detail: formatCommandOutput(stdout: gcOut, stderr: gcErr),
            status: gcCode == 0 && !gcOut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .success : .info
        ))

        // TXT _kerberos (realm)
        let (txtOut, txtErr, txtCode) = runCommand("/usr/bin/dig", arguments: ["+short", "TXT", "_kerberos.\(domain)"])
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .dns,
            title: "DNS TXT _kerberos.\(domain) (realm) — code \(txtCode)",
            detail: formatCommandOutput(stdout: txtOut, stderr: txtErr),
            status: txtCode == 0 && !txtOut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .success : .info
        ))

        // Résolution simple du domaine
        let (nsOut, nsErr, nsCode) = runCommand("/usr/bin/dig", arguments: ["+short", domain])
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .dns,
            title: "Résolution DNS \(domain) — code \(nsCode)",
            detail: formatCommandOutput(stdout: nsOut, stderr: nsErr),
            status: nsCode == 0 && !nsOut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .success : .warning
        ))

        return entries
    }

    // MARK: - Réseau

    private static func diagnoseNetwork(server: String, domain: String) -> [DiagnosticEntry] {
        var entries: [DiagnosticEntry] = []

        let target = server.isEmpty ? domain : server

        // Ping basique (1 paquet, timeout 5s)
        let (pingOut, pingErr, pingCode) = runCommand("/sbin/ping", arguments: ["-c", "1", "-t", "5", target])
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .network,
            title: "Ping \(target) — code \(pingCode)",
            detail: formatCommandOutput(stdout: pingOut, stderr: pingErr),
            status: pingCode == 0 ? .success : .warning
        ))

        // Test de connectivité TCP port 389 (LDAP)
        let (nc389Out, nc389Err, nc389Code) = runCommand("/usr/bin/nc", arguments: ["-z", "-w", "5", target, "389"])
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .network,
            title: "TCP \(target):389 (LDAP) — code \(nc389Code)",
            detail: formatCommandOutput(stdout: nc389Out, stderr: nc389Err),
            status: nc389Code == 0 ? .success : .warning
        ))

        // Test TCP port 636 (LDAPS)
        let (nc636Out, nc636Err, nc636Code) = runCommand("/usr/bin/nc", arguments: ["-z", "-w", "5", target, "636"])
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .network,
            title: "TCP \(target):636 (LDAPS) — code \(nc636Code)",
            detail: formatCommandOutput(stdout: nc636Out, stderr: nc636Err),
            status: nc636Code == 0 ? .success : .info
        ))

        // Test TCP port 88 (Kerberos)
        let (nc88Out, nc88Err, nc88Code) = runCommand("/usr/bin/nc", arguments: ["-z", "-w", "5", target, "88"])
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .network,
            title: "TCP \(target):88 (Kerberos) — code \(nc88Code)",
            detail: formatCommandOutput(stdout: nc88Out, stderr: nc88Err),
            status: nc88Code == 0 ? .success : .warning
        ))

        // Test TCP port 3268 (Global Catalog)
        let (nc3268Out, nc3268Err, nc3268Code) = runCommand("/usr/bin/nc", arguments: ["-z", "-w", "5", target, "3268"])
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .network,
            title: "TCP \(target):3268 (Global Catalog) — code \(nc3268Code)",
            detail: formatCommandOutput(stdout: nc3268Out, stderr: nc3268Err),
            status: nc3268Code == 0 ? .success : .info
        ))

        return entries
    }

    // MARK: - Test LDAP

    private static func diagnoseLDAP(domain: String, server: String) -> [DiagnosticEntry] {
        var entries: [DiagnosticEntry] = []

        let target = server.isEmpty ? domain : server
        let baseDN = domain.split(separator: ".").map { "DC=\($0)" }.joined(separator: ",")

        // Test ldapsearch anonyme (RootDSE)
        let (rootOut, rootErr, rootCode) = runCommand("/usr/bin/ldapsearch", arguments: [
            "-H", "ldap://\(target)",
            "-x", "-b", "", "-s", "base",
            "-LLL",
            "defaultNamingContext", "dnsHostName", "serverName", "supportedSASLMechanisms"
        ])
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .ldap,
            title: "RootDSE anonyme ldap://\(target) — code \(rootCode)",
            detail: formatCommandOutput(stdout: rootOut, stderr: rootErr),
            status: rootCode == 0 ? .success : .warning
        ))

        // Test ldapsearch avec GSSAPI (si un ticket existe)
        let (gssOut, gssErr, gssCode) = runCommand("/usr/bin/ldapsearch", arguments: [
            "-H", "ldap://\(target)",
            "-Y", "GSSAPI", "-Q", "-N",
            "-b", baseDN, "-s", "base",
            "-LLL",
            "defaultNamingContext"
        ])
        entries.append(DiagnosticEntry(
            timestamp: Date(), category: .ldap,
            title: "LDAP GSSAPI ldap://\(target) — code \(gssCode)",
            detail: formatCommandOutput(stdout: gssOut, stderr: gssErr),
            status: gssCode == 0 ? .success : .error
        ))

        // Vérifier les mécanismes SASL supportés
        if rootCode == 0 {
            let saslMechs = rootOut.components(separatedBy: "\n")
                .filter { $0.lowercased().contains("supportedsaslmechanisms") }
                .map { $0.replacingOccurrences(of: "supportedSASLMechanisms: ", with: "", options: .caseInsensitive) }
            if !saslMechs.isEmpty {
                let hasGSSAPI = saslMechs.contains { $0.trimmingCharacters(in: .whitespaces) == "GSSAPI" }
                entries.append(DiagnosticEntry(
                    timestamp: Date(), category: .ldap,
                    title: hasGSSAPI ? "GSSAPI supporté par le serveur" : "GSSAPI NON listé dans les mécanismes SASL",
                    detail: "Mécanismes SASL : \(saslMechs.joined(separator: ", "))",
                    status: hasGSSAPI ? .success : .error
                ))
            }
        }

        return entries
    }

    // MARK: - Helpers

    /// Exécute une commande et capture stdout, stderr, exit code
    private static func runCommand(_ executable: String, arguments: [String]) -> (stdout: String, stderr: String, exitCode: Int32) {
        guard FileManager.default.fileExists(atPath: executable) else {
            return ("", "\(executable) introuvable", -1)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ("", "Erreur de lancement : \(error.localizedDescription)", -1)
        }

        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let out = String(data: outData, encoding: .utf8) ?? "(données binaires)"
        let err = String(data: errData, encoding: .utf8) ?? ""

        return (out, err, process.terminationStatus)
    }

    /// Formate la sortie d'une commande pour le log
    private static func formatCommandOutput(stdout: String, stderr: String) -> String {
        var lines: [String] = []
        let trimmedOut = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedErr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedOut.isEmpty {
            lines.append("stdout:")
            lines.append(trimmedOut)
        }
        if !trimmedErr.isEmpty {
            if !lines.isEmpty { lines.append("") }
            lines.append("stderr:")
            lines.append(trimmedErr)
        }
        if lines.isEmpty {
            lines.append("(aucune sortie)")
        }
        return lines.joined(separator: "\n")
    }

    /// Extrait le principal depuis la sortie de klist
    private static func extractPrincipal(from klistOutput: String) -> String? {
        for line in klistOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Format Heimdal macOS : "Principal: user@REALM"
            // Format MIT : "Default principal: user@REALM"
            let prefixes = ["default principal:", "principal:"]
            for prefix in prefixes {
                if trimmed.lowercased().hasPrefix(prefix) {
                    let principal = trimmed
                        .dropFirst(prefix.count)
                        .trimmingCharacters(in: .whitespaces)
                    if !principal.isEmpty {
                        return principal
                    }
                }
            }
        }
        return nil
    }
}
