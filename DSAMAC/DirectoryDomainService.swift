import Foundation
import Combine

@MainActor
final class DirectoryDomainService: ObservableObject {
    public var connector: DirectoryConnector

    @Published var rootOUTree: [OUNode] = []
    @Published var currentObjects: [DirectoryObjectSummary] = []
    @Published var allUsers: [UserDescriptor] = []
    @Published var allGroups: [GroupDescriptor] = []
    @Published var allComputers: [ComputerDescriptor] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    init(connector: DirectoryConnector) {
        self.connector = connector
    }

    func loadTree() {
        isLoading = true
        errorMessage = nil
        
        do {
            let ous = try connector.fetchOUTree()
            self.rootOUTree = OUNode.buildTree(from: ous)
            
            // Charger tous les objets en cache
            self.allUsers = try connector.fetchAllUsers()
            self.allGroups = try connector.fetchAllGroups()
            self.allComputers = try connector.fetchAllComputers()
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }

    func selectContainer(_ selection: DirectoryContainerSelection?) {
        guard case let .organizationalUnit(ouID) = selection else {
            currentObjects = []
            return
        }

        do {
            let result = try connector.fetchObjects(in: ouID)
            currentObjects = DirectoryObjectSummary.from(users: result.users, groups: result.groups, computers: result.computers)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func search(_ query: String) {
        do {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return
            }
            let results = try connector.searchObjects(query: query)
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
                case .computer:
                    return DirectoryObjectSummary(
                        id: result.id,
                        kind: .computer,
                        primaryText: result.displayName,
                        secondaryText: result.secondaryText,
                        isDisabled: false,
                        isLocked: false
                    )
                case .ou:
                    return DirectoryObjectSummary(
                        id: result.id,
                        kind: .user, // fallback
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

    func details(for selection: DirectoryObjectSelection?) -> (user: UserDescriptor?, group: GroupDescriptor?, computer: ComputerDescriptor?) {
        guard let selection else { return (nil, nil, nil) }
        
        switch selection {
        case .user(let id):
            if let user = allUsers.first(where: { $0.id == id }) {
                return (user, nil, nil)
            }
            if let user = try? connector.fetchUserDetails(id: id) {
                return (user, nil, nil)
            }
            return (nil, nil, nil)
            
        case .group(let id):
            if let group = allGroups.first(where: { $0.id == id }) {
                return (nil, group, nil)
            }
            if let group = try? connector.fetchGroupDetails(id: id) {
                return (nil, group, nil)
            }
            return (nil, nil, nil)
            
        case .computer(let id):
            if let computer = allComputers.first(where: { $0.id == id }) {
                return (nil, nil, computer)
            }
            if let computer = try? connector.fetchComputerDetails(id: id) {
                return (nil, nil, computer)
            }
            return (nil, nil, nil)
        }
    }
    
    func setConnector(_ newConnector: DirectoryConnector) {
        self.connector = newConnector
        loadTree()
    }
}

// MARK: - Helper models

struct OUNode: Identifiable, Hashable {
    let id: OUDescriptor.ID
    let name: String
    let children: [OUNode]?
}

extension OUNode {
    static func buildTree(from descriptors: [OUDescriptor]) -> [OUNode] {
        let byParent = Dictionary(grouping: descriptors, by: { $0.parentID })
        func build(parentID: OUDescriptor.ID?) -> [OUNode] {
            let children = byParent[parentID] ?? []
            return children.map { ou in
                let subChildren = build(parentID: ou.id)
                return OUNode(id: ou.id, name: ou.name, children: subChildren.isEmpty ? nil : subChildren)
            }
        }
        return build(parentID: nil)
    }
}

struct DirectoryObjectSummary: Identifiable, Hashable {
    enum Kind: Hashable {
        case user
        case group
        case computer
    }

    let id: UUID
    let kind: Kind
    let primaryText: String
    let secondaryText: String?
    let isDisabled: Bool
    let isLocked: Bool
}

extension DirectoryObjectSummary {
    static func from(users: [UserDescriptor], groups: [GroupDescriptor], computers: [ComputerDescriptor]) -> [DirectoryObjectSummary] {
        let userSummaries = users.map { user in
            DirectoryObjectSummary(
                id: user.id,
                kind: .user,
                primaryText: user.fullName,
                secondaryText: user.userPrincipalName ?? user.sAMAccountName,
                isDisabled: !user.isEnabled,
                isLocked: user.isLocked
            )
        }

        let groupSummaries = groups.map { group in
            DirectoryObjectSummary(
                id: group.id,
                kind: .group,
                primaryText: group.name,
                secondaryText: "\(group.groupScope.rawValue) - \(group.groupType.rawValue)",
                isDisabled: false,
                isLocked: false
            )
        }
        
        let computerSummaries = computers.map { computer in
            DirectoryObjectSummary(
                id: computer.id,
                kind: .computer,
                primaryText: computer.displayName,
                secondaryText: computer.osInfo,
                isDisabled: !computer.isEnabled,
                isLocked: false
            )
        }

        return userSummaries + groupSummaries + computerSummaries
    }
}

enum DirectoryContainerSelection: Hashable {
    case organizationalUnit(OUDescriptor.ID)
}

enum DirectoryObjectSelection: Hashable {
    case user(UUID)
    case group(UUID)
    case computer(UUID)
}
