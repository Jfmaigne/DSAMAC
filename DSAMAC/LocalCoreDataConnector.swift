import Foundation
import CoreData

/// Local implementation of DirectoryConnector backed by an in-memory model for now.
/// Later this can be wired to real Core Data entities.
final class LocalCoreDataConnector: DirectoryConnector {
    private let context: NSManagedObjectContext

    // In-memory storage simulating a small AD domain
    private var ous: [OUDescriptor] = []
    private var users: [UserDescriptor] = []
    private var groups: [GroupDescriptor] = []

    init(context: NSManagedObjectContext) {
        self.context = context
        bootstrapDemoDataIfNeeded()
    }

    private func bootstrapDemoDataIfNeeded() {
        guard ous.isEmpty else { return }

        // Root domain OU
        let rootID = UUID()
        let root = OUDescriptor(
            id: rootID,
            name: "example.local",
            parentID: nil,
            distinguishedName: "DC=example,DC=local"
        )

        // Child OUs
        let usersOU = OUDescriptor(
            id: UUID(),
            name: "Users",
            parentID: rootID,
            distinguishedName: "OU=Users,DC=example,DC=local"
        )
        let groupsOU = OUDescriptor(
            id: UUID(),
            name: "Groups",
            parentID: rootID,
            distinguishedName: "OU=Groups,DC=example,DC=local"
        )
        let itOU = OUDescriptor(
            id: UUID(),
            name: "IT",
            parentID: usersOU.id,
            distinguishedName: "OU=IT,OU=Users,DC=example,DC=local"
        )
        let hrOU = OUDescriptor(
            id: UUID(),
            name: "HR",
            parentID: usersOU.id,
            distinguishedName: "OU=HR,OU=Users,DC=example,DC=local"
        )

        ous = [root, usersOU, groupsOU, itOU, hrOU]

        // Demo users
        let user1 = UserDescriptor(
            id: UUID(),
            username: "jdoe",
            displayName: "John Doe",
            email: "jdoe@example.local",
            phone: "0102030405",
            department: "IT",
            descriptionText: "Admin système",
            isEnabled: true,
            isLocked: false,
            ouID: itOU.id
        )
        let user2 = UserDescriptor(
            id: UUID(),
            username: "asmith",
            displayName: "Alice Smith",
            email: "asmith@example.local",
            phone: "0607080910",
            department: "HR",
            descriptionText: "RH",
            isEnabled: true,
            isLocked: false,
            ouID: hrOU.id
        )

        users = [user1, user2]

        // Demo groups
        let adminsGroup = GroupDescriptor(
            id: UUID(),
            name: "Domain Admins",
            descriptionText: "Admins du domaine",
            ouID: groupsOU.id,
            memberUserIDs: [user1.id]
        )
        let hrGroup = GroupDescriptor(
            id: UUID(),
            name: "HR Staff",
            descriptionText: "Équipe RH",
            ouID: groupsOU.id,
            memberUserIDs: [user2.id]
        )

        groups = [adminsGroup, hrGroup]
    }

    // MARK: - Tree & listing

    func fetchOUTree() throws -> [OUDescriptor] {
        return ous
    }

    func fetchObjects(in ouID: OUDescriptor.ID) throws -> (users: [UserDescriptor], groups: [GroupDescriptor]) {
        let u = users.filter { $0.ouID == ouID }
        let g = groups.filter { $0.ouID == ouID }
        return (u, g)
    }

    func searchObjects(query: String) throws -> [DirectorySearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let lower = trimmed.lowercased()

        let matchedUsers = users.filter {
            $0.username.lowercased().contains(lower) ||
            $0.displayName.lowercased().contains(lower) ||
            ($0.email?.lowercased().contains(lower) ?? false)
        }.map {
            DirectorySearchResult(
                id: $0.id,
                kind: .user,
                displayName: $0.displayName.isEmpty ? $0.username : $0.displayName,
                secondaryText: $0.email
            )
        }

        let matchedGroups = groups.filter {
            $0.name.lowercased().contains(lower) ||
            ($0.descriptionText?.lowercased().contains(lower) ?? false)
        }.map {
            DirectorySearchResult(
                id: $0.id,
                kind: .group,
                displayName: $0.name,
                secondaryText: $0.descriptionText
            )
        }

        return matchedUsers + matchedGroups
    }
}
