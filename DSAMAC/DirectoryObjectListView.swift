import SwiftUI

struct DirectoryObjectListView: View {
    @ObservedObject var domainService: DirectoryDomainService
    let containerSelection: DirectoryContainerSelection?
    @Binding var selectedObject: DirectoryObjectSelection?

    @State private var searchText: String = ""

    var body: some View {
        VStack {
            if domainService.currentObjects.isEmpty {
                Text("Aucun objet dans ce conteneur")
                    .foregroundStyle(.secondary)
            } else {
                List(selection: $selectedObject) {
                    ForEach(filteredObjects) { summary in
                        HStack {
                            Image(systemName: iconName(for: summary.kind))
                            VStack(alignment: .leading) {
                                Text(summary.primaryText)
                                if let secondary = summary.secondaryText {
                                    Text(secondary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tag(tag(for: summary))
                    }
                }
            }
        }
        .navigationTitle("Objets")
        .searchable(text: $searchText)
        .onChange(of: containerSelection) { _, newValue in
            domainService.selectContainer(newValue)
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Recharger les objets du conteneur courant
                domainService.selectContainer(containerSelection)
            } else {
                domainService.search(newValue)
            }
        }
    }

    private var filteredObjects: [DirectoryObjectSummary] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return domainService.currentObjects
        } else {
            return domainService.currentObjects // currentObjects déjà filtré par le service
        }
    }

    private func iconName(for kind: DirectoryObjectSummary.Kind) -> String {
        switch kind {
        case .user: return "person.fill"
        case .group: return "person.3.fill"
        }
    }

    private func tag(for summary: DirectoryObjectSummary) -> DirectoryObjectSelection {
        switch summary.kind {
        case .user:
            return .user(summary.id)
        case .group:
            return .group(summary.id)
        }
    }
}
