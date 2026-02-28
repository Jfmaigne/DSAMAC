import SwiftUI

struct DirectorySidebarView: View {
    @ObservedObject var domainService: DirectoryDomainService
    @Binding var selectedContainer: DirectoryContainerSelection?

    var body: some View {
        VStack(spacing: 0) {
            if domainService.isLoading {
                ProgressView("Chargement...")
                    .padding()
            } else if let error = domainService.errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text("Erreur")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if domainService.rootOUTree.isEmpty {
                VStack {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Aucune unité d'organisation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                List(selection: $selectedContainer) {
                    OutlineGroup(domainService.rootOUTree, children: \.children) { node in
                        Label {
                            Text(node.name)
                        } icon: {
                            Image(systemName: ouIcon(for: node))
                                .foregroundStyle(ouColor(for: node))
                        }
                        .tag(DirectoryContainerSelection.organizationalUnit(node.id))
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("Annuaire")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    domainService.loadTree()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Actualiser l'arborescence")
            }
        }
    }
    
    private func ouIcon(for node: OUNode) -> String {
        let name = node.name.lowercased()
        
        // Icônes spécifiques selon le nom
        if name.contains("domain") || name.contains(".local") || name.contains(".com") {
            return "globe"
        } else if name.contains("user") || name.contains("utilisateur") {
            return "person.2.fill"
        } else if name.contains("group") || name.contains("groupe") {
            return "person.3.fill"
        } else if name.contains("computer") || name.contains("ordinateur") {
            return "desktopcomputer"
        } else if name.contains("server") || name.contains("serveur") {
            return "server.rack"
        } else if name.contains("it") || name.contains("informatique") {
            return "laptopcomputer"
        } else if name.contains("hr") || name.contains("rh") {
            return "person.text.rectangle"
        } else if name.contains("finance") {
            return "chart.bar.fill"
        } else {
            return "folder.fill"
        }
    }
    
    private func ouColor(for node: OUNode) -> Color {
        let name = node.name.lowercased()
        
        if name.contains("domain") || name.contains(".local") || name.contains(".com") {
            return .blue
        } else if name.contains("user") || name.contains("utilisateur") {
            return .green
        } else if name.contains("group") || name.contains("groupe") {
            return .purple
        } else {
            return .orange
        }
    }
}
