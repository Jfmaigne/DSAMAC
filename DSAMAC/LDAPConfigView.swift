    import SwiftUI

struct LDAPConfigView: View {
    @ObservedObject var connector: ActiveDirectoryConnector
    /// Le service de domaine, pour recharger l'arbre après connexion réussie
    @ObservedObject var domainService: DirectoryDomainService

    // ── Champs de connexion ─────────────────────────────────────────────
    @State private var server: String = ""
    @State private var domain: String = ""
    @State private var port: String = ""
    @State private var method: ADConnectionMethod = .kerberos
    @State private var username: String = ""
    @State private var password: String = ""

    // ── Options TLS ─────────────────────────────────────────────────────
    @State private var ignoreCertErrors: Bool = false
    @State private var caCertPath: String = ""

    // ── Kerberos / GSSAPI ───────────────────────────────────────────────
    @State private var kerberosPrincipal: String = ""
    @State private var kerberosRealm: String = ""
    @State private var keytabPath: String = ""
    @State private var kerberosTicketPrincipal: String? = nil

    // ── Recherche LDAP ──────────────────────────────────────────────────
    @State private var searchBaseDN: String = ""
    @State private var useGlobalCatalog: Bool = false
    @State private var globalCatalogPort: String = ""

    // ── Options avancées ────────────────────────────────────────────────
    @State private var autoDetectServer: Bool = true
    @State private var connectionTimeout: String = "30"
    @State private var sizeLimit: String = "0"
    @State private var followReferrals: Bool = true
    @State private var pageSize: String = "1000"

    // ── État de l'interface ─────────────────────────────────────────────
    @State private var isConnecting: Bool = false
    @State private var errorMessage: String?
    @State private var showAdvanced: Bool = false
    @State private var showKerberosAdvanced: Bool = false
    @State private var showLDAPAdvanced: Bool = false
    @State private var showDiagnostic: Bool = false

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
                    Text("Configurez les paramètres de connexion à votre domaine AD")
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

