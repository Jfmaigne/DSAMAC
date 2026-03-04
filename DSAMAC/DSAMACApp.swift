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

    var body: some Scene {
        WindowGroup {
            RootContainerView(persistenceController: persistenceController)
        }
    }
}

/// Vue racine qui gère le cycle de vie du service et du connecteur.
/// Utilise @StateObject pour que le connecteur AD et le service survivent aux re-rendus SwiftUI.
private struct RootContainerView: View {
    let persistenceController: PersistenceController

    /// Le connecteur AD est un ObservableObject ; on le garde en @StateObject
    /// pour ne pas le recréer à chaque rafraîchissement de la vue.
    @StateObject private var adConnector = ActiveDirectoryConnector(adConfig: nil)

    /// Le service de domaine (créé une seule fois grâce à @StateObject)
    @StateObject private var domainService: DirectoryDomainService

    /// Indique si on est en mode AD réel ou démo locale
    @State private var isUsingAD: Bool = false

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
        // Initialiser le service avec le connecteur local par défaut
        let context = persistenceController.container.viewContext
        let localConnector = LocalCoreDataConnector(context: context)
        _domainService = StateObject(wrappedValue: DirectoryDomainService(connector: localConnector))
    }

    var body: some View {
        Group {
            // Si le connecteur AD signale qu'il a besoin d'une config manuelle, on affiche le formulaire
            if isUsingAD && adConnector.needsManualConfig {
                LDAPConfigView(connector: adConnector, domainService: domainService)
            } else {
                DirectoryRootView(domainService: domainService)
            }
        }
        .environment(\.managedObjectContext, persistenceController.container.viewContext)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(isUsingAD ? "Retour aux données de démo" : "Utiliser AD réel") {
                    toggleADMode()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func toggleADMode() {
        if isUsingAD {
            // Retour au mode démo local
            let context = persistenceController.container.viewContext
            let localConnector = LocalCoreDataConnector(context: context)
            domainService.setConnector(localConnector)
            isUsingAD = false
        } else {
            // Passer en mode AD réel
            adConnector.resetCache()
            adConnector.needsManualConfig = false
            domainService.setConnector(adConnector)
            isUsingAD = true

            // Si loadTree échoue (pas de domaine détecté), le connecteur
            // aura positionné needsManualConfig = true → le formulaire s'affichera
        }
    }
}
