import Foundation
import CoreData

// MARK: - DTOs

struct OUDescriptor: Identifiable, Hashable {
    typealias ID = UUID
    let id: ID
    let name: String
    let parentID: ID?
    let distinguishedName: String?
}

struct UserDescriptor: Identifiable, Hashable {
    typealias ID = UUID
    let id: ID
    let username: String
    let displayName: String
    let email: String?
    let phone: String?
    let department: String?
    let descriptionText: String?
    let isEnabled: Bool
    let isLocked: Bool
    let ouID: OUDescriptor.ID
}

struct GroupDescriptor: Identifiable, Hashable {
    typealias ID = UUID
    let id: ID
    let name: String
    let descriptionText: String?
    let ouID: OUDescriptor.ID
    let memberUserIDs: [UserDescriptor.ID]
}

struct DirectorySearchResult: Identifiable, Hashable {
    enum Kind: Hashable {
        case user
        case group
    }
    let id: UUID
    let kind: Kind
    let displayName: String
    let secondaryText: String?
}

// MARK: - Protocol (lecture uniquement)

protocol DirectoryConnector {
    /// Retourne l'ensemble des OU (le service se charge de construire l'arborescence)
    func fetchOUTree() throws -> [OUDescriptor]

    /// Retourne les utilisateurs et groupes directement contenus dans une OU
    func fetchObjects(in ouID: OUDescriptor.ID) throws -> (users: [UserDescriptor], groups: [GroupDescriptor])

    /// Recherche globale d'objets (utilisateurs et groupes)
    func searchObjects(query: String) throws -> [DirectorySearchResult]
}