                // ═══════════════════════════════════════════════════════════════
                // Section méthode de connexion
                // ═══════════════════════════════════════════════════════════════
                Section {
                    Picker("Méthode", selection: $method) {
                        ForEach(ADConnectionMethod.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: method) { _, newMethod in
                        let currentPort = Int(port) ?? 0
                        let oldDefaults = ADConnectionMethod.allCases.map { $0.defaultPort }
                        if oldDefaults.contains(currentPort) || port.isEmpty {
                            port = "\(newMethod.defaultPort)"
                        }
                        // En mode Kerberos, activer l'auto-détection par défaut
                        if newMethod == .kerberos && server.isEmpty {
                            autoDetectServer = true
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

                // ═══════════════════════════════════════════════════════════════
                // Section serveur & domaine
                // ═══════════════════════════════════════════════════════════════
                Section {
                    // Auto-détection DNS SRV
                    Toggle("Auto-détecter le serveur (DNS SRV)", isOn: $autoDetectServer)

                    if autoDetectServer {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(.blue)
                            Text("Le contrôleur de domaine sera détecté automatiquement via l'enregistrement DNS _ldap._tcp.\(domain.isEmpty ? "<domaine>" : domain)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }

                    if !autoDetectServer {
                        TextField("Serveur AD (ex: dc01.example.local)", text: $server)
                            .textContentType(.URL)
                    }

                    HStack {
                        TextField("Nom de domaine (ex: example.local)", text: $domain)
                            .onChange(of: domain) { _, newDomain in
                                // Auto-remplir le realm Kerberos
                                if kerberosRealm.isEmpty || kerberosRealm == kerberosRealm.uppercased() {
                                    kerberosRealm = newDomain.uppercased()
                                }
                                // Auto-remplir le Base DN
                                if searchBaseDN.isEmpty {
                                    // On ne force pas, l'utilisateur peut le saisir manuellement
                                }
                            }
                        if !useGlobalCatalog {
                            TextField("Port", text: $port)
                                .frame(width: 70)
                                .onAppear {
                                    if port.isEmpty { port = "\(method.defaultPort)" }
                                }
                        }
                    }

                    // Global Catalog
                    Toggle("Utiliser le Global Catalog (inter-domaines)", isOn: $useGlobalCatalog)
                    if useGlobalCatalog {
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                                .foregroundStyle(.blue)
                            Text("Port \(method == .ldaps ? "3269 (LDAPS)" : "3268 (LDAP)") – Recherche dans toute la forêt AD")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            TextField("Port GC", text: $globalCatalogPort)
                                .frame(width: 70)
                                .onAppear {
                                    if globalCatalogPort.isEmpty {
                                        globalCatalogPort = method == .ldaps ? "3269" : "3268"
                                    }
                                }
                        }
                    }
                } header: {
                    Text("Serveur")
                }

                // ═══════════════════════════════════════════════════════════════
                // Section Base DN de recherche
                // ═══════════════════════════════════════════════════════════════
                Section {
                    TextField("Base DN (ex: DC=example,DC=local)", text: $searchBaseDN)
                        .font(.system(.body, design: .monospaced))

                    if searchBaseDN.isEmpty && !domain.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.blue)
                            Text("Valeur déduite : \(domain.split(separator: ".").map { "DC=\($0)" }.joined(separator: ","))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Base de recherche LDAP")
                } footer: {
                    Text("Laissez vide pour déduire automatiquement du nom de domaine. Saisissez un DN spécifique pour limiter la recherche à une branche de l'arbre (ex: OU=Paris,DC=example,DC=local).")
                        .font(.caption2)
                }

                // ═══════════════════════════════════════════════════════════════
                // Section credentials (masquée pour Kerberos)
                // ═══════════════════════════════════════════════════════════════
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
                    // ═══════════════════════════════════════════════════════════
                    // Section Kerberos / GSSAPI
                    // ═══════════════════════════════════════════════════════════
                    Section {
                        // Statut du ticket Kerberos
                        HStack(spacing: 10) {
                            if let principal = kerberosTicketPrincipal {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Ticket Kerberos valide")
                                        .font(.callout).fontWeight(.medium)
                                    Text(principal)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Aucun ticket Kerberos détecté")
                                        .font(.callout).fontWeight(.medium)
                                    Text("Exécutez « kinit utilisateur@DOMAINE » dans le Terminal")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Vérifier") {
                                kerberosTicketPrincipal = ActiveDirectoryConnector.checkKerberosTicket()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 4)

                        TextField("Realm Kerberos (ex: EXAMPLE.LOCAL)", text: $kerberosRealm)
                            .font(.system(.body, design: .monospaced))

                        if kerberosRealm.isEmpty && !domain.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.blue)
                                Text("Valeur déduite : \(domain.uppercased())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Options Kerberos avancées
                        DisclosureGroup("Options Kerberos avancées", isExpanded: $showKerberosAdvanced) {
                            TextField("Principal Kerberos (optionnel, ex: admin@EXAMPLE.LOCAL)", text: $kerberosPrincipal)
                                .textContentType(.username)

                            TextField("Chemin vers un keytab (optionnel, ex: /etc/krb5.keytab)", text: $keytabPath)
                                .font(.system(.body, design: .monospaced))

                            if !keytabPath.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "key.fill")
                                        .foregroundStyle(.blue)
                                    Text("Le keytab sera utilisé pour l'authentification sans saisie de mot de passe. Utile pour les tâches automatisées.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        // Bouton diagnostic
                        Button {
                            showDiagnostic = true
                        } label: {
                            Label("Lancer le diagnostic complet…", systemImage: "stethoscope")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 4)

                    } header: {
                        Text("Kerberos / GSSAPI")
                    } footer: {
                        Text("Si votre Mac est joint au domaine, le ticket Kerberos courant sera utilisé automatiquement. Sinon, exécutez « kinit utilisateur@\(kerberosRealm.isEmpty ? "DOMAINE" : kerberosRealm) » dans le Terminal au préalable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // ═══════════════════════════════════════════════════════════════
                // Options TLS avancées (certificats)
                // ═══════════════════════════════════════════════════════════════
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

                // ═══════════════════════════════════════════════════════════════
                // Options LDAP avancées
                // ═══════════════════════════════════════════════════════════════
                Section {
                    DisclosureGroup("Options LDAP avancées", isExpanded: $showLDAPAdvanced) {
                        HStack {
                            Text("Timeout de connexion (sec)")
                            Spacer()
                            TextField("30", text: $connectionTimeout)
                                .frame(width: 60)
                                .multilineTextAlignment(.trailing)
                        }

                        HStack {
                            Text("Limite de résultats")
                            Spacer()
                            TextField("0 = illimité", text: $sizeLimit)
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                        }

                        HStack {
                            Text("Taille de page (paging)")
                            Spacer()
                            TextField("1000", text: $pageSize)
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                        }

                        Toggle("Suivre les referrals LDAP", isOn: $followReferrals)
                        if !followReferrals {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.blue)
                                Text("Désactiver si vous recevez des erreurs de referral. Utilisez plutôt le Global Catalog pour les recherches inter-domaines.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // ═══════════════════════════════════════════════════════════════
                // Message d'erreur
                // ═══════════════════════════════════════════════════════════════
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

                // ═══════════════════════════════════════════════════════════════
                // Bouton de connexion (dans le formulaire pour rester visible)
                // ═══════════════════════════════════════════════════════════════
                Section {
                    HStack {
                        Spacer()
                        Button(action: connect) {
                            HStack(spacing: 8) {
                                if isConnecting {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(isConnecting ? "Connexion en cours…" : "Se connecter")
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isConnecting || !isFormValid)
                        .keyboardShortcut(.return)
                        Spacer()
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 600, minHeight: 580)
        .onAppear {
            // Vérifier le ticket Kerberos au chargement
            kerberosTicketPrincipal = ActiveDirectoryConnector.checkKerberosTicket()
        }
        .sheet(isPresented: $showDiagnostic) {
            KerberosDiagnosticView(domain: domain, server: server)
        }
    }

    // MARK: - Helpers

    private var isFormValid: Bool {
        // Le domaine est toujours obligatoire
        if domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        // Le serveur est obligatoire sauf si auto-détection est activée
        if !autoDetectServer && server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        // En Kerberos, seul le domaine (+ serveur ou auto-detect) est requis
        if method == .kerberos {
            return true
        }
        // Pour les autres méthodes, username + password sont obligatoires
        return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
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
            kerberosPrincipal: kerberosPrincipal.isEmpty ? nil : kerberosPrincipal,
            kerberosRealm: kerberosRealm.isEmpty ? nil : kerberosRealm,
            keytabPath: keytabPath.isEmpty ? nil : keytabPath,
            searchBaseDN: searchBaseDN.isEmpty ? nil : searchBaseDN,
            useGlobalCatalog: useGlobalCatalog,
            globalCatalogPort: Int(globalCatalogPort),
            connectionTimeout: Int(connectionTimeout) ?? 30,
            sizeLimit: Int(sizeLimit) ?? 0,
            followReferrals: followReferrals,
            autoDetectServer: autoDetectServer,
            pageSize: Int(pageSize) ?? 1000
        )

        // 1. Configurer le connecteur
        connector.adConfig = cfg
        connector.resetCache()

        // 2. Lancer la connexion en tâche de fond
        let conn = connector
        let svc = domainService
        Task {
            do {
                // Tenter de charger les données — cela appelle ldapsearch
                _ = try conn.fetchOUTree()

                // Succès → la config manuelle n'est plus nécessaire
                conn.needsManualConfig = false

                // Recharger le service complet (arbre + objets)
                svc.loadTree()

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
        LDAPConfigView(
            connector: ActiveDirectoryConnector(adConfig: nil),
            domainService: DirectoryDomainService(connector: LocalCoreDataConnector(context: PersistenceController.shared.container.viewContext))
        )
    }
}
#endif
