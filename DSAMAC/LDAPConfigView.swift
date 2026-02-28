import SwiftUI

struct LDAPConfigView: View {
    @ObservedObject var connector: ActiveDirectoryConnector
    @State private var server: String = ""
    @State private var domain: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var error: String?
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Connexion LDAP au domaine Active Directory")
                .font(.title2)
                .bold()
                .padding(.top)
            Form {
                Section(header: Text("Paramètres LDAP")) {
                    TextField("Serveur AD (ex: dc01.example.local)", text: $server)
                    TextField("Nom du domaine (ex: example.local)", text: $domain)
                    TextField("Nom d'utilisateur (ex: admin@example.local)", text: $username)
                    SecureField("Mot de passe", text: $password)
                }
                if let error = error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            Button(action: connect) {
                Text("Se connecter au domaine AD")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
        }
        .padding()
    }
    
    private func connect() {
        guard !server.isEmpty, !domain.isEmpty, !username.isEmpty, !password.isEmpty else {
            error = "Tous les champs sont obligatoires."
            return
        }
        connector.needsManualConfig = false
        connector.ldapConfig = ActiveDirectoryConnector.LDAPConfig(
            server: server,
            domain: domain,
            username: username,
            password: password
        )
        error = nil
        // Relancer la connexion AD
        do {
            _ = try connector.fetchOUTree()
        } catch {
            self.error = error.localizedDescription
            connector.needsManualConfig = true
        }
    }
}

#if DEBUG
struct LDAPConfigView_Previews: PreviewProvider {
    static var previews: some View {
        LDAPConfigView(connector: ActiveDirectoryConnector())
    }
}
#endif
