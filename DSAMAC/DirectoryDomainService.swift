import Foundation
import Combine

@MainActor
final class DirectoryDomainService: ObservableObject {
    private let connector: DirectoryConnector

    @Published var rootOUTree: [OUNode] = []
    @Published var currentObjects: [DirectoryObjectSummary] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    init(connector: DirectoryConnector) {
        self.connector = connector
    }

    func loadTree() {
        do {
            let ous = try connector.fetchOUTree()
            self.rootOUTree = OUNode.buildTree(from: ous)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func selectContainer(_ selection: DirectoryContainerSelection?) {
        guard case let .organizationalUnit(ouID) = selection else {
            currentObjects = []
            return
        }

        do {
            let result = try connector.fetchObjects(in: ouID)
            currentObjects = DirectoryObjectSummary.from(users: result.users, groups: result.groups)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func search(_ query: String) {
        do {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Pas de recherche globale : on laisse la vue gérer l'affichage courant
                return
            }
            let results = try connector.searchObjects(query: query)
            // On convertit les résultats en summaries pour la liste
            self.currentObjects = results.map { result in
                switch result.kind {
                case .user:
                    return DirectoryObjectSummary(
                        id: result.id,
                        kind: .user,
                        primaryText: result.displayName,
                        secondaryText: result.secondaryText,
                        isDisabled: false,
                        isLocked: false
                    )
                case .group:
                    return DirectoryObjectSummary(
                        id: result.id,
                        kind: .group,
                        primaryText: result.displayName,
                        secondaryText: result.secondaryText,
                        isDisabled: false,
                        isLocked: false
                    )
                }
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func details(for selection: DirectoryObjectSelection?) -> (user: UserDescriptor?, group: GroupDescriptor?) {
        guard let selection else { return (nil, nil) }
        switch selection {
        case .user(let id):
            if let user = try? connector.searchObjects(query: "").compactMap({ result -> UserDescriptor? in
                return nil
            }) {
                _ = user
            }
            // Pour l'instant, on recherche simplement dans les objets chargés du dernier conteneur
            if case let .user(userID) = selection {
                if let summaryUser = currentObjects.first(where: { $0.id == userID && $0.kind == .user }) {
                    // On n'a pas tous les champs détaillés, mais on peut renvoyer une vue simplifiée via le summary
                    let descriptor = UserDescriptor(
                        id: summaryUser.id,
                        username: summaryUser.primaryText,
                        displayName: summaryUser.primaryText,
                        email: summaryUser.secondaryText,
                        phone: nil,
                        department: nil,
                        descriptionText: nil,
                        isEnabled: !summaryUser.isDisabled,
                        isLocked: summaryUser.isLocked,
                        ouID: UUID()
                    )
                    return (descriptor, nil)
                }
            }
        case .group(let id):
            if let summaryGroup = currentObjects.first(where: { $0.id == id && $0.kind == .group }) {
                let descriptor = GroupDescriptor(
                    id: summaryGroup.id,
                    name: summaryGroup.primaryText,
                    descriptionText: summaryGroup.secondaryText,
                    ouID: UUID(),
                    memberUserIDs: []
                )
                return (nil, descriptor)
            }
        }
        return (nil, nil)
    }
}

// MARK: - Helper models

struct OUNode: Identifiable, Hashable {
    let id: OUDescriptor.ID
    let name: String
    let children: [OUNode]? // optionnel pour être compatible avec OutlineGroup
}

extension OUNode {
    static func buildTree(from descriptors: [OUDescriptor]) -> [OUNode] {
        let byParent = Dictionary(grouping: descriptors, by: { $0.parentID })
        func build(parentID: OUDescriptor.ID?) -> [OUNode] {
            let children = byParent[parentID] ?? []
            return children.map { ou in
                OUNode(id: ou.id, name: ou.name, children: build(parentID: ou.id))
            }
        }
        return build(parentID: nil)
    }
}

struct DirectoryObjectSummary: Identifiable, Hashable {
    enum Kind: Hashable {
        case user
        case group
    }

    let id: UUID
    let kind: Kind
    let primaryText: String
    let secondaryText: String?
    let isDisabled: Bool
    let isLocked: Bool
}

extension DirectoryObjectSummary {
    static func from(users: [UserDescriptor], groups: [GroupDescriptor]) -> [DirectoryObjectSummary] {
        let userSummaries = users.map { user in
            DirectoryObjectSummary(
                id: user.id,
                kind: .user,
                primaryText: user.displayName.isEmpty ? user.username : user.displayName,
                secondaryText: user.email,
                isDisabled: !user.isEnabled,
                isLocked: user.isLocked
            )
        }

        let groupSummaries = groups.map { group in
            DirectoryObjectSummary(
                id: group.id,
                kind: .group,
                primaryText: group.name,
                secondaryText: group.descriptionText,
                isDisabled: false,
                isLocked: false
            )
        }

        return userSummaries + groupSummaries
    }
}

enum DirectoryContainerSelection: Hashable {
    case organizationalUnit(OUDescriptor.ID)
}

enum DirectoryObjectSelection: Hashable {
    case user(UUID)
    case group(UUID)
}
