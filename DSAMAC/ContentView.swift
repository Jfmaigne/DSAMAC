//
//  ContentView.swift
//  DSAMAC
//
//  Created by MAIGNE JEAN-FRANCOIS on 21/02/2026.
//

import SwiftUI
import CoreData
import Foundation
import Combine

struct DirectoryUser: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let uniqueID: String?
}

@MainActor
final class ActiveDirectoryService: ObservableObject {
    @Published var users: [DirectoryUser] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadADUsers() async {
        isLoading = true
        errorMessage = nil
        do {
            // Prefer OpenDirectory if available; for portability, we shell out to dscl.
            // This lists users from the AD node if bound (e.g., /Active Directory/<DOMAIN>/All Users)
            // We attempt to discover the AD node name first.
            let adNode = try await detectADNode()
            let listed = try await listUsers(at: adNode)
            await MainActor.run {
                self.users = listed
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.users = []
            }
        }
        isLoading = false
    }

    private func detectADNode() async throws -> String {
        // Use `dscl localhost -list "/Active Directory"` to reveal domain nodes
        let output = try await runDSCL(["localhost", "-list", "/Active Directory"]) // may list domain folders
        // Parse first non-empty line as domain folder name (e.g., "CORP")
        let domainFolder = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        guard let domainFolder, !domainFolder.isEmpty else {
            // Fallback: some systems present "All Domains"; try a generic path
            return "/Active Directory/All Domains/All Users"
        }
        // Construct the All Users path for the discovered domain
        return "/Active Directory/\(domainFolder)/All Users"
    }

    private func listUsers(at nodePath: String) async throws -> [DirectoryUser] {
        // dscl list users: `dscl "+nodePath" -list Users`
        // Using dscl with explicit node path
        let args = [nodePath, "-list", "."]
        // Some ADs require Users container explicitly; try two strategies
        let rawList1 = try? await runDSCL(args)
        let rawList2 = try? await runDSCL([nodePath, "-list", "Users"]) // alternate container

        let combined = [rawList1, rawList2]
            .compactMap { $0 }
            .joined(separator: "\n")

        let names = Set(combined
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
            .sorted()

        // Optionally fetch UniqueID for each user (can be slow). We'll skip for performance.
        return names.map { DirectoryUser(name: $0, uniqueID: nil) }
    }

    private func runDSCL(_ arguments: [String]) async throws -> String {
        // Invokes: /usr/bin/dscl <args...>
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
            process.arguments = arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            process.terminationHandler = { proc in
                let dataOut = stdout.fileHandleForReading.readDataToEndOfFile()
                let dataErr = stderr.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: dataOut, encoding: .utf8) ?? ""
                let err = String(data: dataErr, encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: out)
                } else {
                    continuation.resume(throwing: NSError(domain: "DSCL", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: err.isEmpty ? "dscl failed" : err]))
                }
            }
        }
    }
}

struct ContentView: View {
    // Preserve Core Data context for the existing preview and potential usage
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: true)],
        animation: .default)
    private var items: FetchedResults<Item>

    @StateObject private var adService = ActiveDirectoryService()
    @State private var selection: Int = 0

    var body: some View {
        NavigationView {
            VStack {
                Picker("Section", selection: $selection) {
                    Text("Active Directory").tag(0)
                    Text("Core Data Items").tag(1)
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                if selection == 0 {
                    adUsersView
                } else {
                    coreDataListView
                }
            }
            .navigationTitle(selection == 0 ? "Utilisateurs AD" : "Items")
            .toolbar {
                if selection == 0 {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await adService.loadADUsers() }
                        } label: {
                            Label("Rafraîchir", systemImage: "arrow.clockwise")
                        }
                        .disabled(adService.isLoading)
                    }
                } else {
                    ToolbarItem {
                        Button(action: addItem) {
                            Label("Add Item", systemImage: "plus")
                        }
                    }
                }
            }
        }
        .task {
            // Auto-load AD users on first appearance
            await adService.loadADUsers()
        }
    }

    private var adUsersView: some View {
        Group {
            if adService.isLoading {
                ProgressView("Chargement des utilisateurs AD…")
                    .padding()
            } else if let error = adService.errorMessage {
                VStack(spacing: 12) {
                    Text("Erreur: \(error)")
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button("Réessayer") {
                        Task { await adService.loadADUsers() }
                    }
                }
                .padding()
            } else if adService.users.isEmpty {
                VStack(spacing: 8) {
                    Text("Aucun utilisateur AD trouvé.")
                    Text("Vérifiez que ce Mac est bien joint à un domaine Active Directory.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                List(adService.users) { user in
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.blue)
                        Text(user.name)
                        Spacer()
                        if let uid = user.uniqueID {
                            Text("#\(uid)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var coreDataListView: some View {
        List {
            ForEach(items) { item in
                NavigationLink {
                    Text("Item at \(item.timestamp!, formatter: itemFormatter)")
                } label: {
                    Text(item.timestamp!, formatter: itemFormatter)
                }
            }
            .onDelete(perform: deleteItems)
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(context: viewContext)
            newItem.timestamp = Date()

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { items[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
