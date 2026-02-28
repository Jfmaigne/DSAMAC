import Foundation
import CoreData

// MARK: - DTOs enrichis type dsa.msc

/// Unité d'Organisation (OU)
struct OUDescriptor: Identifiable, Hashable {
    typealias ID = UUID
    let id: ID
    let name: String
    let parentID: ID?
    let distinguishedName: String?
    let description: String?
    let whenCreated: Date?
    let whenChanged: Date?
}

/// Utilisateur AD complet (type dsa.msc)
struct UserDescriptor: Identifiable, Hashable {
    typealias ID = UUID
    let id: ID
    
    // Onglet Général
    let firstName: String?              // givenName
    let lastName: String?               // sn
    let displayName: String             // displayName
    let description: String?            // description
    let office: String?                 // physicalDeliveryOfficeName
    let telephone: String?              // telephoneNumber
    let email: String?                  // mail
    let webPage: String?                // wWWHomePage
    
    // Onglet Adresse
    let street: String?                 // streetAddress
    let poBox: String?                  // postOfficeBox
    let city: String?                   // l (locality)
    let state: String?                  // st
    let postalCode: String?             // postalCode
    let country: String?                // c / co
    
    // Onglet Compte
    let sAMAccountName: String          // sAMAccountName (login pré-Windows 2000)
    let userPrincipalName: String?      // userPrincipalName (login@domain)
    let objectSID: String?              // objectSid (SID)
    let userAccountControl: Int?        // userAccountControl (flags)
    let isEnabled: Bool                 // dérivé de userAccountControl
    let isLocked: Bool                  // lockoutTime
    let accountExpires: Date?           // accountExpires
    let passwordLastSet: Date?          // pwdLastSet
    let passwordNeverExpires: Bool      // dérivé de userAccountControl
    let mustChangePassword: Bool        // pwdLastSet == 0
    let cannotChangePassword: Bool      // dérivé de userAccountControl
    let lastLogon: Date?                // lastLogon / lastLogonTimestamp
    let logonCount: Int?                // logonCount
    let badPasswordCount: Int?          // badPwdCount
    let badPasswordTime: Date?          // badPasswordTime
    
    // Onglet Profil
    let profilePath: String?            // profilePath
    let scriptPath: String?             // scriptPath (logon script)
    let homeDirectory: String?          // homeDirectory
    let homeDrive: String?              // homeDrive
    
    // Onglet Téléphones
    let homePhone: String?              // homePhone
    let pager: String?                  // pager
    let mobile: String?                 // mobile
    let fax: String?                    // facsimileTelephoneNumber
    let ipPhone: String?                // ipPhone
    
    // Onglet Organisation
    let title: String?                  // title (fonction)
    let department: String?             // department
    let company: String?                // company
    let manager: String?                // manager (DN du manager)
    let managerDisplayName: String?     // nom lisible du manager
    let directReports: [String]         // directReports (DNs des subordonnés)
    
    // Onglet Membre de
    let memberOf: [String]              // memberOf (DNs des groupes)
    let primaryGroupID: Int?            // primaryGroupID
    let primaryGroup: String?           // nom du groupe principal
    
    // Métadonnées
    let distinguishedName: String?      // distinguishedName
    let objectGUID: String?             // objectGUID
    let whenCreated: Date?              // whenCreated
    let whenChanged: Date?              // whenChanged
    let objectClass: [String]           // objectClass
    
    let ouID: OUDescriptor.ID
    
    // Computed properties utiles
    var fullName: String {
        let fn = firstName ?? ""
        let ln = lastName ?? ""
        if fn.isEmpty && ln.isEmpty {
            return displayName.isEmpty ? sAMAccountName : displayName
        }
        return "\(fn) \(ln)".trimmingCharacters(in: .whitespaces)
    }
    
    var accountStatus: String {
        if !isEnabled { return "Désactivé" }
        if isLocked { return "Verrouillé" }
        return "Actif"
    }
}

/// Groupe AD complet (type dsa.msc)
struct GroupDescriptor: Identifiable, Hashable {
    typealias ID = UUID
    let id: ID
    
    // Onglet Général
    let name: String                    // name / cn
    let sAMAccountName: String          // sAMAccountName
    let description: String?            // description
    let email: String?                  // mail
    let notes: String?                  // info
    
    // Type et scope du groupe
    let groupType: GroupType
    let groupScope: GroupScope
    
    // Identifiants
    let objectSID: String?              // objectSid
    let distinguishedName: String?      // distinguishedName
    let objectGUID: String?             // objectGUID
    
    // Membres
    let members: [String]               // member (DNs des membres)
    let memberNames: [String]           // noms lisibles des membres
    let memberCount: Int                // nombre de membres
    
    // Membre de
    let memberOf: [String]              // memberOf (DNs des groupes parents)
    let memberOfNames: [String]         // noms lisibles des groupes parents
    
    // Métadonnées
    let whenCreated: Date?              // whenCreated
    let whenChanged: Date?              // whenChanged
    let managedBy: String?              // managedBy (DN du gestionnaire)
    let managedByName: String?          // nom lisible du gestionnaire
    
    let ouID: OUDescriptor.ID
}

/// Compte ordinateur AD complet (type dsa.msc)
struct ComputerDescriptor: Identifiable, Hashable {
    typealias ID = UUID
    let id: ID
    
    // Onglet Général
    let name: String                    // cn / name
    let sAMAccountName: String          // sAMAccountName (généralement NAME$)
    let dnsHostName: String?            // dNSHostName
    let description: String?            // description
    let location: String?               // location
    
    // Type de machine
    let computerType: ComputerType      // dérivé de l'OS ou des attributs
    
