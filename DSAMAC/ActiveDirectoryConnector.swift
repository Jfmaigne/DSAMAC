import Foundation

/// Implémentation lecture seule de DirectoryConnector qui interroge un domaine AD réel via l'outil `dscl`.
///
/// Cette implémentation suppose que le Mac est joint à un domaine Active Directory.
/// Elle essaie de découvrir le nœud AD et de lister les utilisateurs/groupes de façon simplifiée.
final class ActiveDirectoryConnector: DirectoryConnector {
    // MARK: - DirectoryConnector

    func fetchOUTree() throws -> [OUDescriptor] {
        // On ne sait pas reconstruire finement l'arbre AD via dscl sans beaucoup de logique.
        // Pour une première version, on expose un "pseudo domaine" racine qui contiendra tous les objets.
        let rootID = UUID()
        let root = OUDescriptor(
            id: rootID,
            name: "AD Domain",
            parentID: nil,
            distinguishedName: nil
        )
        return [root]
    }

    func fetchObjects(in ouID: OUDescriptor.ID) throws -> (users: [UserDescriptor], groups: [GroupDescriptor]) {
        // Ici, on ignore l'ouID et on liste simplement les utilisateurs AD connus via dscl.
        // On ne gère pas encore les groupes pour rester simple.
        let adNode = try detectADNode()
        let adUsers = try listUsers(at: adNode)
        return (adUsers, [])
    }

    func searchObjects(query: String) throws -> [DirectorySearchResult] {
        let adNode = try detectADNode()
        let adUsers = try listUsers(at: adNode)
        let lower = query.lowercased()
        let matchedUsers = adUsers.filter { user in
            user.username.lowercased().contains(lower) ||
            user.displayName.lowercased().contains(lower)
        }
        return matchedUsers.map { user in
            DirectorySearchResult(
                id: user.id,
                kind: .user,
                displayName: user.displayName.isEmpty ? user.username : user.displayName,
                secondaryText: user.email
            )
        }
    }

    // MARK: - dscl helpers

    private func detectADNode() throws -> String {
        // Utilise `dscl localhost -list "/Active Directory"` pour trouver le dossier de domaine (ex: "CORP").
        let output = try runDSCL(["localhost", "-list", "/Active Directory"])
        let domainFolder = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        guard let domainFolder, !domainFolder.isEmpty else {
            // Fallback: certains environnements exposent "All Domains".
            return "/Active Directory/All Domains/All Users"
        }
        return "/Active Directory/\(domainFolder)/All Users"
    }

    private func listUsers(at nodePath: String) throws -> [UserDescriptor] {
        // Tente deux stratégies pour lister les utilisateurs.
        let rawList1 = try? runDSCL([nodePath, "-list", "."])
        let rawList2 = try? runDSCL([nodePath, "-list", "Users"])

        let combined = [rawList1, rawList2]
            .compactMap { $0 }
            .joined(separator: "\n")

        let names = Set(combined
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
            .sorted()

        // On ne récupère pas encore les e-mails/téléphone, seulement le nom.
        return names.map { name in
            UserDescriptor(
                id: UUID(),
                username: name,
                displayName: name,
                email: nil,
                phone: nil,
                department: nil,
                descriptionText: nil,
                isEnabled: true,
                isLocked: false,
                ouID: UUID() // non significatif dans cette implémentation
            )
        }
    }

    private func runDSCL(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let dataOut = stdout.fileHandleForReading.readDataToEndOfFile()
        let dataErr = stderr.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: dataOut, encoding: .utf8) ?? ""
        let err = String(data: dataErr, encoding: .utf8) ?? ""

        if process.terminationStatus == 0 {
            return out
        } else {
            throw NSError(domain: "DSCL", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: err.isEmpty ? "dscl failed" : err])
        }
    }
}
