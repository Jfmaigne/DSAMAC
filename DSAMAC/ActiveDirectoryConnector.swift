import Foundation
import Combine

/// Implémentation lecture seule de DirectoryConnector qui interroge un domaine AD réel via l'outil `dscl`.
///
/// Cette implémentation suppose que le Mac est joint à un domaine Active Directory.
/// Elle lit tous les attributs utilisateurs, groupes et ordinateurs comme le ferait dsa.msc.
final class ActiveDirectoryConnector: DirectoryConnector, ObservableObject {
    // Configuration LDAP
    struct LDAPConfig {
        let server: String
        let domain: String
        let username: String
        let password: String
    }
    
    public var ldapConfig: LDAPConfig?
    
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
        
        if shouldUseLDAP() {
            // TODO: Implémenter la lecture LDAP ici
            // Utiliser ldapConfig pour se connecter et charger les objets
            // Charger les OUs, utilisateurs, groupes, ordinateurs via LDAP
            throw NSError(domain: "AD", code: 2, userInfo: [NSLocalizedDescriptionKey: "Lecture LDAP non encore implémentée."])
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
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
            throw NSError(domain: "DSCL", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: err.isEmpty ? "dscl failed with status \(process.terminationStatus)" : err
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
    
    // Ajout d'un initialiseur pour configurer le connecteur
    init(ldapConfig: LDAPConfig? = nil) {
        self.ldapConfig = ldapConfig
    }
    
    // Méthode utilitaire pour savoir si on doit utiliser dscl ou LDAP
    private func shouldUseLDAP() -> Bool {
        return ldapConfig != nil
    }
}
