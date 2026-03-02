import SwiftUI

struct LDAPConfigView: View {
    @ObservedObject var connector: ActiveDirectoryConnector

    // Champs de connexion
    @State private var server: String = ""
    @State private var domain: String = ""
    @State private var port: String = ""
    @State private var method: ADConnectionMethod = .ldaps
    @State private var username: String = ""
    @State private var password: String = ""

    // Options TLS
    @State private var ignoreCertErrors: Bool = false
    @State private var caCertPath: String = ""

    // Kerberos
    @State private var kerberosPrincipal: String = ""

    // État
    @State private var isConnecting: Bool = false
    @State private var errorMessage: String?
    @State private var showAdvanced: Bool = false

    var body: some View {
        VStack(spacing: 0) {

            // ── En-tête ───────────────────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connexion au domaine Active Directory")
                        .font(.title2).bold()
                    Text("Choisissez une méthode de connexion sécurisée")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(.regularMaterial)

            Divider()

            // ── Formulaire ────────────────────────────────────────────────────
            Form {

                // Section méthode de connexion
                Section {
                    Picker("Méthode", selection: $method) {
                        ForEach(ADConnectionMethod.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: method) { _, newMethod in
                        // Mettre à jour le port automatiquement si non modifié manuellement
                        let currentPort = Int(port) ?? 0
                        let oldDefaults = ADConnectionMethod.allCases.map { $0.defaultPort }
                        if oldDefaults.contains(currentPort) || port.isEmpty {
                            port = "\(newMethod.defaultPort)"
                        }
                    }

                    // Badge de sécurité
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: securityIcon)
                            .foregroundStyle(securityColor)
                        Text(method.securityDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                } header: {
                    Text("Méthode de connexion")
                }

                // Section serveur
                Section {
                    TextField("Serveur AD (ex: dc01.example.local)", text: $server)
                        .textContentType(.URL)
                    HStack {
                        TextField("Nom de domaine (ex: example.local)", text: $domain)
                        TextField("Port", text: $port)
                            .frame(width: 70)
                            .onAppear {
                                if port.isEmpty { port = "\(method.defaultPort)" }
                            }
                    }
                } header: {
                    Text("Serveur")
                }

                // Section credentials (masquée pour Kerberos)
                if method != .kerberos {
                    Section {
                        TextField("Nom d'utilisateur (ex: admin@example.local)", text: $username)
                            .textContentType(.username)
                        SecureField("Mot de passe", text: $password)
                            .textContentType(.password)
                    } header: {
                        Text("Identifiants")
                    } footer: {
                        if method == .simpleBind {
                            Label("Le mot de passe sera transmis en clair sur le réseau.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    }
                } else {
                    // Section Kerberos
                    Section {
                        TextField("Principal Kerberos (optionnel, ex: admin@EXAMPLE.LOCAL)", text: $kerberosPrincipal)
                            .textContentType(.username)
                    } header: {
                        Text("Kerberos / GSSAPI")
                    } footer: {
                        Text("Si votre Mac est joint au domaine, le ticket Kerberos courant sera utilisé automatiquement. Sinon, exécutez `kinit utilisateur@DOMAINE` dans le Terminal au préalable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Options avancées (certificats TLS)
                if method == .ldaps || method == .startTLS {
                    Section {
                        DisclosureGroup("Options TLS avancées", isExpanded: $showAdvanced) {
                            Toggle("Ignorer les erreurs de certificat", isOn: $ignoreCertErrors)
                            if ignoreCertErrors {
                                Label("À n'utiliser qu'en développement/test (certificat auto-signé).", systemImage: "exclamationmark.shield.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                            }
                            TextField("Chemin vers un CA personnalisé (PEM) – optionnel", text: $caCertPath)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }

                // Message d'erreur
                if let error = errorMessage {
                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.callout)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // ── Bouton de connexion ───────────────────────────────────────────
            HStack {
                Spacer()
                Button(action: connect) {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 6)
                    }
                    Text(isConnecting ? "Connexion en cours…" : "Se connecter")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConnecting || !isFormValid)
                .keyboardShortcut(.return)
                .padding()
            }
        }
        .frame(minWidth: 540, minHeight: 460)
    }

    // MARK: - Helpers

    private var isFormValid: Bool {
        guard !server.isEmpty, !domain.isEmpty else { return false }
        if method == .kerberos { return true }
        return !username.isEmpty && !password.isEmpty
    }

    private var securityIcon: String {
        switch method {
        case .simpleBind: return "exclamationmark.triangle.fill"
        case .ldaps, .startTLS, .kerberos: return "checkmark.shield.fill"
        }
    }

    private var securityColor: Color {
        switch method {
        case .simpleBind: return .orange
        case .ldaps, .startTLS, .kerberos: return .green
        }
    }

    // MARK: - Connexion

    private func connect() {
        errorMessage = nil
        isConnecting = true

        let portInt = Int(port) ?? method.defaultPort

        let cfg = ADConnectionConfig(
            server: server,
            domain: domain,
            method: method,
            username: username,
            password: password,
            port: portInt,
            ignoreCertificateErrors: ignoreCertErrors,
            caCertificatePath: caCertPath.isEmpty ? nil : caCertPath,
            kerberosPrincipal: kerberosPrincipal.isEmpty ? nil : kerberosPrincipal
        )

        // Capturer le connecteur explicitement
        let conn = connector
        Task {
            do {
                conn.adConfig = cfg
                conn.needsManualConfig = false
                conn.resetCache()
                _ = try conn.fetchOUTree()
                isConnecting = false
            } catch {
                isConnecting = false
                errorMessage = error.localizedDescription
                conn.needsManualConfig = true
            }
        }
    }
}

#if DEBUG
struct LDAPConfigView_Previews: PreviewProvider {
    static var previews: some View {
        LDAPConfigView(connector: ActiveDirectoryConnector(adConfig: nil))
    }
}
#endif
