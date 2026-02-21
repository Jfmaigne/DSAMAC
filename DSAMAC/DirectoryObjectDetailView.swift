import SwiftUI

struct DirectoryObjectDetailView: View {
    @ObservedObject var domainService: DirectoryDomainService
    let objectSelection: DirectoryObjectSelection?

    var body: some View {
        Group {
            if let selection = objectSelection {
                let details = domainService.details(for: selection)
                if let user = details.user {
                    userDetail(user)
                } else if let group = details.group {
                    groupDetail(group)
                } else {
                    Text("Aucun détail disponible")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Sélectionnez un utilisateur ou un groupe")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func userDetail(_ user: UserDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(user.displayName.isEmpty ? user.username : user.displayName)
                .font(.title2)
            if let email = user.email {
                Label(email, systemImage: "envelope")
            }
            if let dept = user.department {
                Label(dept, systemImage: "building.2")
            }
            if let desc = user.descriptionText {
                Text(desc)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label(user.isEnabled ? "Activé" : "Désactivé", systemImage: user.isEnabled ? "checkmark.circle" : "xmark.circle")
                if user.isLocked {
                    Label("Verrouillé", systemImage: "lock.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func groupDetail(_ group: GroupDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.name)
                .font(.title2)
            if let desc = group.descriptionText {
                Text(desc)
                    .foregroundStyle(.secondary)
            }
            Text("Membres: \(group.memberUserIDs.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
