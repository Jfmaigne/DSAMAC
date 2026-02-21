//
//  DSAMACApp.swift
//  DSAMAC
//
//  Created by MAIGNE JEAN-FRANCOIS on 21/02/2026.
//

import SwiftUI
import CoreData

@main
struct DSAMACApp: App {
    let persistenceController = PersistenceController.shared

    // Bascule simple entre domaine de démo local et vrai domaine AD
    private let useActiveDirectory = false

    var body: some Scene {
        WindowGroup {
            RootContainerView(
                persistenceController: persistenceController,
                useActiveDirectory: useActiveDirectory
            )
        }
    }
}

private struct RootContainerView: View {
    let persistenceController: PersistenceController
    let useActiveDirectory: Bool

    @State private var useADFromUI: Bool = false

    var body: some View {
        let context = persistenceController.container.viewContext

        let effectiveUseAD = useActiveDirectory || useADFromUI

        let connector: DirectoryConnector = {
            if effectiveUseAD {
                return ActiveDirectoryConnector()
            } else {
                return LocalCoreDataConnector(context: context)
            }
        }()

        let domainService = DirectoryDomainService(connector: connector)

        return DirectoryRootView(domainService: domainService)
            .environment(\.managedObjectContext, context)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Toggle("Utiliser AD réel", isOn: $useADFromUI)
                }
            }
    }
}