    // Système d'exploitation
    let operatingSystem: String?        // operatingSystem
    let operatingSystemVersion: String? // operatingSystemVersion
    let operatingSystemServicePack: String? // operatingSystemServicePack
    
    // Onglet Compte
    let objectSID: String?              // objectSid
    let userAccountControl: Int?        // userAccountControl
    let isEnabled: Bool                 // dérivé de userAccountControl
    let accountExpires: Date?           // accountExpires
    let lastLogon: Date?                // lastLogon / lastLogonTimestamp
    let logonCount: Int?                // logonCount
    let badPasswordCount: Int?          // badPwdCount
    let badPasswordTime: Date?          // badPasswordTime
    let passwordLastSet: Date?          // pwdLastSet
    
    // Délégation
    let isTrustedForDelegation: Bool    // dérivé de userAccountControl
    
    // Onglet Membre de
    let memberOf: [String]              // memberOf (DNs des groupes)
    let memberOfNames: [String]         // noms lisibles des groupes
    let primaryGroupID: Int?            // primaryGroupID
    let primaryGroup: String?           // nom du groupe principal
    
    // Onglet Emplacement
    let managedBy: String?              // managedBy (DN du gestionnaire)
    let managedByName: String?          // nom lisible du gestionnaire
    
    // Métadonnées
    let distinguishedName: String?      // distinguishedName
    let objectGUID: String?             // objectGUID
    let whenCreated: Date?              // whenCreated
    let whenChanged: Date?              // whenChanged
    let objectClass: [String]           // objectClass
    
    let ouID: OUDescriptor.ID
    
    // Computed properties
    var displayName: String {
        // Retirer le $ final du sAMAccountName si présent
        let cleanName = name.hasSuffix("$") ? String(name.dropLast()) : name
        return cleanName.isEmpty ? sAMAccountName : cleanName
    }
    
    var accountStatus: String {
        if !isEnabled { return "Désactivé" }
        return "Actif"
    }
    
    var osInfo: String {
        var parts: [String] = []
        if let os = operatingSystem { parts.append(os) }
        if let ver = operatingSystemVersion { parts.append(ver) }
        if let sp = operatingSystemServicePack { parts.append(sp) }
        return parts.isEmpty ? "Inconnu" : parts.joined(separator: " ")
    }
}

/// Type d'ordinateur
enum ComputerType: String, Hashable {
    case workstation = "Poste de travail"
    case server = "Serveur"
    case domainController = "Contrôleur de domaine"
    case unknown = "Ordinateur"
    
    init(fromOS os: String?, userAccountControl: Int?) {
        let osLower = os?.lowercased() ?? ""
        let uac = userAccountControl ?? 0
        
        // Vérifier si c'est un contrôleur de domaine (bit 0x2000)
        if uac & 0x2000 != 0 {
            self = .domainController
        }
        // Vérifier si c'est un serveur (bit 0x1000 ou nom de l'OS)
        else if uac & 0x1000 != 0 || osLower.contains("server") {
            self = .server
        }
        // Sinon c'est un poste de travail
        else if osLower.contains("windows") || osLower.contains("mac") || osLower.contains("linux") {
            self = .workstation
        }
        else {
            self = .unknown
        }
    }
}

/// Type de groupe AD
enum GroupType: String, Hashable {
    case security = "Sécurité"
    case distribution = "Distribution"
    case unknown = "Inconnu"
    
    init(fromGroupType value: Int) {
        // Le bit 0x80000000 indique un groupe de sécurité
        if value < 0 || (value & 0x80000000) != 0 {
            self = .security
        } else {
            self = .distribution
        }
    }
}

/// Scope de groupe AD
enum GroupScope: String, Hashable {
    case domainLocal = "Domaine local"
    case global = "Global"
    case universal = "Universel"
    case unknown = "Inconnu"
    
    init(fromGroupType value: Int) {
        let scope = value & 0x0000000F
        switch scope {
        case 1: self = .global
        case 2: self = .domainLocal
        case 4: self = .global
        case 8: self = .universal
        default: self = .unknown
        }
    }
}

/// Résultat de recherche
struct DirectorySearchResult: Identifiable, Hashable {
    enum Kind: Hashable {
        case user
        case group
        case computer
        case ou
    }
    let id: UUID
    let kind: Kind
    let displayName: String
    let secondaryText: String?
    let distinguishedName: String?
}

// MARK: - Protocol (lecture uniquement)

protocol DirectoryConnector {
    /// Retourne l'ensemble des OU (le service se charge de construire l'arborescence)
    func fetchOUTree() throws -> [OUDescriptor]

    /// Retourne les utilisateurs, groupes et ordinateurs directement contenus dans une OU
    func fetchObjects(in ouID: OUDescriptor.ID) throws -> (users: [UserDescriptor], groups: [GroupDescriptor], computers: [ComputerDescriptor])

    /// Recherche globale d'objets (utilisateurs, groupes et ordinateurs)
    func searchObjects(query: String) throws -> [DirectorySearchResult]
    
    /// Récupère les détails complets d'un utilisateur
    func fetchUserDetails(id: UserDescriptor.ID) throws -> UserDescriptor?
    
    /// Récupère les détails complets d'un groupe
    func fetchGroupDetails(id: GroupDescriptor.ID) throws -> GroupDescriptor?
    
    /// Récupère les détails complets d'un ordinateur
    func fetchComputerDetails(id: ComputerDescriptor.ID) throws -> ComputerDescriptor?
    
    /// Récupère tous les utilisateurs
    func fetchAllUsers() throws -> [UserDescriptor]
    
    /// Récupère tous les groupes
    func fetchAllGroups() throws -> [GroupDescriptor]
    
    /// Récupère tous les ordinateurs
    func fetchAllComputers() throws -> [ComputerDescriptor]
}
