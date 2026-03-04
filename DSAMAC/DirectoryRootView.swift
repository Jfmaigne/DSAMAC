import SwiftUI

struct DirectoryRootView: View {
    @ObservedObject var domainService: DirectoryDomainService

    @State private var selectedContainer: DirectoryContainerSelection?
    @State private var selectedObject: DirectoryObjectSelection?

    var body: some View {
        NavigationSplitView {
            DirectorySidebarView(domainService: domainService, selectedContainer: $selectedContainer)
        } content: {
            DirectoryObjectListView(domainService: domainService, containerSelection: selectedContainer, selectedObject: $selectedObject)
        } detail: {
            DirectoryObjectDetailView(domainService: domainService, objectSelection: selectedObject)
        }
        .task {
            domainService.loadTree()
        }
        // Afficher l'erreur éventuelle
        .overlay {
            if let error = domainService.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding()
            }
        }
    }
}
