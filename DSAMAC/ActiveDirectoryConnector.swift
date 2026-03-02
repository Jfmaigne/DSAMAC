import Foundation
import Combine

// MARK: - Méthode de connexion AD

/// Les différentes méthodes de connexion sécurisée à un domaine Active Directory
enum ADConnectionMethod: String, CaseIterable, Identifiable {
    /// LDAP Simple Bind en clair – NON RECOMMANDÉ (port 389, aucun chiffrement)
    case simpleBind     = "LDAP Simple (non sécurisé)"
    /// LDAPS : TLS natif dès la connexion (port 636) – RECOMMANDÉ
    case ldaps          = "LDAPS (TLS natif, port 636)"
    /// StartTLS : connexion LDAP puis upgrade TLS (port 389) – RECOMMANDÉ
    case startTLS       = "StartTLS (port 389 + TLS)"
    /// Kerberos / GSSAPI : authentification Windows intégrée, sans mot de passe exposé
    case kerberos       = "Kerberos / GSSAPI (SSO)"

    var id: String { rawValue }

    /// Port par défaut selon la méthode
    var defaultPort: Int {
        switch self {
        case .simpleBind, .startTLS: return 389
        case .ldaps:                 return 636
        case .kerberos:              return 389
        }
    }

    /// Description de sécurité
    var securityDescription: String {
        switch self {
        case .simpleBind:
            return "⚠️ Credentials envoyés en clair. À éviter absolument en production."
        case .ldaps:
            return "✅ TLS natif depuis la connexion. Recommandé pour les environnements AD."
        case .startTLS:
            return "✅ Connexion LDAP puis upgrade TLS automatique. Compatible avec la plupart des AD."
        case .kerberos:
            return "✅ Authentification SSO Windows. Aucun mot de passe transmis sur le réseau."
        }
    }
}

// MARK: - Configuration LDAP enrichie

struct ADConnectionConfig {
    // Connexion
    var server: String
    var port: Int
    var domain: String
    var method: ADConnectionMethod

    // Credentials (non utilisés en mode Kerberos)
    var username: String
    var password: String

    // Options TLS (LDAPS / StartTLS)
    /// Ignorer les erreurs de certificat (auto-signé, etc.) – à n'activer qu'en dev/test
    var ignoreCertificateErrors: Bool
    /// Chemin vers un certificat CA personnalisé (PEM) – optionnel
    var caCertificatePath: String?

    // Kerberos
    /// Principal Kerberos explicite (ex: admin@EXAMPLE.LOCAL) – optionnel, sinon ticket courant
    var kerberosPrincipal: String?

    init(
        server: String,
        domain: String,
        method: ADConnectionMethod = .ldaps,
        username: String = "",
        password: String = "",
        port: Int? = nil,
        ignoreCertificateErrors: Bool = false,
        caCertificatePath: String? = nil,
        kerberosPrincipal: String? = nil
    ) {
        self.server = server
        self.domain = domain
        self.method = method
        self.username = username
        self.password = password
        self.port = port ?? method.defaultPort
        self.ignoreCertificateErrors = ignoreCertificateErrors
        self.caCertificatePath = caCertificatePath
        self.kerberosPrincipal = kerberosPrincipal
    }
}

// MARK: - Connecteur AD

/// Implémentation lecture seule de DirectoryConnector qui interroge un domaine AD réel.
/// Supporte LDAPS, StartTLS, Kerberos/GSSAPI et (à éviter) Simple Bind.
/// Si le Mac est joint au domaine, utilise dscl automatiquement.
final class ActiveDirectoryConnector: DirectoryConnector, ObservableObject {

    // Rétrocompatibilité : accès à la config via l'ancienne propriété
    struct LDAPConfig {
        let server: String
        let domain: String
        let username: String
        let password: String
    }

    /// Config complète (méthode sécurisée + credentials)
    public var adConfig: ADConnectionConfig?

    /// Rétrocompatibilité
    public var ldapConfig: LDAPConfig? {
        get {
            guard let cfg = adConfig else { return nil }
            return LDAPConfig(server: cfg.server, domain: cfg.domain,
                              username: cfg.username, password: cfg.password)
        }
        set {
            if let lc = newValue {
                adConfig = ADConnectionConfig(
                    server: lc.server, domain: lc.domain,
                    method: .ldaps,
                    username: lc.username, password: lc.password
                )
            } else {
                adConfig = nil
            }
        }
    }
    
    // MARK: - Cache et état
    
    private var cachedUsers: [UserDescriptor] = []
    private var cachedGroups: [GroupDescriptor] = []
    private var cachedComputers: [ComputerDescriptor] = []
    private var cachedOUs: [OUDescriptor] = []
    private var rootOUID: OUDescriptor.ID = UUID()
    private var adNodePath: String?
    private var hasFetched = false
    
    @Published var needsManualConfig: Bool = false
    
    // MARK: - DirectoryConnector Protocol
    
    func fetchOUTree() throws -> [OUDescriptor] {
        try ensureDataFetched()
        return cachedOUs
    }
    
    func fetchObjects(in ouID: OUDescriptor.ID) throws -> (users: [UserDescriptor], groups: [GroupDescriptor], computers: [ComputerDescriptor]) {
        try ensureDataFetched()
        // Pour l'instant on retourne tous les objets car on n'a pas de vraie hiérarchie OU via dscl
        return (cachedUsers, cachedGroups, cachedComputers)
    }
    
    func searchObjects(query: String) throws -> [DirectorySearchResult] {
        try ensureDataFetched()
        let lower = query.lowercased()
        
        var results: [DirectorySearchResult] = []
        
        // Recherche dans les utilisateurs
        let matchedUsers = cachedUsers.filter { user in
            user.sAMAccountName.lowercased().contains(lower) ||
            user.displayName.lowercased().contains(lower) ||
            (user.userPrincipalName?.lowercased().contains(lower) ?? false) ||
            (user.email?.lowercased().contains(lower) ?? false) ||
            (user.firstName?.lowercased().contains(lower) ?? false) ||
            (user.lastName?.lowercased().contains(lower) ?? false) ||
            (user.department?.lowercased().contains(lower) ?? false)
        }
        
        results += matchedUsers.map { user in
            DirectorySearchResult(
                id: user.id,
                kind: .user,
                displayName: user.fullName,
                secondaryText: user.userPrincipalName ?? user.sAMAccountName,
                distinguishedName: user.distinguishedName
            )
        }
        
        // Recherche dans les groupes
        let matchedGroups = cachedGroups.filter { group in
            group.name.lowercased().contains(lower) ||
            group.sAMAccountName.lowercased().contains(lower) ||
            (group.description?.lowercased().contains(lower) ?? false)
        }
        
        results += matchedGroups.map { group in
            DirectorySearchResult(
                id: group.id,
                kind: .group,
                displayName: group.name,
                secondaryText: "\(group.groupScope.rawValue) - \(group.groupType.rawValue)",
                distinguishedName: group.distinguishedName
            )
        }
        
        // Recherche dans les ordinateurs
        let matchedComputers = cachedComputers.filter { computer in
            computer.name.lowercased().contains(lower) ||
            computer.sAMAccountName.lowercased().contains(lower) ||
            (computer.dnsHostName?.lowercased().contains(lower) ?? false) ||
            (computer.description?.lowercased().contains(lower) ?? false) ||
            (computer.operatingSystem?.lowercased().contains(lower) ?? false)
        }
        
        results += matchedComputers.map { computer in
            DirectorySearchResult(
                id: computer.id,
                kind: .computer,
                displayName: computer.displayName,
                secondaryText: computer.osInfo,
                distinguishedName: computer.distinguishedName
            )
        }
        
        return results
    }
    
