import SwiftUI

struct DirectoryObjectListView: View {
    @ObservedObject var domainService: DirectoryDomainService
    let containerSelection: DirectoryContainerSelection?
    @Binding var selectedObject: DirectoryObjectSelection?

    @State private var searchText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Barre d'info
            if !domainService.currentObjects.isEmpty {
                HStack {
                    let userCount = domainService.currentObjects.filter { $0.kind == .user }.count
                    let groupCount = domainService.currentObjects.filter { $0.kind == .group }.count
                    let computerCount = domainService.currentObjects.filter { $0.kind == .computer }.count
                    
                    if userCount > 0 {
                        Label("\(userCount) utilisateur(s)", systemImage: "person.fill")
                            .font(.caption)
                    }
                    if groupCount > 0 {
                        Label("\(groupCount) groupe(s)", systemImage: "person.3.fill")
                            .font(.caption)
                    }
                    if computerCount > 0 {
                        Label("\(computerCount) ordinateur(s)", systemImage: "desktopcomputer")
                            .font(.caption)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                
                Divider()
            }
            
            // Liste des objets
            if domainService.currentObjects.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Aucun objet dans ce conteneur")
                        .foregroundStyle(.secondary)
                    Text("Sélectionnez une unité d'organisation dans l'arborescence")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                List(selection: $selectedObject) {
                    ForEach(filteredObjects) { summary in
                        DirectoryObjectRow(summary: summary)
                            .tag(tag(for: summary))
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Objets")
        .searchable(text: $searchText, prompt: "Rechercher un utilisateur, groupe ou ordinateur...")
        .onChange(of: containerSelection) { _, newValue in
            domainService.selectContainer(newValue)
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                domainService.selectContainer(containerSelection)
            } else {
                domainService.search(newValue)
            }
        }
    }

    private var filteredObjects: [DirectoryObjectSummary] {
        return domainService.currentObjects
    }

    private func tag(for summary: DirectoryObjectSummary) -> DirectoryObjectSelection {
        switch summary.kind {
        case .user:
            return .user(summary.id)
        case .group:
            return .group(summary.id)
        case .computer:
            return .computer(summary.id)
        }
    }
}

// MARK: - Ligne d'objet dans la liste

struct DirectoryObjectRow: View {
    let summary: DirectoryObjectSummary
    
    var body: some View {
        HStack(spacing: 12) {
            // Icône avec indicateur de statut
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(iconColor)
                
                // Badge de statut pour les utilisateurs et ordinateurs désactivés
                if (summary.kind == .user || summary.kind == .computer) && summary.isDisabled {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                if summary.kind == .user && summary.isLocked {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Image(systemName: "lock.fill")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
            }
            .frame(width: 32)
            
            // Informations
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(summary.primaryText)
                        .fontWeight(.medium)
                        .foregroundColor(summary.isDisabled ? .secondary : .primary)
                    
                    if summary.isDisabled {
                        Text("(Désactivé)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if summary.isLocked {
                        Text("(Verrouillé)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                
                if let secondary = summary.secondaryText {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Type d'objet
            Text(objectTypeLabel)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(objectTypeColor.opacity(0.1))
                .foregroundColor(objectTypeColor)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
    
    private var iconName: String {
        switch summary.kind {
        case .user: return "person.fill"
        case .group: return "person.3.fill"
        case .computer: return "desktopcomputer"
        }
    }
    
    private var iconColor: Color {
        switch summary.kind {
        case .user:
            if summary.isDisabled { return .gray }
            if summary.isLocked { return .orange }
            return .blue
        case .group:
            return .purple
        case .computer:
            if summary.isDisabled { return .gray }
            return .green
        }
    }
    
    private var objectTypeLabel: String {
        switch summary.kind {
        case .user: return "Utilisateur"
        case .group: return "Groupe"
        case .computer: return "Ordinateur"
        }
    }
    
    private var objectTypeColor: Color {
        switch summary.kind {
        case .user: return .blue
        case .group: return .purple
        case .computer: return .green
        }
    }
}
