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
    }
}