    func fetchUserDetails(id: UserDescriptor.ID) throws -> UserDescriptor? {
        try ensureDataFetched()
        return cachedUsers.first { $0.id == id }
    }
    
    func fetchGroupDetails(id: GroupDescriptor.ID) throws -> GroupDescriptor? {
        try ensureDataFetched()
        return cachedGroups.first { $0.id == id }
    }
    
    func fetchComputerDetails(id: ComputerDescriptor.ID) throws -> ComputerDescriptor? {
        try ensureDataFetched()
        return cachedComputers.first { $0.id == id }
    }
    
    func fetchAllUsers() throws -> [UserDescriptor] {
        try ensureDataFetched()
        return cachedUsers
    }
    
    func fetchAllGroups() throws -> [GroupDescriptor] {
        try ensureDataFetched()
        return cachedGroups
    }
    
    func fetchAllComputers() throws -> [ComputerDescriptor] {
        try ensureDataFetched()
        return cachedComputers
    }
    
    // MARK: - Chargement des données
    
    private func ensureDataFetched() throws {
        guard !hasFetched else { return }

        if let cfg = adConfig {
            try loadViaADConfig(cfg)
        } else {
            do {
                let nodePath = try detectADNode()
                adNodePath = nodePath
                
                // Créer une OU racine représentant le domaine
                let domainName = extractDomainName(from: nodePath)
                rootOUID = UUID()
                let rootOU = OUDescriptor(
                    id: rootOUID,
                    name: domainName,
                    parentID: nil,
                    distinguishedName: nil,
                    description: "Domaine Active Directory",
                    whenCreated: nil,
                    whenChanged: nil
                )
                
                // Créer des pseudo-OUs pour organiser comme dsa.msc
                let usersOUID = UUID()
                let usersOU = OUDescriptor(
                    id: usersOUID,
                    name: "Utilisateurs",
                    parentID: rootOUID,
                    distinguishedName: nil,
                    description: "Tous les utilisateurs du domaine",
                    whenCreated: nil,
                    whenChanged: nil
                )
                
                let groupsOUID = UUID()
                let groupsOU = OUDescriptor(
                    id: groupsOUID,
                    name: "Groupes",
                    parentID: rootOUID,
                    distinguishedName: nil,
                    description: "Tous les groupes du domaine",
                    whenCreated: nil,
                    whenChanged: nil
                )
                
                let computersOUID = UUID()
                let computersOU = OUDescriptor(
                    id: computersOUID,
                    name: "Ordinateurs",
                    parentID: rootOUID,
                    distinguishedName: nil,
                    description: "Tous les ordinateurs du domaine",
                    whenCreated: nil,
                    whenChanged: nil
                )
                
                cachedOUs = [rootOU, usersOU, groupsOU, computersOU]
                
                // Charger les utilisateurs
                cachedUsers = try loadAllUsers(at: nodePath, ouID: usersOUID)
                
                // Charger les groupes
                cachedGroups = try loadAllGroups(at: nodePath, ouID: groupsOUID)
                
                // Charger les ordinateurs
                cachedComputers = try loadAllComputers(at: nodePath, ouID: computersOUID)
            } catch {
                // Si aucun domaine n'est détecté, signaler à l'UI qu'une config manuelle est nécessaire
                needsManualConfig = true
                throw NSError(domain: "AD", code: 1, userInfo: [NSLocalizedDescriptionKey: "Aucun domaine AD détecté. Veuillez saisir les paramètres LDAP."])
            }
        }
        
        hasFetched = true
    }
    
    private func extractDomainName(from nodePath: String) -> String {
        // Ex: "/Active Directory/CORP/All Domains" -> "CORP"
        let parts = nodePath.split(separator: "/")
        if parts.count >= 2 {
            return String(parts[1]) // "Active Directory" est parts[0], le domaine est parts[1]
        }
        return "AD Domain"
    }
    
    // MARK: - Détection du nœud AD
    
    private func detectADNode() throws -> String {
        // Utilise `dscl localhost -list "/Active Directory"` pour trouver le dossier de domaine
        let output = try runDSCL(["localhost", "-list", "/Active Directory"])
        let domainFolder = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        
        guard let domainFolder, !domainFolder.isEmpty else {
            throw NSError(domain: "AD", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Aucun domaine Active Directory trouvé. Assurez-vous que ce Mac est joint à un domaine AD."
            ])
        }
        
