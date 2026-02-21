import SwiftUI

struct DirectorySidebarView: View {
    @ObservedObject var domainService: DirectoryDomainService
    @Binding var selectedContainer: DirectoryContainerSelection?

    var body: some View {
        List(selection: $selectedContainer) {
            OutlineGroup(domainService.rootOUTree, children: \.children) { node in
                Text(node.name)
                    .tag(DirectoryContainerSelection.organizationalUnit(node.id))
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Annuaire")
    }
}
