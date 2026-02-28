import SwiftUI

struct DirectoryObjectDetailView: View {
    @ObservedObject var domainService: DirectoryDomainService
    let objectSelection: DirectoryObjectSelection?

    var body: some View {
        Group {
            if let selection = objectSelection {
                let details = domainService.details(for: selection)
                if let user = details.user {
                    UserDetailView(user: user)
                } else if let group = details.group {
                    GroupDetailView(group: group)
                } else if let computer = details.computer {
                    ComputerDetailView(computer: computer)
                } else {
                    emptyState("Aucun détail disponible")
                }
            } else {
                emptyState("Sélectionnez un utilisateur, groupe ou ordinateur")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func emptyState(_ message: String) -> some View {
        VStack {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Vue détail utilisateur type dsa.msc

struct UserDetailView: View {
    let user: UserDescriptor
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // En-tête avec nom et statut
            userHeader
            
            Divider()
            
            // Onglets type dsa.msc
            TabView(selection: $selectedTab) {
                generalTab
                    .tabItem { Label("Général", systemImage: "person.fill") }
                    .tag(0)
                
                accountTab
                    .tabItem { Label("Compte", systemImage: "key.fill") }
                    .tag(1)
                
                addressTab
                    .tabItem { Label("Adresse", systemImage: "location.fill") }
                    .tag(2)
                
                phonesTab
                    .tabItem { Label("Téléphones", systemImage: "phone.fill") }
                    .tag(3)
                
                organizationTab
                    .tabItem { Label("Organisation", systemImage: "building.2.fill") }
                    .tag(4)
                
                memberOfTab
                    .tabItem { Label("Membre de", systemImage: "person.3.fill") }
                    .tag(5)
                
                profileTab
                    .tabItem { Label("Profil", systemImage: "folder.fill") }
                    .tag(6)
            }
            .padding()
        }
    }
    
    // MARK: - En-tête utilisateur
    
    private var userHeader: some View {
        HStack(spacing: 16) {
            // Avatar avec statut
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(user.isEnabled ? .blue : .gray)
                
                // Badge de statut
                Circle()
                    .fill(statusColor)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: statusIcon)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(user.fullName)
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text(user.userPrincipalName ?? user.sAMAccountName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    StatusBadge(text: user.accountStatus, color: statusColor)
                    
                    if let title = user.title {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private var statusColor: Color {
        if !user.isEnabled { return .red }
        if user.isLocked { return .orange }
        return .green
    }
    
    private var statusIcon: String {
        if !user.isEnabled { return "xmark" }
        if user.isLocked { return "lock.fill" }
        return "checkmark"
    }
    
    // MARK: - Onglet Général
    
    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Identité") {
                    DetailGrid {
                        DetailRow(label: "Prénom", value: user.firstName)
                        DetailRow(label: "Nom", value: user.lastName)
                        DetailRow(label: "Nom complet", value: user.displayName)
                        DetailRow(label: "Description", value: user.description)
                    }
                }
                
                GroupBox("Contact") {
                    DetailGrid {
                        DetailRow(label: "Bureau", value: user.office)
                        DetailRow(label: "Email", value: user.email, icon: "envelope")
                        DetailRow(label: "Téléphone", value: user.telephone, icon: "phone")
                        DetailRow(label: "Page web", value: user.webPage, icon: "globe")
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Onglet Compte
    
    private var accountTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Identifiants de connexion") {
                    DetailGrid {
                        DetailRow(label: "Nom d'ouverture de session (pré-2000)", value: user.sAMAccountName)
                        DetailRow(label: "Nom d'utilisateur principal (UPN)", value: user.userPrincipalName)
                        DetailRow(label: "SID", value: user.objectSID, isMonospace: true)
                        DetailRow(label: "GUID", value: user.objectGUID, isMonospace: true)
                    }
                }
                
                GroupBox("État du compte") {
                    DetailGrid {
                        DetailRow(label: "Compte activé", value: user.isEnabled ? "Oui" : "Non", valueColor: user.isEnabled ? .green : .red)
                        DetailRow(label: "Compte verrouillé", value: user.isLocked ? "Oui" : "Non", valueColor: user.isLocked ? .red : .green)
                        DetailRow(label: "Expiration du compte", value: formatDate(user.accountExpires) ?? "Jamais")
                        DetailRow(label: "userAccountControl", value: user.userAccountControl.map { String($0) })
                    }
                }
                
                GroupBox("Mot de passe") {
                    DetailGrid {
                        DetailRow(label: "Dernier changement", value: formatDate(user.passwordLastSet))
                        DetailRow(label: "N'expire jamais", value: user.passwordNeverExpires ? "Oui" : "Non")
                        DetailRow(label: "Doit changer au prochain logon", value: user.mustChangePassword ? "Oui" : "Non")
                        DetailRow(label: "Ne peut pas changer", value: user.cannotChangePassword ? "Oui" : "Non")
                    }
                }
                
                GroupBox("Connexions") {
                    DetailGrid {
                        DetailRow(label: "Dernière connexion", value: formatDate(user.lastLogon))
                        DetailRow(label: "Nombre de connexions", value: user.logonCount.map { String($0) })
                        DetailRow(label: "Mauvais mots de passe", value: user.badPasswordCount.map { String($0) })
                        DetailRow(label: "Dernier mauvais mot de passe", value: formatDate(user.badPasswordTime))
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Onglet Adresse
    
    private var addressTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Adresse postale") {
                    DetailGrid {
                        DetailRow(label: "Rue", value: user.street)
                        DetailRow(label: "Boîte postale", value: user.poBox)
                        DetailRow(label: "Ville", value: user.city)
                        DetailRow(label: "État/Province", value: user.state)
                        DetailRow(label: "Code postal", value: user.postalCode)
                        DetailRow(label: "Pays", value: user.country)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Onglet Téléphones
    
    private var phonesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Numéros de téléphone") {
                    DetailGrid {
                        DetailRow(label: "Téléphone bureau", value: user.telephone, icon: "phone")
                        DetailRow(label: "Domicile", value: user.homePhone, icon: "phone.fill")
                        DetailRow(label: "Mobile", value: user.mobile, icon: "iphone")
                        DetailRow(label: "Fax", value: user.fax, icon: "faxmachine")
                        DetailRow(label: "Pager", value: user.pager, icon: "antenna.radiowaves.left.and.right")
                        DetailRow(label: "IP Phone", value: user.ipPhone, icon: "phone.connection")
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Onglet Organisation
    
    private var organizationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Poste") {
                    DetailGrid {
                        DetailRow(label: "Fonction", value: user.title)
                        DetailRow(label: "Service", value: user.department)
                        DetailRow(label: "Société", value: user.company)
                    }
                }
                
                GroupBox("Hiérarchie") {
                    DetailGrid {
                        DetailRow(label: "Responsable", value: user.managerDisplayName, icon: "person.fill")
                        if let managerDN = user.manager {
                            DetailRow(label: "DN du responsable", value: managerDN, isMonospace: true)
                        }
                    }
                }
                
                if !user.directReports.isEmpty {
                    GroupBox("Collaborateurs directs (\(user.directReports.count))") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(user.directReports, id: \.self) { report in
                                HStack {
                                    Image(systemName: "person.fill")
                                        .foregroundStyle(.secondary)
                                    Text(extractCN(from: report))
                                }
                                .font(.system(.body, design: .default))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Onglet Membre de
    
    private var memberOfTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Groupe principal") {
                    DetailGrid {
                        DetailRow(label: "Groupe", value: user.primaryGroup ?? "Domain Users")
                        DetailRow(label: "ID du groupe principal", value: user.primaryGroupID.map { String($0) })
                    }
                }
                
                GroupBox("Appartenance aux groupes (\(user.memberOf.count))") {
                    if user.memberOf.isEmpty {
                        Text("Aucun groupe supplémentaire")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(user.memberOf, id: \.self) { groupDN in
                                HStack {
                                    Image(systemName: "person.3.fill")
                                        .foregroundStyle(.blue)
                                    VStack(alignment: .leading) {
                                        Text(extractCN(from: groupDN))
                                            .fontWeight(.medium)
                                        Text(groupDN)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Onglet Profil
    
    private var profileTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Chemin du profil") {
                    DetailGrid {
                        DetailRow(label: "Profil", value: user.profilePath, icon: "folder")
                        DetailRow(label: "Script d'ouverture de session", value: user.scriptPath, icon: "doc.text")
                    }
                }
                
                GroupBox("Dossier de base") {
                    DetailGrid {
                        DetailRow(label: "Répertoire", value: user.homeDirectory, icon: "folder.fill")
                        DetailRow(label: "Lecteur", value: user.homeDrive)
                    }
                }
                
                GroupBox("Métadonnées") {
                    DetailGrid {
                        DetailRow(label: "DN", value: user.distinguishedName, isMonospace: true)
                        DetailRow(label: "Créé le", value: formatDate(user.whenCreated))
                        DetailRow(label: "Modifié le", value: formatDate(user.whenChanged))
                        DetailRow(label: "Classes d'objet", value: user.objectClass.joined(separator: ", "))
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: date)
    }
    
    private func extractCN(from dn: String) -> String {
        let components = dn.split(separator: ",")
        for component in components {
            let parts = component.split(separator: "=", maxSplits: 1)
            if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces).uppercased() == "CN" {
                return String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        return dn
    }
}

// MARK: - Vue détail groupe type dsa.msc

struct GroupDetailView: View {
    let group: GroupDescriptor
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // En-tête avec nom
            groupHeader
            
            Divider()
            
            // Onglets type dsa.msc
            TabView(selection: $selectedTab) {
                generalTab
                    .tabItem { Label("Général", systemImage: "person.3.fill") }
                    .tag(0)
                
                membersTab
                    .tabItem { Label("Membres", systemImage: "person.2.fill") }
                    .tag(1)
                
                memberOfTab
                    .tabItem { Label("Membre de", systemImage: "person.3.sequence.fill") }
                    .tag(2)
            }
            .padding()
        }
    }
    
    // MARK: - En-tête groupe
    
    private var groupHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 48))
                .foregroundStyle(group.groupType == .security ? .blue : .purple)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text(group.distinguishedName ?? group.sAMAccountName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    StatusBadge(text: group.groupType.rawValue, color: group.groupType == .security ? .blue : .purple)
                    StatusBadge(text: group.groupScope.rawValue, color: .gray)
                    Text("\(group.memberCount) membre(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Onglet Général
    
    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Informations générales") {
                    DetailGrid {
                        DetailRow(label: "Nom", value: group.name)
                        DetailRow(label: "Nom (pré-2000)", value: group.sAMAccountName)
                        DetailRow(label: "Description", value: group.description)
                        DetailRow(label: "Email", value: group.email, icon: "envelope")
                        DetailRow(label: "Notes", value: group.notes)
                    }
                }
                
                GroupBox("Type et étendue") {
                    DetailGrid {
                        DetailRow(label: "Type de groupe", value: group.groupType.rawValue)
                        DetailRow(label: "Étendue du groupe", value: group.groupScope.rawValue)
                    }
                }
                
                GroupBox("Identifiants") {
                    DetailGrid {
                        DetailRow(label: "SID", value: group.objectSID, isMonospace: true)
                        DetailRow(label: "GUID", value: group.objectGUID, isMonospace: true)
                        DetailRow(label: "DN", value: group.distinguishedName, isMonospace: true)
                    }
                }
                
                GroupBox("Gestion") {
                    DetailGrid {
                        DetailRow(label: "Géré par", value: group.managedByName, icon: "person.fill")
                        if let managedByDN = group.managedBy {
                            DetailRow(label: "DN du gestionnaire", value: managedByDN, isMonospace: true)
                        }
                    }
                }
                
                GroupBox("Métadonnées") {
                    DetailGrid {
                        DetailRow(label: "Créé le", value: formatDate(group.whenCreated))
                        DetailRow(label: "Modifié le", value: formatDate(group.whenChanged))
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Onglet Membres
    
    private var membersTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Membres du groupe (\(group.memberCount))") {
                    if group.members.isEmpty {
                        Text("Ce groupe n'a aucun membre")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(zip(group.members.indices, group.members)), id: \.0) { index, memberDN in
                                HStack {
                                    Image(systemName: "person.fill")
                                        .foregroundStyle(.blue)
                                    VStack(alignment: .leading) {
                                        Text(index < group.memberNames.count ? group.memberNames[index] : extractCN(from: memberDN))
                                            .fontWeight(.medium)
                                        Text(memberDN)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Onglet Membre de
    
    private var memberOfTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Ce groupe est membre de (\(group.memberOf.count))") {
                    if group.memberOf.isEmpty {
                        Text("Ce groupe n'appartient à aucun autre groupe")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(zip(group.memberOf.indices, group.memberOf)), id: \.0) { index, groupDN in
                                HStack {
                                    Image(systemName: "person.3.fill")
                                        .foregroundStyle(.purple)
                                    VStack(alignment: .leading) {
                                        Text(index < group.memberOfNames.count ? group.memberOfNames[index] : extractCN(from: groupDN))
                                            .fontWeight(.medium)
                                        Text(groupDN)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: date)
    }
    
    private func extractCN(from dn: String) -> String {
        let components = dn.split(separator: ",")
        for component in components {
            let parts = component.split(separator: "=", maxSplits: 1)
            if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces).uppercased() == "CN" {
                return String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        return dn
    }
}

// MARK: - Composants réutilisables

struct StatusBadge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

struct DetailGrid<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

struct DetailRow: View {
    let label: String
    let value: String?
    var icon: String? = nil
    var isMonospace: Bool = false
    var valueColor: Color? = nil
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":")
                .foregroundStyle(.secondary)
                .frame(width: 200, alignment: .trailing)
            
            if let value = value, !value.isEmpty {
                HStack(spacing: 4) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .foregroundStyle(.secondary)
                    }
                    Text(value)
                        .font(isMonospace ? .system(.body, design: .monospaced) : .body)
                        .foregroundColor(valueColor)
                        .textSelection(.enabled)
                }
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Vue détail ordinateur type dsa.msc

struct ComputerDetailView: View {
    let computer: ComputerDescriptor
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // En-tête
            computerHeader
            
            Divider()
            
            // Onglets type dsa.msc
            TabView(selection: $selectedTab) {
                generalTab
                    .tabItem { Label("Général", systemImage: "desktopcomputer") }
                    .tag(0)
                
                operatingSystemTab
                    .tabItem { Label("Système", systemImage: "cpu") }
                    .tag(1)
                
                accountTab
                    .tabItem { Label("Compte", systemImage: "key.fill") }
                    .tag(2)
                
                memberOfTab
                    .tabItem { Label("Membre de", systemImage: "person.3.fill") }
                    .tag(3)
                
                delegationTab
                    .tabItem { Label("Délégation", systemImage: "arrow.triangle.branch") }
                    .tag(4)
            }
            .padding()
        }
    }
    
    // MARK: - En-tête ordinateur
    
    private var computerHeader: some View {
        HStack(spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: computerIcon)
                    .font(.system(size: 48))
                    .foregroundStyle(computer.isEnabled ? .green : .gray)
                
                Circle()
                    .fill(computer.isEnabled ? .green : .red)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: computer.isEnabled ? "checkmark" : "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(computer.displayName)
                    .font(.title)
                    .fontWeight(.semibold)
                
                if let dnsName = computer.dnsHostName {
                    Text(dnsName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 8) {
                    StatusBadge(text: computer.computerType.rawValue, color: computerTypeColor)
                    StatusBadge(text: computer.accountStatus, color: computer.isEnabled ? .green : .red)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private var computerIcon: String {
        switch computer.computerType {
        case .workstation: return "desktopcomputer"
        case .server: return "server.rack"
        case .domainController: return "server.rack"
        case .unknown: return "pc"
        }
    }
    
    private var computerTypeColor: Color {
        switch computer.computerType {
        case .workstation: return .blue
        case .server: return .orange
        case .domainController: return .red
        case .unknown: return .gray
        }
    }
    
    // MARK: - Onglet Général
    
    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Identification") {
                    DetailGrid {
                        DetailRow(label: "Nom", value: computer.name)
                        DetailRow(label: "Nom DNS complet", value: computer.dnsHostName, icon: "network")
                        DetailRow(label: "Nom (pré-2000)", value: computer.sAMAccountName)
                        DetailRow(label: "Description", value: computer.description)
                        DetailRow(label: "Emplacement", value: computer.location, icon: "mappin")
                    }
                }
                
                GroupBox("Gestion") {
                    DetailGrid {
                        DetailRow(label: "Géré par", value: computer.managedByName, icon: "person.fill")
                        if let managedByDN = computer.managedBy {
                            DetailRow(label: "DN du gestionnaire", value: managedByDN, isMonospace: true)
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Onglet Système d'exploitation
    
    private var operatingSystemTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Système d'exploitation") {
                    DetailGrid {
                        DetailRow(label: "Système", value: computer.operatingSystem, icon: "desktopcomputer")
                        DetailRow(label: "Version", value: computer.operatingSystemVersion)
                        DetailRow(label: "Service Pack", value: computer.operatingSystemServicePack)
                    }
                }
                
                GroupBox("Type de machine") {
                    DetailGrid {
                        DetailRow(label: "Type", value: computer.computerType.rawValue)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Onglet Compte
    
    private var accountTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Identifiants") {
                    DetailGrid {
                        DetailRow(label: "SID", value: computer.objectSID, isMonospace: true)
                        DetailRow(label: "GUID", value: computer.objectGUID, isMonospace: true)
                        DetailRow(label: "DN", value: computer.distinguishedName, isMonospace: true)
                    }
                }
                
                GroupBox("État du compte") {
                    DetailGrid {
                        DetailRow(label: "Compte activé", value: computer.isEnabled ? "Oui" : "Non", valueColor: computer.isEnabled ? .green : .red)
                        DetailRow(label: "Expiration du compte", value: formatDate(computer.accountExpires) ?? "Jamais")
                        DetailRow(label: "userAccountControl", value: computer.userAccountControl.map { String($0) })
                    }
                }
                
                GroupBox("Connexions") {
                    DetailGrid {
                        DetailRow(label: "Dernière connexion", value: formatDate(computer.lastLogon))
                        DetailRow(label: "Nombre de connexions", value: computer.logonCount.map { String($0) })
                        DetailRow(label: "Dernier changement MDP", value: formatDate(computer.passwordLastSet))
                        DetailRow(label: "Mauvais mots de passe", value: computer.badPasswordCount.map { String($0) })
                        DetailRow(label: "Dernier mauvais MDP", value: formatDate(computer.badPasswordTime))
                    }
                }
                
                GroupBox("Métadonnées") {
                    DetailGrid {
                        DetailRow(label: "Créé le", value: formatDate(computer.whenCreated))
                        DetailRow(label: "Modifié le", value: formatDate(computer.whenChanged))
                        DetailRow(label: "Classes d'objet", value: computer.objectClass.joined(separator: ", "))
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Onglet Membre de
    
    private var memberOfTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Groupe principal") {
                    DetailGrid {
                        DetailRow(label: "Groupe", value: computer.primaryGroup ?? "Domain Computers")
                        DetailRow(label: "ID du groupe principal", value: computer.primaryGroupID.map { String($0) })
                    }
                }
                
                GroupBox("Appartenance aux groupes (\(computer.memberOf.count))") {
                    if computer.memberOf.isEmpty {
                        Text("Aucun groupe supplémentaire")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(zip(computer.memberOf.indices, computer.memberOf)), id: \.0) { index, groupDN in
                                HStack {
                                    Image(systemName: "person.3.fill")
                                        .foregroundStyle(.purple)
                                    VStack(alignment: .leading) {
                                        Text(index < computer.memberOfNames.count ? computer.memberOfNames[index] : extractCN(from: groupDN))
                                            .fontWeight(.medium)
                                        Text(groupDN)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Onglet Délégation
    
    private var delegationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Délégation") {
                    DetailGrid {
                        DetailRow(label: "Approuvé pour la délégation", value: computer.isTrustedForDelegation ? "Oui" : "Non", valueColor: computer.isTrustedForDelegation ? .orange : nil)
                    }
                    
                    if computer.isTrustedForDelegation {
                        Text("⚠️ Cet ordinateur est approuvé pour la délégation Kerberos. Cela peut présenter des risques de sécurité.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.top, 4)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: date)
    }
    
    private func extractCN(from dn: String) -> String {
        let components = dn.split(separator: ",")
        for component in components {
            let parts = component.split(separator: "=", maxSplits: 1)
            if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces).uppercased() == "CN" {
                return String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        return dn
    }
}