        return "/Active Directory/\(domainFolder)"
    }
    
    // MARK: - Chargement des utilisateurs
    
    private func loadAllUsers(at nodePath: String, ouID: OUDescriptor.ID) throws -> [UserDescriptor] {
        let usersPath = "\(nodePath)/All Domains/Users"
        
        // Lister tous les utilisateurs
        guard let rawList = try? runDSCL([usersPath, "-list", "."]) else {
            return []
        }
        
        let userNames = rawList
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var users: [UserDescriptor] = []
        
        for userName in userNames {
            if let user = try? loadUserDetails(userName: userName, basePath: usersPath, ouID: ouID) {
                users.append(user)
            }
        }
        
        return users.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
    
    private func loadUserDetails(userName: String, basePath: String, ouID: OUDescriptor.ID) throws -> UserDescriptor {
        let userPath = "\(basePath)/\(userName)"
        let attributes = try readAllAttributes(at: userPath)
        
        // Parser les attributs AD
        let firstName = attributes["dsAttrTypeNative:givenName"]?.first
        let lastName = attributes["dsAttrTypeNative:sn"]?.first
        let displayName = attributes["dsAttrTypeNative:displayName"]?.first ?? attributes["RealName"]?.first ?? userName
        let description = attributes["dsAttrTypeNative:description"]?.first
        let office = attributes["dsAttrTypeNative:physicalDeliveryOfficeName"]?.first
        let telephone = attributes["dsAttrTypeNative:telephoneNumber"]?.first
        let email = attributes["EMailAddress"]?.first ?? attributes["dsAttrTypeNative:mail"]?.first
        let webPage = attributes["dsAttrTypeNative:wWWHomePage"]?.first
        
        // Adresse
        let street = attributes["dsAttrTypeNative:streetAddress"]?.first
        let poBox = attributes["dsAttrTypeNative:postOfficeBox"]?.first
        let city = attributes["dsAttrTypeNative:l"]?.first
        let state = attributes["dsAttrTypeNative:st"]?.first
        let postalCode = attributes["dsAttrTypeNative:postalCode"]?.first
        let country = attributes["dsAttrTypeNative:c"]?.first ?? attributes["dsAttrTypeNative:co"]?.first
        
        // Compte
        let sAMAccountName = attributes["dsAttrTypeNative:sAMAccountName"]?.first ?? userName
        let userPrincipalName = attributes["dsAttrTypeNative:userPrincipalName"]?.first
        let objectSID = attributes["dsAttrTypeNative:objectSid"]?.first
        let userAccountControlStr = attributes["dsAttrTypeNative:userAccountControl"]?.first
        let userAccountControl = userAccountControlStr.flatMap { Int($0) }
        
        // Décodage des flags userAccountControl
        let isEnabled = !(userAccountControl.map { $0 & 0x0002 != 0 } ?? false) // ACCOUNTDISABLE
        let isLocked = attributes["dsAttrTypeNative:lockoutTime"]?.first.map { $0 != "0" } ?? false
        let passwordNeverExpires = userAccountControl.map { $0 & 0x10000 != 0 } ?? false // DONT_EXPIRE_PASSWORD
        let cannotChangePassword = userAccountControl.map { $0 & 0x0040 != 0 } ?? false // PASSWD_CANT_CHANGE
        
        // Dates
        let accountExpires = parseADDate(attributes["dsAttrTypeNative:accountExpires"]?.first)
        let passwordLastSet = parseADDate(attributes["dsAttrTypeNative:pwdLastSet"]?.first)
        let lastLogon = parseADDate(attributes["dsAttrTypeNative:lastLogon"]?.first) ?? parseADDate(attributes["dsAttrTypeNative:lastLogonTimestamp"]?.first)
        let whenCreated = parseGeneralizedTime(attributes["dsAttrTypeNative:whenCreated"]?.first)
        let whenChanged = parseGeneralizedTime(attributes["dsAttrTypeNative:whenChanged"]?.first)
        
        // Compteurs
        let logonCount = attributes["dsAttrTypeNative:logonCount"]?.first.flatMap { Int($0) }
        let badPasswordCount = attributes["dsAttrTypeNative:badPwdCount"]?.first.flatMap { Int($0) }
        let badPasswordTime = parseADDate(attributes["dsAttrTypeNative:badPasswordTime"]?.first)
        
        // Profil
        let profilePath = attributes["dsAttrTypeNative:profilePath"]?.first
        let scriptPath = attributes["dsAttrTypeNative:scriptPath"]?.first
        let homeDirectory = attributes["dsAttrTypeNative:homeDirectory"]?.first ?? attributes["NFSHomeDirectory"]?.first
        let homeDrive = attributes["dsAttrTypeNative:homeDrive"]?.first
        
        // Téléphones
        let homePhone = attributes["dsAttrTypeNative:homePhone"]?.first
        let pager = attributes["dsAttrTypeNative:pager"]?.first
        let mobile = attributes["dsAttrTypeNative:mobile"]?.first
        let fax = attributes["dsAttrTypeNative:facsimileTelephoneNumber"]?.first
        let ipPhone = attributes["dsAttrTypeNative:ipPhone"]?.first
        
        // Organisation
        let title = attributes["dsAttrTypeNative:title"]?.first
        let department = attributes["dsAttrTypeNative:department"]?.first
        let company = attributes["dsAttrTypeNative:company"]?.first
        let manager = attributes["dsAttrTypeNative:manager"]?.first
        let managerDisplayName = manager.flatMap { extractCNFromDN($0) }
        let directReports = attributes["dsAttrTypeNative:directReports"] ?? []
        
        // Membre de
        let memberOf = attributes["dsAttrTypeNative:memberOf"] ?? []
        let primaryGroupIDStr = attributes["dsAttrTypeNative:primaryGroupID"]?.first
        let primaryGroupID = primaryGroupIDStr.flatMap { Int($0) }
        
        // Métadonnées
        let distinguishedName = attributes["dsAttrTypeNative:distinguishedName"]?.first
        let objectGUID = attributes["dsAttrTypeNative:objectGUID"]?.first ?? attributes["GeneratedUID"]?.first
        let objectClass = attributes["dsAttrTypeNative:objectClass"] ?? []
        
        // Déterminer si l'utilisateur doit changer son mot de passe
        let mustChangePassword = passwordLastSet == nil || (attributes["dsAttrTypeNative:pwdLastSet"]?.first == "0")
        
        return UserDescriptor(
            id: UUID(),
            firstName: firstName,
            lastName: lastName,
            displayName: displayName,
            description: description,
            office: office,
            telephone: telephone,
            email: email,
            webPage: webPage,
            street: street,
            poBox: poBox,
            city: city,
            state: state,
            postalCode: postalCode,
            country: country,
            sAMAccountName: sAMAccountName,
            userPrincipalName: userPrincipalName,
            objectSID: objectSID,
            userAccountControl: userAccountControl,
            isEnabled: isEnabled,
            isLocked: isLocked,
            accountExpires: accountExpires,
            passwordLastSet: passwordLastSet,
            passwordNeverExpires: passwordNeverExpires,
            mustChangePassword: mustChangePassword,
            cannotChangePassword: cannotChangePassword,
            lastLogon: lastLogon,
            logonCount: logonCount,
            badPasswordCount: badPasswordCount,
            badPasswordTime: badPasswordTime,
            profilePath: profilePath,
            scriptPath: scriptPath,
            homeDirectory: homeDirectory,
            homeDrive: homeDrive,
            homePhone: homePhone,
            pager: pager,
            mobile: mobile,
            fax: fax,
            ipPhone: ipPhone,
            title: title,
            department: department,
            company: company,
            manager: manager,
            managerDisplayName: managerDisplayName,
            directReports: directReports,
            memberOf: memberOf,
            primaryGroupID: primaryGroupID,
            primaryGroup: nil, // Sera résolu plus tard si besoin
            distinguishedName: distinguishedName,
            objectGUID: objectGUID,
            whenCreated: whenCreated,
            whenChanged: whenChanged,
            objectClass: objectClass,
            ouID: ouID
        )
    }
    
    // MARK: - Chargement des groupes
    
    private func loadAllGroups(at nodePath: String, ouID: OUDescriptor.ID) throws -> [GroupDescriptor] {
        let groupsPath = "\(nodePath)/All Domains/Groups"
        
        // Lister tous les groupes
        guard let rawList = try? runDSCL([groupsPath, "-list", "."]) else {
            return []
        }
        
        let groupNames = rawList
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var groups: [GroupDescriptor] = []
        
        for groupName in groupNames {
            if let group = try? loadGroupDetails(groupName: groupName, basePath: groupsPath, ouID: ouID) {
                groups.append(group)
            }
        }
        
        return groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private func loadGroupDetails(groupName: String, basePath: String, ouID: OUDescriptor.ID) throws -> GroupDescriptor {
        let groupPath = "\(basePath)/\(groupName)"
        let attributes = try readAllAttributes(at: groupPath)
        
        // Attributs généraux
        let name = attributes["RecordName"]?.first ?? groupName
        let sAMAccountName = attributes["dsAttrTypeNative:sAMAccountName"]?.first ?? groupName
        let description = attributes["dsAttrTypeNative:description"]?.first
        let email = attributes["dsAttrTypeNative:mail"]?.first
        let notes = attributes["dsAttrTypeNative:info"]?.first
        
        // Type et scope
        let groupTypeValue = attributes["dsAttrTypeNative:groupType"]?.first.flatMap { Int($0) } ?? 0
        let groupType = GroupType(fromGroupType: groupTypeValue)
        let groupScope = GroupScope(fromGroupType: groupTypeValue)
        
        // Identifiants
        let objectSID = attributes["dsAttrTypeNative:objectSid"]?.first
        let distinguishedName = attributes["dsAttrTypeNative:distinguishedName"]?.first
        let objectGUID = attributes["dsAttrTypeNative:objectGUID"]?.first ?? attributes["GeneratedUID"]?.first
        
        // Membres
        let members = attributes["dsAttrTypeNative:member"] ?? attributes["GroupMembership"] ?? []
        let memberNames = members.compactMap { extractCNFromDN($0) }
        
        // Membre de
        let memberOf = attributes["dsAttrTypeNative:memberOf"] ?? []
        let memberOfNames = memberOf.compactMap { extractCNFromDN($0) }
        
        // Métadonnées
        let whenCreated = parseGeneralizedTime(attributes["dsAttrTypeNative:whenCreated"]?.first)
        let whenChanged = parseGeneralizedTime(attributes["dsAttrTypeNative:whenChanged"]?.first)
        let managedBy = attributes["dsAttrTypeNative:managedBy"]?.first
        let managedByName = managedBy.flatMap { extractCNFromDN($0) }
        
        return GroupDescriptor(
            id: UUID(),
            name: name,
            sAMAccountName: sAMAccountName,
            description: description,
            email: email,
            notes: notes,
            groupType: groupType,
            groupScope: groupScope,
            objectSID: objectSID,
            distinguishedName: distinguishedName,
            objectGUID: objectGUID,
            members: members,
            memberNames: memberNames,
            memberCount: members.count,
            memberOf: memberOf,
            memberOfNames: memberOfNames,
            whenCreated: whenCreated,
            whenChanged: whenChanged,
            managedBy: managedBy,
            managedByName: managedByName,
            ouID: ouID
        )
    }
    
    // MARK: - Chargement des ordinateurs
    
    private func loadAllComputers(at nodePath: String, ouID: OUDescriptor.ID) throws -> [ComputerDescriptor] {
        let computersPath = "\(nodePath)/All Domains/Computers"
        
        // Lister tous les ordinateurs
        guard let rawList = try? runDSCL([computersPath, "-list", "."]) else {
            return []
        }
        
        let computerNames = rawList
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var computers: [ComputerDescriptor] = []
        
        for computerName in computerNames {
            if let computer = try? loadComputerDetails(computerName: computerName, basePath: computersPath, ouID: ouID) {
                computers.append(computer)
            }
        }
        
        return computers.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
    
    private func loadComputerDetails(computerName: String, basePath: String, ouID: OUDescriptor.ID) throws -> ComputerDescriptor {
        let computerPath = "\(basePath)/\(computerName)"
        let attributes = try readAllAttributes(at: computerPath)
        
        // Attributs généraux
        let name = attributes["RecordName"]?.first ?? computerName
        let sAMAccountName = attributes["dsAttrTypeNative:sAMAccountName"]?.first ?? computerName
        let dnsHostName = attributes["dsAttrTypeNative:dNSHostName"]?.first
        let description = attributes["dsAttrTypeNative:description"]?.first
        let location = attributes["dsAttrTypeNative:location"]?.first
        
        // Système d'exploitation
        let operatingSystem = attributes["dsAttrTypeNative:operatingSystem"]?.first
        let operatingSystemVersion = attributes["dsAttrTypeNative:operatingSystemVersion"]?.first
        let operatingSystemServicePack = attributes["dsAttrTypeNative:operatingSystemServicePack"]?.first
        
        // Compte
        let objectSID = attributes["dsAttrTypeNative:objectSid"]?.first
        let userAccountControlStr = attributes["dsAttrTypeNative:userAccountControl"]?.first
        let userAccountControl = userAccountControlStr.flatMap { Int($0) }
        
        // Décodage des flags
        let isEnabled = !(userAccountControl.map { $0 & 0x0002 != 0 } ?? false)
        let isTrustedForDelegation = userAccountControl.map { $0 & 0x80000 != 0 } ?? false
        
        // Type de machine
        let computerType = ComputerType(fromOS: operatingSystem, userAccountControl: userAccountControl)
        
        // Dates
        let accountExpires = parseADDate(attributes["dsAttrTypeNative:accountExpires"]?.first)
        let lastLogon = parseADDate(attributes["dsAttrTypeNative:lastLogon"]?.first) ?? parseADDate(attributes["dsAttrTypeNative:lastLogonTimestamp"]?.first)
        let passwordLastSet = parseADDate(attributes["dsAttrTypeNative:pwdLastSet"]?.first)
        let whenCreated = parseGeneralizedTime(attributes["dsAttrTypeNative:whenCreated"]?.first)
        let whenChanged = parseGeneralizedTime(attributes["dsAttrTypeNative:whenChanged"]?.first)
        
        // Compteurs
        let logonCount = attributes["dsAttrTypeNative:logonCount"]?.first.flatMap { Int($0) }
        let badPasswordCount = attributes["dsAttrTypeNative:badPwdCount"]?.first.flatMap { Int($0) }
        let badPasswordTime = parseADDate(attributes["dsAttrTypeNative:badPasswordTime"]?.first)
        
        // Membre de
        let memberOf = attributes["dsAttrTypeNative:memberOf"] ?? []
        let memberOfNames = memberOf.compactMap { extractCNFromDN($0) }
        let primaryGroupIDStr = attributes["dsAttrTypeNative:primaryGroupID"]?.first
        let primaryGroupID = primaryGroupIDStr.flatMap { Int($0) }
        
        // Gestion
        let managedBy = attributes["dsAttrTypeNative:managedBy"]?.first
        let managedByName = managedBy.flatMap { extractCNFromDN($0) }
        
        // Métadonnées
        let distinguishedName = attributes["dsAttrTypeNative:distinguishedName"]?.first
        let objectGUID = attributes["dsAttrTypeNative:objectGUID"]?.first ?? attributes["GeneratedUID"]?.first
        let objectClass = attributes["dsAttrTypeNative:objectClass"] ?? []
        
        return ComputerDescriptor(
            id: UUID(),
            name: name,
            sAMAccountName: sAMAccountName,
            dnsHostName: dnsHostName,
            description: description,
            location: location,
            computerType: computerType,
            operatingSystem: operatingSystem,
            operatingSystemVersion: operatingSystemVersion,
            operatingSystemServicePack: operatingSystemServicePack,
            objectSID: objectSID,
            userAccountControl: userAccountControl,
            isEnabled: isEnabled,
            accountExpires: accountExpires,
            lastLogon: lastLogon,
            logonCount: logonCount,
            badPasswordCount: badPasswordCount,
            badPasswordTime: badPasswordTime,
            passwordLastSet: passwordLastSet,
            isTrustedForDelegation: isTrustedForDelegation,
            memberOf: memberOf,
            memberOfNames: memberOfNames,
            primaryGroupID: primaryGroupID,
            primaryGroup: nil,
            managedBy: managedBy,
            managedByName: managedByName,
            distinguishedName: distinguishedName,
            objectGUID: objectGUID,
            whenCreated: whenCreated,
            whenChanged: whenChanged,
            objectClass: objectClass,
            ouID: ouID
        )
    }
    
    // MARK: - Chargement via configuration AD (LDAPS / StartTLS / Kerberos / SimpleBind)

    private func loadViaADConfig(_ cfg: ADConnectionConfig) throws {
        let baseDN = domainToBaseDN(cfg.domain)

        // Créer les OUs virtuelles racine
        rootOUID = UUID()
        let rootOU = OUDescriptor(id: rootOUID, name: cfg.domain, parentID: nil,
                                  distinguishedName: baseDN, description: "Domaine Active Directory",
                                  whenCreated: nil, whenChanged: nil)

        let usersOUID = UUID()
        let usersOU = OUDescriptor(id: usersOUID, name: "Utilisateurs", parentID: rootOUID,
                                   distinguishedName: "CN=Users,\(baseDN)", description: "Utilisateurs du domaine",
                                   whenCreated: nil, whenChanged: nil)

        let groupsOUID = UUID()
        let groupsOU = OUDescriptor(id: groupsOUID, name: "Groupes", parentID: rootOUID,
                                    distinguishedName: "CN=Groups,\(baseDN)", description: "Groupes du domaine",
                                    whenCreated: nil, whenChanged: nil)

        let computersOUID = UUID()
        let computersOU = OUDescriptor(id: computersOUID, name: "Ordinateurs", parentID: rootOUID,
                                       distinguishedName: "CN=Computers,\(baseDN)", description: "Ordinateurs du domaine",
                                       whenCreated: nil, whenChanged: nil)

        // Charger les vraies OUs depuis LDAP
        let realOUs = (try? ldapFetchOUs(config: cfg, baseDN: baseDN, parentID: rootOUID)) ?? []
        cachedOUs = [rootOU, usersOU, groupsOU, computersOU] + realOUs

        // Charger les objets
        cachedUsers     = try ldapFetchUsers(config: cfg, baseDN: baseDN, ouID: usersOUID)
        cachedGroups    = try ldapFetchGroups(config: cfg, baseDN: baseDN, ouID: groupsOUID)
        cachedComputers = try ldapFetchComputers(config: cfg, baseDN: baseDN, ouID: computersOUID)
    }

    // Rétrocompat : ancienne méthode appelée via l'ancien LDAPConfig
    private func loadViaLDAP(config: LDAPConfig) throws {
        let cfg = ADConnectionConfig(
            server: config.server, domain: config.domain,
            method: .ldaps,
            username: config.username, password: config.password
        )
        try loadViaADConfig(cfg)
    }

    /// Convertit "example.local" en "DC=example,DC=local"
    private func domainToBaseDN(_ domain: String) -> String {
        return domain.split(separator: ".")
            .map { "DC=\($0)" }
            .joined(separator: ",")
    }

    // MARK: - Fetch OUs via LDAP

    private func ldapFetchOUs(config: ADConnectionConfig, baseDN: String, parentID: UUID) throws -> [OUDescriptor] {
        let filter = "(objectClass=organizationalUnit)"
        let attrs = ["ou", "distinguishedName", "description", "whenCreated", "whenChanged"]
        let entries = try runLDAPSearch(config: config, baseDN: baseDN, filter: filter, attributes: attrs)

        return entries.compactMap { entry -> OUDescriptor? in
            guard let dn = entry["dn"]?.first, let name = entry["ou"]?.first else { return nil }
            return OUDescriptor(
                id: UUID(),
                name: name,
                parentID: parentID,
                distinguishedName: dn,
                description: entry["description"]?.first,
                whenCreated: parseGeneralizedTime(entry["whenCreated"]?.first),
                whenChanged: parseGeneralizedTime(entry["whenChanged"]?.first)
            )
        }.sorted { $0.name < $1.name }
    }

    // MARK: - Fetch Utilisateurs via LDAP

    private func ldapFetchUsers(config: ADConnectionConfig, baseDN: String, ouID: UUID) throws -> [UserDescriptor] {
        let filter = "(&(objectClass=user)(objectCategory=person)(!(objectClass=computer)))"
        let attrs = [
            "givenName", "sn", "displayName", "description", "physicalDeliveryOfficeName",
            "telephoneNumber", "mail", "wWWHomePage", "streetAddress", "postOfficeBox",
            "l", "st", "postalCode", "co", "c", "sAMAccountName", "userPrincipalName",
            "objectSid", "userAccountControl", "lockoutTime", "accountExpires", "pwdLastSet",
            "lastLogon", "lastLogonTimestamp", "logonCount", "badPwdCount", "badPasswordTime",
            "profilePath", "scriptPath", "homeDirectory", "homeDrive", "homePhone", "pager",
            "mobile", "facsimileTelephoneNumber", "ipPhone", "title", "department", "company",
            "manager", "directReports", "memberOf", "primaryGroupID", "distinguishedName",
            "objectGUID", "whenCreated", "whenChanged", "objectClass"
        ]
        let entries = try runLDAPSearch(config: config, baseDN: baseDN, filter: filter, attributes: attrs)

        return entries.compactMap { entry -> UserDescriptor? in
            guard let sam = entry["sAMAccountName"]?.first else { return nil }

            let uac = entry["userAccountControl"]?.first.flatMap { Int($0) }
            let isEnabled = !(uac.map { $0 & 0x0002 != 0 } ?? false)
            let isLocked = entry["lockoutTime"]?.first.map { $0 != "0" && $0 != "" } ?? false
            let pwdLastSet = parseADDate(entry["pwdLastSet"]?.first)
            let memberOf = entry["memberOf"] ?? []

            return UserDescriptor(
                id: UUID(),
                firstName: entry["givenName"]?.first,
                lastName: entry["sn"]?.first,
                displayName: entry["displayName"]?.first ?? sam,
                description: entry["description"]?.first,
                office: entry["physicalDeliveryOfficeName"]?.first,
                telephone: entry["telephoneNumber"]?.first,
                email: entry["mail"]?.first,
                webPage: entry["wWWHomePage"]?.first,
                street: entry["streetAddress"]?.first,
                poBox: entry["postOfficeBox"]?.first,
                city: entry["l"]?.first,
                state: entry["st"]?.first,
                postalCode: entry["postalCode"]?.first,
                country: entry["co"]?.first ?? entry["c"]?.first,
                sAMAccountName: sam,
                userPrincipalName: entry["userPrincipalName"]?.first,
                objectSID: entry["objectSid"]?.first,
                userAccountControl: uac,
                isEnabled: isEnabled,
                isLocked: isLocked,
                accountExpires: parseADDate(entry["accountExpires"]?.first),
                passwordLastSet: pwdLastSet,
                passwordNeverExpires: uac.map { $0 & 0x10000 != 0 } ?? false,
                mustChangePassword: entry["pwdLastSet"]?.first == "0",
                cannotChangePassword: uac.map { $0 & 0x0040 != 0 } ?? false,
                lastLogon: parseADDate(entry["lastLogon"]?.first) ?? parseADDate(entry["lastLogonTimestamp"]?.first),
                logonCount: entry["logonCount"]?.first.flatMap { Int($0) },
                badPasswordCount: entry["badPwdCount"]?.first.flatMap { Int($0) },
                badPasswordTime: parseADDate(entry["badPasswordTime"]?.first),
                profilePath: entry["profilePath"]?.first,
                scriptPath: entry["scriptPath"]?.first,
                homeDirectory: entry["homeDirectory"]?.first,
                homeDrive: entry["homeDrive"]?.first,
                homePhone: entry["homePhone"]?.first,
                pager: entry["pager"]?.first,
                mobile: entry["mobile"]?.first,
                fax: entry["facsimileTelephoneNumber"]?.first,
                ipPhone: entry["ipPhone"]?.first,
                title: entry["title"]?.first,
                department: entry["department"]?.first,
                company: entry["company"]?.first,
                manager: entry["manager"]?.first,
                managerDisplayName: entry["manager"]?.first.flatMap { extractCNFromDN($0) },
                directReports: entry["directReports"] ?? [],
                memberOf: memberOf,
                primaryGroupID: entry["primaryGroupID"]?.first.flatMap { Int($0) },
                primaryGroup: nil,
                distinguishedName: entry["dn"]?.first,
                objectGUID: entry["objectGUID"]?.first,
                whenCreated: parseGeneralizedTime(entry["whenCreated"]?.first),
                whenChanged: parseGeneralizedTime(entry["whenChanged"]?.first),
                objectClass: entry["objectClass"] ?? [],
                ouID: ouID
            )
        }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - Fetch Groupes via LDAP

    private func ldapFetchGroups(config: ADConnectionConfig, baseDN: String, ouID: UUID) throws -> [GroupDescriptor] {
        let filter = "(objectClass=group)"
        let attrs = [
            "cn", "sAMAccountName", "description", "mail", "info",
            "groupType", "objectSid", "distinguishedName", "objectGUID",
            "member", "memberOf", "whenCreated", "whenChanged", "managedBy"
        ]
        let entries = try runLDAPSearch(config: config, baseDN: baseDN, filter: filter, attributes: attrs)

        return entries.compactMap { entry -> GroupDescriptor? in
            guard let name = entry["cn"]?.first ?? entry["sAMAccountName"]?.first else { return nil }
            let sam = entry["sAMAccountName"]?.first ?? name
            let gtVal = entry["groupType"]?.first.flatMap { Int($0) } ?? 0
            let members = entry["member"] ?? []

            return GroupDescriptor(
                id: UUID(),
                name: name,
                sAMAccountName: sam,
                description: entry["description"]?.first,
                email: entry["mail"]?.first,
                notes: entry["info"]?.first,
                groupType: GroupType(fromGroupType: gtVal),
                groupScope: GroupScope(fromGroupType: gtVal),
                objectSID: entry["objectSid"]?.first,
                distinguishedName: entry["dn"]?.first,
                objectGUID: entry["objectGUID"]?.first,
                members: members,
                memberNames: members.compactMap { extractCNFromDN($0) },
                memberCount: members.count,
                memberOf: entry["memberOf"] ?? [],
                memberOfNames: (entry["memberOf"] ?? []).compactMap { extractCNFromDN($0) },
                whenCreated: parseGeneralizedTime(entry["whenCreated"]?.first),
                whenChanged: parseGeneralizedTime(entry["whenChanged"]?.first),
                managedBy: entry["managedBy"]?.first,
                managedByName: entry["managedBy"]?.first.flatMap { extractCNFromDN($0) },
                ouID: ouID
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Fetch Ordinateurs via LDAP

    private func ldapFetchComputers(config: ADConnectionConfig, baseDN: String, ouID: UUID) throws -> [ComputerDescriptor] {
        let filter = "(objectClass=computer)"
        let attrs = [
            "cn", "sAMAccountName", "dNSHostName", "description", "location",
            "operatingSystem", "operatingSystemVersion", "operatingSystemServicePack",
            "objectSid", "userAccountControl", "accountExpires", "lastLogon",
            "lastLogonTimestamp", "logonCount", "badPwdCount", "badPasswordTime",
            "pwdLastSet", "memberOf", "primaryGroupID", "managedBy",
            "distinguishedName", "objectGUID", "whenCreated", "whenChanged", "objectClass"
        ]
        let entries = try runLDAPSearch(config: config, baseDN: baseDN, filter: filter, attributes: attrs)

        return entries.compactMap { entry -> ComputerDescriptor? in
            guard let name = entry["cn"]?.first else { return nil }
            let sam = entry["sAMAccountName"]?.first ?? "\(name)$"
            let uac = entry["userAccountControl"]?.first.flatMap { Int($0) }
            let isEnabled = !(uac.map { $0 & 0x0002 != 0 } ?? false)
            let os = entry["operatingSystem"]?.first
            let memberOf = entry["memberOf"] ?? []

            return ComputerDescriptor(
                id: UUID(),
                name: name,
                sAMAccountName: sam,
                dnsHostName: entry["dNSHostName"]?.first,
                description: entry["description"]?.first,
                location: entry["location"]?.first,
                computerType: ComputerType(fromOS: os, userAccountControl: uac),
                operatingSystem: os,
                operatingSystemVersion: entry["operatingSystemVersion"]?.first,
                operatingSystemServicePack: entry["operatingSystemServicePack"]?.first,
                objectSID: entry["objectSid"]?.first,
                userAccountControl: uac,
                isEnabled: isEnabled,
                accountExpires: parseADDate(entry["accountExpires"]?.first),
                lastLogon: parseADDate(entry["lastLogon"]?.first) ?? parseADDate(entry["lastLogonTimestamp"]?.first),
                logonCount: entry["logonCount"]?.first.flatMap { Int($0) },
                badPasswordCount: entry["badPwdCount"]?.first.flatMap { Int($0) },
                badPasswordTime: parseADDate(entry["badPasswordTime"]?.first),
                passwordLastSet: parseADDate(entry["pwdLastSet"]?.first),
                isTrustedForDelegation: uac.map { $0 & 0x80000 != 0 } ?? false,
                memberOf: memberOf,
                memberOfNames: memberOf.compactMap { extractCNFromDN($0) },
                primaryGroupID: entry["primaryGroupID"]?.first.flatMap { Int($0) },
                primaryGroup: nil,
                managedBy: entry["managedBy"]?.first,
                managedByName: entry["managedBy"]?.first.flatMap { extractCNFromDN($0) },
                distinguishedName: entry["dn"]?.first,
                objectGUID: entry["objectGUID"]?.first,
                whenCreated: parseGeneralizedTime(entry["whenCreated"]?.first),
                whenChanged: parseGeneralizedTime(entry["whenChanged"]?.first),
                objectClass: entry["objectClass"] ?? [],
                ouID: ouID
            )
        }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - Exécution de ldapsearch (LDAPS / StartTLS / Kerberos / SimpleBind)

    /// Construit et exécute ldapsearch selon la méthode de connexion choisie.
    /// - LDAPS       : -H ldaps://server:636
    /// - StartTLS    : -H ldap://server:389 -ZZ
    /// - Kerberos    : -H ldap://server -Y GSSAPI  (pas de -D/-w)
    /// - SimpleBind  : -H ldap://server -x -D user -w pass  (NON RECOMMANDÉ)
    private func runLDAPSearch(config: ADConnectionConfig, baseDN: String, filter: String, attributes: [String]) throws -> [[String: [String]]] {

        var args: [String] = []

        // ── URL de connexion ──────────────────────────────────────────────────
        let port = config.port
        switch config.method {
        case .ldaps:
            args += ["-H", "ldaps://\(config.server):\(port)"]
        case .startTLS, .simpleBind, .kerberos:
            args += ["-H", "ldap://\(config.server):\(port)"]
        }

        // ── Gestion des certificats TLS ───────────────────────────────────────
        // ldapsearch utilise les variables d'environnement LDAPTLS_* ou le fichier ldaprc
        // On les passe via l'environnement du Process (voir runLDAPProcess)

        // ── StartTLS : upgrade de connexion en TLS ───────────────────────────
        if config.method == .startTLS {
            args += ["-ZZ"]   // -ZZ = StartTLS obligatoire (échoue si non supporté)
        }

        // ── Authentification ─────────────────────────────────────────────────
        switch config.method {
        case .kerberos:
            // GSSAPI : le ticket Kerberos courant est utilisé (kinit préalable si besoin)
            args += ["-Y", "GSSAPI"]
            if let principal = config.kerberosPrincipal, !principal.isEmpty {
                args += ["-U", principal]
            }

        case .ldaps, .startTLS:
            // Simple Bind mais sur canal chiffré → acceptable
            let bindDN = config.username.contains("@")
                ? config.username
                : "\(config.username)@\(config.domain)"
            args += ["-x", "-D", bindDN, "-w", config.password]

        case .simpleBind:
            // Simple Bind en clair – déconseillé mais gardé pour compatibilité
            let bindDN = config.username.contains("@")
                ? config.username
                : "\(config.username)@\(config.domain)"
            args += ["-x", "-D", bindDN, "-w", config.password]
        }

        // ── Requête LDAP ──────────────────────────────────────────────────────
        args += [
            "-b", baseDN,
            "-LLL",             // LDIF v1 sans commentaires
            "-o", "ldif-wrap=no",  // pas de retour à la ligne dans les valeurs
            filter
        ]
        args += attributes

        let output = try runLDAPProcess(config: config, arguments: args)
        return parseLDIF(output)
    }

    /// Lance /usr/bin/ldapsearch avec les bonnes variables d'environnement TLS
    private func runLDAPProcess(config: ADConnectionConfig, arguments: [String]) throws -> String {
        var env = ProcessInfo.processInfo.environment

        // Variables d'environnement OpenLDAP pour la gestion des certificats
        if config.ignoreCertificateErrors {
            // Désactiver la vérification du certificat serveur (dev/test uniquement)
            env["LDAPTLS_REQCERT"] = "never"
        } else if let caPath = config.caCertificatePath, !caPath.isEmpty {
            // Utiliser un CA personnalisé
            env["LDAPTLS_CACERT"] = caPath
            env["LDAPTLS_REQCERT"] = "demand"
        } else {
            // Comportement par défaut : vérification stricte
            env["LDAPTLS_REQCERT"] = "demand"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ldapsearch")
        process.arguments = arguments
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError  = stderr

        try process.run()
        process.waitUntilExit()

        let dataOut = stdout.fileHandleForReading.readDataToEndOfFile()
        let dataErr = stderr.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: dataOut, encoding: .utf8) ?? ""
        let err = String(data: dataErr, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            // Analyser le message d'erreur pour donner un retour précis
            let msg: String
            if err.contains("Can't contact LDAP server") {
                msg = "Impossible de contacter le serveur \(config.server):\(config.port). Vérifiez l'adresse et le port."
            } else if err.contains("Invalid credentials") {
                msg = "Identifiants incorrects. Vérifiez le nom d'utilisateur et le mot de passe."
            } else if err.contains("certificate") || err.contains("TLS") {
                msg = "Erreur de certificat TLS. Activez 'Ignorer les erreurs de certificat' pour un serveur avec certificat auto-signé."
            } else if err.contains("GSSAPI") || err.contains("Kerberos") {
                msg = "Erreur Kerberos/GSSAPI. Vérifiez que vous avez un ticket Kerberos valide (kinit)."
            } else {
                msg = err.isEmpty ? "ldapsearch a échoué (code \(process.terminationStatus))" : err
            }
            throw NSError(domain: "LDAP", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }

        return out
    }

    /// Parser le format LDIF retourné par ldapsearch
    private func parseLDIF(_ ldif: String) -> [[String: [String]]] {
        var results: [[String: [String]]] = []
        var current: [String: [String]] = [:]
        var currentKey: String?
        var currentValue: String = ""

        func flushKeyValue() {
            guard let key = currentKey, !currentValue.isEmpty else { return }
            let k = key.lowercased()
            if current[k] == nil { current[k] = [] }
            current[k]!.append(currentValue)
            currentKey = nil
            currentValue = ""
        }

        func flushEntry() {
            flushKeyValue()
            if !current.isEmpty {
                results.append(current)
                current = [:]
            }
        }

        for line in ldif.components(separatedBy: "\n") {
            // Ligne vide = séparateur d'entrée
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushEntry()
                continue
            }

            // Continuation d'une valeur multi-ligne (commence par espace ou tabulation)
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                currentValue += line.trimmingCharacters(in: .whitespaces)
                continue
            }

            // Nouvelle clé: valeur
            if let colonIdx = line.firstIndex(of: ":") {
                flushKeyValue()
                let key = String(line[..<colonIdx])
                var value = String(line[line.index(after: colonIdx)...])

                // Valeur base64 (:: indique du base64)
                if value.hasPrefix(": ") {
                    let b64 = String(value.dropFirst(2))
                    if let data = Data(base64Encoded: b64),
                       let decoded = String(data: data, encoding: .utf8) {
                        value = decoded
                    } else {
                        value = b64
                    }
                } else {
                    value = value.hasPrefix(" ") ? String(value.dropFirst()) : value
                }

                // La ligne "dn:" donne le DN de l'entrée
                if key.lowercased() == "dn" {
                    currentKey = "dn"
                    currentValue = value
                } else {
                    currentKey = key
                    currentValue = value
                }
            }
        }
        flushEntry()
        return results
    }

    // MARK: - Helpers dscl
    
    private func readAllAttributes(at path: String) throws -> [String: [String]] {
        let output = try runDSCL(["-plist", ".", "-read", path])
        
        // Parser le plist si possible
        if let data = output.data(using: .utf8),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            return parseAttributesFromPlist(plist)
        }
        
        // Sinon, parser le format texte standard
        return parseAttributesFromText(output)
    }
    
    private func parseAttributesFromPlist(_ plist: [String: Any]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        
        for (key, value) in plist {
            if let stringValue = value as? String {
                result[key] = [stringValue]
            } else if let arrayValue = value as? [String] {
                result[key] = arrayValue
            } else if let arrayValue = value as? [Any] {
                result[key] = arrayValue.compactMap { $0 as? String }
            }
        }
        
        return result
    }
    
    private func parseAttributesFromText(_ text: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        var currentKey: String?
        var currentValues: [String] = []
        
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineStr = String(line)
            
            if lineStr.hasPrefix(" ") || lineStr.hasPrefix("\t") {
                // Continuation de valeur multi-ligne
                let value = lineStr.trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    currentValues.append(value)
                }
            } else if let colonIndex = lineStr.firstIndex(of: ":") {
                // Nouvelle clé
                if let key = currentKey, !currentValues.isEmpty {
                    result[key] = currentValues
                }
                
                currentKey = String(lineStr[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let valueAfterColon = String(lineStr[lineStr.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                currentValues = valueAfterColon.isEmpty ? [] : [valueAfterColon]
            }
        }
        
        // Dernière clé
        if let key = currentKey, !currentValues.isEmpty {
            result[key] = currentValues
        }
        
        return result
    }
    
    private func runDSCL(_ arguments: [String]) throws -> String {
        return try runProcess("/usr/bin/dscl", arguments: arguments)
    }

    private func runProcess(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let dataOut = stdout.fileHandleForReading.readDataToEndOfFile()
        let dataErr = stderr.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: dataOut, encoding: .utf8) ?? ""
        let err = String(data: dataErr, encoding: .utf8) ?? ""

        if process.terminationStatus == 0 {
            return out
        } else {
            throw NSError(domain: "Process", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: err.isEmpty ? "\(executable) a échoué (code \(process.terminationStatus))" : err
            ])
        }
    }
    
    // MARK: - Parsing helpers
    
    private func parseADDate(_ value: String?) -> Date? {
        guard let value = value, !value.isEmpty, value != "0" else { return nil }
        
        // Les dates AD sont en "100-nanosecond intervals since January 1, 1601"
        guard let interval = Int64(value), interval > 0 else { return nil }
        
        // Convertir en timestamp Unix
        // Différence entre 1601 et 1970 en secondes: 11644473600
        let unixTimestamp = Double(interval) / 10_000_000 - 11644473600
        
        // Vérifier que la date est raisonnable (entre 1970 et 2100)
        if unixTimestamp > 0 && unixTimestamp < 4102444800 { // avant 2100
            return Date(timeIntervalSince1970: unixTimestamp)
        }
        
        return nil
    }
    
    private func parseGeneralizedTime(_ value: String?) -> Date? {
        guard let value = value, !value.isEmpty else { return nil }
        
        // Format: YYYYMMDDHHmmss.0Z
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss'.0Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        
        if let date = formatter.date(from: value) {
            return date
        }
        
        // Essayer sans les millisecondes
        formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        return formatter.date(from: value)
    }
    
    private func extractCNFromDN(_ dn: String) -> String? {
        // Extrait le CN (Common Name) d'un Distinguished Name
        // Ex: "CN=John Doe,OU=Users,DC=example,DC=com" -> "John Doe"
        let components = dn.split(separator: ",")
        for component in components {
            let parts = component.split(separator: "=", maxSplits: 1)
            if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces).uppercased() == "CN" {
                return String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
    
    // MARK: - Initialisation

    init(adConfig: ADConnectionConfig? = nil) {
        self.adConfig = adConfig
    }

    /// Réinitialise le cache pour forcer un rechargement complet au prochain fetch
    func resetCache() {
        hasFetched = false
        cachedUsers = []
        cachedGroups = []
        cachedComputers = []
        cachedOUs = []
        adNodePath = nil
    }
}
