import Foundation
import CoreData

/// Local implementation of DirectoryConnector backed by an in-memory model.
/// Provides realistic demo data simulating a small AD domain with full attributes like dsa.msc.
final class LocalCoreDataConnector: DirectoryConnector {
    private let context: NSManagedObjectContext

    // In-memory storage simulating a full AD domain
    private var ous: [OUDescriptor] = []
    private var users: [UserDescriptor] = []
    private var groups: [GroupDescriptor] = []
    private var computers: [ComputerDescriptor] = []

    init(context: NSManagedObjectContext) {
        self.context = context
        bootstrapDemoDataIfNeeded()
    }

    private func bootstrapDemoDataIfNeeded() {
        guard ous.isEmpty else { return }

        let now = Date()
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: now)!
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: now)!
        let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: now)!
        let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: now)!
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let inOneYear = Calendar.current.date(byAdding: .year, value: 1, to: now)!

        // Root domain OU
        let rootID = UUID()
        let root = OUDescriptor(
            id: rootID,
            name: "example.local",
            parentID: nil,
            distinguishedName: "DC=example,DC=local",
            description: "Domaine racine Example",
            whenCreated: oneYearAgo,
            whenChanged: oneMonthAgo
        )

        // Child OUs
        let usersOUID = UUID()
        let usersOU = OUDescriptor(
            id: usersOUID,
            name: "Users",
            parentID: rootID,
            distinguishedName: "OU=Users,DC=example,DC=local",
            description: "Conteneur des utilisateurs",
            whenCreated: oneYearAgo,
            whenChanged: sixMonthsAgo
        )
        
        let groupsOUID = UUID()
        let groupsOU = OUDescriptor(
            id: groupsOUID,
            name: "Groups",
            parentID: rootID,
            distinguishedName: "OU=Groups,DC=example,DC=local",
            description: "Conteneur des groupes",
            whenCreated: oneYearAgo,
            whenChanged: sixMonthsAgo
        )
        
        // OU pour les ordinateurs
        let computersOUID = UUID()
        let computersOU = OUDescriptor(
            id: computersOUID,
            name: "Computers",
            parentID: rootID,
            distinguishedName: "OU=Computers,DC=example,DC=local",
            description: "Conteneur des ordinateurs",
            whenCreated: oneYearAgo,
            whenChanged: sixMonthsAgo
        )
        
        // Sous-OUs pour les ordinateurs
        let workstationsOUID = UUID()
        let workstationsOU = OUDescriptor(
            id: workstationsOUID,
            name: "Workstations",
            parentID: computersOUID,
            distinguishedName: "OU=Workstations,OU=Computers,DC=example,DC=local",
            description: "Postes de travail",
            whenCreated: oneYearAgo,
            whenChanged: oneMonthAgo
        )
        
        let serversOUID = UUID()
        let serversOU = OUDescriptor(
            id: serversOUID,
            name: "Servers",
            parentID: computersOUID,
            distinguishedName: "OU=Servers,OU=Computers,DC=example,DC=local",
            description: "Serveurs",
            whenCreated: oneYearAgo,
            whenChanged: oneMonthAgo
        )
        
        let itOUID = UUID()
        let itOU = OUDescriptor(
            id: itOUID,
            name: "IT",
            parentID: usersOUID,
            distinguishedName: "OU=IT,OU=Users,DC=example,DC=local",
            description: "Service Informatique",
            whenCreated: oneYearAgo,
            whenChanged: oneMonthAgo
        )
        
        let hrOUID = UUID()
        let hrOU = OUDescriptor(
            id: hrOUID,
            name: "HR",
            parentID: usersOUID,
            distinguishedName: "OU=HR,OU=Users,DC=example,DC=local",
            description: "Ressources Humaines",
            whenCreated: oneYearAgo,
            whenChanged: oneMonthAgo
        )
        
        let financeOUID = UUID()
        let financeOU = OUDescriptor(
            id: financeOUID,
            name: "Finance",
            parentID: usersOUID,
            distinguishedName: "OU=Finance,OU=Users,DC=example,DC=local",
            description: "Service Financier",
            whenCreated: sixMonthsAgo,
            whenChanged: oneMonthAgo
        )

        ous = [root, usersOU, groupsOU, computersOU, workstationsOU, serversOU, itOU, hrOU, financeOU]

        // Demo users with full attributes
        let user1ID = UUID()
        let user1 = UserDescriptor(
            id: user1ID,
            firstName: "John",
            lastName: "Doe",
            displayName: "John Doe",
            description: "Administrateur système senior",
            office: "Bureau 101",
            telephone: "+33 1 02 03 04 05",
            email: "jdoe@example.local",
            webPage: "https://intranet.example.local/~jdoe",
            street: "123 Rue de la Paix",
            poBox: nil,
            city: "Paris",
            state: "Île-de-France",
            postalCode: "75001",
            country: "France",
            sAMAccountName: "jdoe",
            userPrincipalName: "jdoe@example.local",
            objectSID: "S-1-5-21-1234567890-1234567890-1234567890-1001",
            userAccountControl: 512, // Normal account, enabled
            isEnabled: true,
            isLocked: false,
            accountExpires: nil,
            passwordLastSet: oneWeekAgo,
            passwordNeverExpires: false,
            mustChangePassword: false,
            cannotChangePassword: false,
            lastLogon: yesterday,
            logonCount: 1247,
            badPasswordCount: 0,
            badPasswordTime: nil,
            profilePath: nil,
            scriptPath: "logon.bat",
            homeDirectory: "\\\\fileserver\\users\\jdoe",
            homeDrive: "H:",
            homePhone: "+33 1 98 76 54 32",
            pager: nil,
            mobile: "+33 6 12 34 56 78",
            fax: nil,
            ipPhone: "1001",
            title: "Administrateur Système",
            department: "IT",
            company: "Example Corp",
            manager: "CN=Marie Martin,OU=IT,OU=Users,DC=example,DC=local",
            managerDisplayName: "Marie Martin",
            directReports: ["CN=Bob Wilson,OU=IT,OU=Users,DC=example,DC=local"],
            memberOf: [
                "CN=Domain Admins,OU=Groups,DC=example,DC=local",
                "CN=IT Staff,OU=Groups,DC=example,DC=local"
            ],
            primaryGroupID: 513,
            primaryGroup: "Domain Users",
            distinguishedName: "CN=John Doe,OU=IT,OU=Users,DC=example,DC=local",
            objectGUID: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            whenCreated: oneYearAgo,
            whenChanged: oneWeekAgo,
            objectClass: ["top", "person", "organizationalPerson", "user"],
            ouID: itOUID
        )
        
        let user2ID = UUID()
        let user2 = UserDescriptor(
            id: user2ID,
            firstName: "Alice",
            lastName: "Smith",
            displayName: "Alice Smith",
            description: "Responsable RH",
            office: "Bureau 205",
            telephone: "+33 1 06 07 08 09",
            email: "asmith@example.local",
            webPage: nil,
            street: "123 Rue de la Paix",
            poBox: nil,
            city: "Paris",
            state: "Île-de-France",
            postalCode: "75001",
            country: "France",
            sAMAccountName: "asmith",
            userPrincipalName: "asmith@example.local",
            objectSID: "S-1-5-21-1234567890-1234567890-1234567890-1002",
            userAccountControl: 512,
            isEnabled: true,
            isLocked: false,
            accountExpires: inOneYear,
            passwordLastSet: oneMonthAgo,
            passwordNeverExpires: false,
            mustChangePassword: false,
            cannotChangePassword: false,
            lastLogon: yesterday,
            logonCount: 523,
            badPasswordCount: 1,
            badPasswordTime: oneWeekAgo,
            profilePath: nil,
            scriptPath: "logon.bat",
            homeDirectory: "\\\\fileserver\\users\\asmith",
            homeDrive: "H:",
            homePhone: nil,
            pager: nil,
            mobile: "+33 6 98 76 54 32",
            fax: nil,
            ipPhone: "2005",
            title: "Responsable Ressources Humaines",
            department: "HR",
            company: "Example Corp",
            manager: nil,
            managerDisplayName: nil,
            directReports: ["CN=Bob HR,OU=HR,OU=Users,DC=example,DC=local"],
            memberOf: [
                "CN=HR Staff,OU=Groups,DC=example,DC=local",
                "CN=Management,OU=Groups,DC=example,DC=local"
            ],
            primaryGroupID: 513,
            primaryGroup: "Domain Users",
            distinguishedName: "CN=Alice Smith,OU=HR,OU=Users,DC=example,DC=local",
            objectGUID: "b2c3d4e5-f6a7-8901-bcde-f23456789012",
            whenCreated: oneYearAgo,
            whenChanged: oneMonthAgo,
            objectClass: ["top", "person", "organizationalPerson", "user"],
            ouID: hrOUID
        )
        
        let user3ID = UUID()
        let user3 = UserDescriptor(
            id: user3ID,
            firstName: "Bob",
            lastName: "Wilson",
            displayName: "Bob Wilson",
            description: "Technicien support IT",
            office: "Bureau 102",
            telephone: "+33 1 11 22 33 44",
            email: "bwilson@example.local",
            webPage: nil,
            street: "123 Rue de la Paix",
            poBox: nil,
            city: "Paris",
            state: "Île-de-France",
            postalCode: "75001",
            country: "France",
            sAMAccountName: "bwilson",
            userPrincipalName: "bwilson@example.local",
            objectSID: "S-1-5-21-1234567890-1234567890-1234567890-1003",
            userAccountControl: 514, // Disabled account
            isEnabled: false,
            isLocked: false,
            accountExpires: nil,
            passwordLastSet: sixMonthsAgo,
            passwordNeverExpires: false,
            mustChangePassword: true,
            cannotChangePassword: false,
            lastLogon: sixMonthsAgo,
            logonCount: 89,
            badPasswordCount: 0,
            badPasswordTime: nil,
            profilePath: nil,
            scriptPath: "logon.bat",
            homeDirectory: "\\\\fileserver\\users\\bwilson",
            homeDrive: "H:",
            homePhone: nil,
            pager: nil,
            mobile: "+33 6 55 44 33 22",
            fax: nil,
            ipPhone: "1002",
            title: "Technicien Support",
            department: "IT",
            company: "Example Corp",
            manager: "CN=John Doe,OU=IT,OU=Users,DC=example,DC=local",
            managerDisplayName: "John Doe",
            directReports: [],
            memberOf: [
                "CN=IT Staff,OU=Groups,DC=example,DC=local"
            ],
            primaryGroupID: 513,
            primaryGroup: "Domain Users",
            distinguishedName: "CN=Bob Wilson,OU=IT,OU=Users,DC=example,DC=local",
            objectGUID: "c3d4e5f6-a7b8-9012-cdef-345678901234",
            whenCreated: sixMonthsAgo,
            whenChanged: oneMonthAgo,
            objectClass: ["top", "person", "organizationalPerson", "user"],
            ouID: itOUID
        )
        
        let user4ID = UUID()
        let user4 = UserDescriptor(
            id: user4ID,
            firstName: "Marie",
            lastName: "Martin",
            displayName: "Marie Martin",
            description: "Directrice IT",
            office: "Bureau 100",
            telephone: "+33 1 00 00 00 01",
            email: "mmartin@example.local",
            webPage: "https://intranet.example.local/~mmartin",
            street: "123 Rue de la Paix",
            poBox: nil,
            city: "Paris",
            state: "Île-de-France",
            postalCode: "75001",
            country: "France",
            sAMAccountName: "mmartin",
            userPrincipalName: "mmartin@example.local",
            objectSID: "S-1-5-21-1234567890-1234567890-1234567890-1004",
            userAccountControl: 66048, // Normal + password never expires
            isEnabled: true,
            isLocked: false,
            accountExpires: nil,
            passwordLastSet: oneYearAgo,
            passwordNeverExpires: true,
            mustChangePassword: false,
            cannotChangePassword: false,
            lastLogon: yesterday,
            logonCount: 2156,
            badPasswordCount: 0,
            badPasswordTime: nil,
            profilePath: nil,
            scriptPath: "logon.bat",
            homeDirectory: "\\\\fileserver\\users\\mmartin",
            homeDrive: "H:",
            homePhone: "+33 1 99 88 77 66",
            pager: nil,
            mobile: "+33 6 00 00 00 01",
            fax: "+33 1 00 00 00 02",
            ipPhone: "1000",
            title: "Directrice des Systèmes d'Information",
            department: "IT",
            company: "Example Corp",
            manager: nil,
            managerDisplayName: nil,
            directReports: [
                "CN=John Doe,OU=IT,OU=Users,DC=example,DC=local",
                "CN=Bob Wilson,OU=IT,OU=Users,DC=example,DC=local"
            ],
            memberOf: [
                "CN=Domain Admins,OU=Groups,DC=example,DC=local",
                "CN=IT Staff,OU=Groups,DC=example,DC=local",
                "CN=Management,OU=Groups,DC=example,DC=local"
            ],
            primaryGroupID: 513,
            primaryGroup: "Domain Users",
            distinguishedName: "CN=Marie Martin,OU=IT,OU=Users,DC=example,DC=local",
            objectGUID: "d4e5f6a7-b8c9-0123-def0-456789012345",
            whenCreated: oneYearAgo,
            whenChanged: oneWeekAgo,
            objectClass: ["top", "person", "organizationalPerson", "user"],
            ouID: itOUID
        )
        
        let user5ID = UUID()
        let user5 = UserDescriptor(
            id: user5ID,
            firstName: "Pierre",
            lastName: "Dupont",
            displayName: "Pierre Dupont",
            description: "Comptable",
            office: "Bureau 301",
            telephone: "+33 1 33 44 55 66",
            email: "pdupont@example.local",
            webPage: nil,
            street: "123 Rue de la Paix",
            poBox: nil,
            city: "Paris",
            state: "Île-de-France",
            postalCode: "75001",
            country: "France",
            sAMAccountName: "pdupont",
            userPrincipalName: "pdupont@example.local",
            objectSID: "S-1-5-21-1234567890-1234567890-1234567890-1005",
            userAccountControl: 528, // Locked out
            isEnabled: true,
            isLocked: true,
            accountExpires: nil,
            passwordLastSet: oneMonthAgo,
            passwordNeverExpires: false,
            mustChangePassword: false,
            cannotChangePassword: false,
            lastLogon: oneWeekAgo,
            logonCount: 312,
            badPasswordCount: 5,
            badPasswordTime: yesterday,
            profilePath: nil,
            scriptPath: "logon.bat",
            homeDirectory: "\\\\fileserver\\users\\pdupont",
            homeDrive: "H:",
            homePhone: nil,
            pager: nil,
            mobile: "+33 6 77 88 99 00",
            fax: nil,
            ipPhone: "3001",
            title: "Comptable Senior",
            department: "Finance",
            company: "Example Corp",
            manager: nil,
            managerDisplayName: nil,
            directReports: [],
            memberOf: [
                "CN=Finance Staff,OU=Groups,DC=example,DC=local"
            ],
            primaryGroupID: 513,
            primaryGroup: "Domain Users",
            distinguishedName: "CN=Pierre Dupont,OU=Finance,OU=Users,DC=example,DC=local",
            objectGUID: "e5f6a7b8-c9d0-1234-ef01-567890123456",
            whenCreated: sixMonthsAgo,
            whenChanged: yesterday,
            objectClass: ["top", "person", "organizationalPerson", "user"],
            ouID: financeOUID
        )

        users = [user1, user2, user3, user4, user5]

        // Demo groups with full attributes
        let domainAdminsGroup = GroupDescriptor(
            id: UUID(),
            name: "Domain Admins",
            sAMAccountName: "Domain Admins",
            description: "Administrateurs du domaine avec tous les privilèges",
            email: "admins@example.local",
            notes: "Groupe critique - accès restreint",
            groupType: .security,
            groupScope: .global,
            objectSID: "S-1-5-21-1234567890-1234567890-1234567890-512",
            distinguishedName: "CN=Domain Admins,OU=Groups,DC=example,DC=local",
            objectGUID: "f6a7b8c9-d0e1-2345-f012-678901234567",
            members: [
                "CN=John Doe,OU=IT,OU=Users,DC=example,DC=local",
                "CN=Marie Martin,OU=IT,OU=Users,DC=example,DC=local"
            ],
            memberNames: ["John Doe", "Marie Martin"],
            memberCount: 2,
            memberOf: [],
            memberOfNames: [],
            whenCreated: oneYearAgo,
            whenChanged: oneMonthAgo,
            managedBy: "CN=Marie Martin,OU=IT,OU=Users,DC=example,DC=local",
            managedByName: "Marie Martin",
            ouID: groupsOUID
        )
        
        let itStaffGroup = GroupDescriptor(
            id: UUID(),
            name: "IT Staff",
            sAMAccountName: "IT Staff",
            description: "Personnel du service informatique",
            email: "it@example.local",
            notes: nil,
            groupType: .security,
            groupScope: .global,
            objectSID: "S-1-5-21-1234567890-1234567890-1234567890-1101",
            distinguishedName: "CN=IT Staff,OU=Groups,DC=example,DC=local",
            objectGUID: "a7b8c9d0-e1f2-3456-0123-789012345678",
            members: [
                "CN=John Doe,OU=IT,OU=Users,DC=example,DC=local",
                "CN=Bob Wilson,OU=IT,OU=Users,DC=example,DC=local",
                "CN=Marie Martin,OU=IT,OU=Users,DC=example,DC=local"
            ],
            memberNames: ["John Doe", "Bob Wilson", "Marie Martin"],
            memberCount: 3,
            memberOf: [],
            memberOfNames: [],
            whenCreated: oneYearAgo,
            whenChanged: oneWeekAgo,
            managedBy: "CN=Marie Martin,OU=IT,OU=Users,DC=example,DC=local",
            managedByName: "Marie Martin",
            ouID: groupsOUID
        )
        
        let hrStaffGroup = GroupDescriptor(
            id: UUID(),
            name: "HR Staff",
            sAMAccountName: "HR Staff",
            description: "Personnel des Ressources Humaines",
            email: "hr@example.local",
            notes: "Accès aux dossiers du personnel",
            groupType: .security,
            groupScope: .global,
            objectSID: "S-1-5-21-1234567890-1234567890-1234567890-1102",
            distinguishedName: "CN=HR Staff,OU=Groups,DC=example,DC=local",
            objectGUID: "b8c9d0e1-f2a3-4567-1234-890123456789",
            members: [
                "CN=Alice Smith,OU=HR,OU=Users,DC=example,DC=local"
            ],
            memberNames: ["Alice Smith"],
            memberCount: 1,
            memberOf: [],
            memberOfNames: [],
            whenCreated: oneYearAgo,
            whenChanged: oneMonthAgo,
            managedBy: "CN=Alice Smith,OU=HR,OU=Users,DC=example,DC=local",
            managedByName: "Alice Smith",
            ouID: groupsOUID
        )
        
        let financeStaffGroup = GroupDescriptor(
            id: UUID(),
            name: "Finance Staff",
            sAMAccountName: "Finance Staff",
            description: "Personnel du service financier",
            email: "finance@example.local",
            notes: nil,
            groupType: .security,
            groupScope: .global,
            objectSID: "S-1-5-21-1234567890-1234567890-1234567890-1103",
            distinguishedName: "CN=Finance Staff,OU=Groups,DC=example,DC=local",
            objectGUID: "c9d0e1f2-a3b4-5678-2345-901234567890",
            members: [
                "CN=Pierre Dupont,OU=Finance,OU=Users,DC=example,DC=local"
            ],
            memberNames: ["Pierre Dupont"],
            memberCount: 1,
            memberOf: [],
            memberOfNames: [],
            whenCreated: sixMonthsAgo,
            whenChanged: oneMonthAgo,
            managedBy: nil,
            managedByName: nil,
            ouID: groupsOUID
        )
        
        let managementGroup = GroupDescriptor(
            id: UUID(),
            name: "Management",
            sAMAccountName: "Management",
            description: "Équipe de direction",
            email: "management@example.local",
            notes: "Groupe de distribution pour les communications de direction",
            groupType: .distribution,
            groupScope: .universal,
            objectSID: "S-1-5-21-1234567890-1234567890-1234567890-1104",
            distinguishedName: "CN=Management,OU=Groups,DC=example,DC=local",
            objectGUID: "d0e1f2a3-b4c5-6789-3456-012345678901",
            members: [
                "CN=Marie Martin,OU=IT,OU=Users,DC=example,DC=local",
                "CN=Alice Smith,OU=HR,OU=Users,DC=example,DC=local"
            ],
            memberNames: ["Marie Martin", "Alice Smith"],
            memberCount: 2,
            memberOf: [],
            memberOfNames: [],
            whenCreated: oneYearAgo,
            whenChanged: oneMonthAgo,
            managedBy: nil,
            managedByName: nil,
            ouID: groupsOUID
        )
        
        let allUsersGroup = GroupDescriptor(
            id: UUID(),
            name: "All Users",
            sAMAccountName: "All Users",
            description: "Tous les utilisateurs du domaine",
            email: "all@example.local",
            notes: nil,
            groupType: .distribution,
            groupScope: .domainLocal,
            objectSID: "S-1-5-21-1234567890-1234567890-1234567890-1105",
            distinguishedName: "CN=All Users,OU=Groups,DC=example,DC=local",
            objectGUID: "e1f2a3b4-c5d6-7890-4567-123456789012",
            members: [
                "CN=John Doe,OU=IT,OU=Users,DC=example,DC=local",
                "CN=Alice Smith,OU=HR,OU=Users,DC=example,DC=local",
                "CN=Bob Wilson,OU=IT,OU=Users,DC=example,DC=local",
                "CN=Marie Martin,OU=IT,OU=Users,DC=example,DC=local",
                "CN=Pierre Dupont,OU=Finance,OU=Users,DC=example,DC=local"
            ],
            memberNames: ["John Doe", "Alice Smith", "Bob Wilson", "Marie Martin", "Pierre Dupont"],
            memberCount: 5,
            memberOf: [],
            memberOfNames: [],
            whenCreated: oneYearAgo,
            whenChanged: yesterday,
            managedBy: nil,
            managedByName: nil,
            ouID: groupsOUID
        )

        groups = [domainAdminsGroup, itStaffGroup, hrStaffGroup, financeStaffGroup, managementGroup, allUsersGroup]
        
        // Demo computers (workstations and servers)
        let ws1 = ComputerDescriptor(
            id: UUID(),
            name: "PC-JDOE",
            sAMAccountName: "PC-JDOE$",
            dnsHostName: "pc-jdoe.example.local",
            description: "Poste de travail de John Doe",
            location: "Bureau 101",
            computerType: .workstation,
            operatingSystem: "Windows 11 Pro",
            operatingSystemVersion: "10.0 (22631)",
            operatingSystemServicePack: nil,
            objectSID: "S-1-5-21-1234567890-1234567890-1234567890-2001",
            userAccountControl: 4096,
            isEnabled: true,
            accountExpires: nil,
            lastLogon: yesterday,
            logonCount: 523,
            badPasswordCount: 0,
            badPasswordTime: nil,
            passwordLastSet: oneMonthAgo,
            isTrustedForDelegation: false,
            memberOf: ["CN=Domain Computers,OU=Groups,DC=example,DC=local"],
            memberOfNames: ["Domain Computers"],
            primaryGroupID: 515,
            primaryGroup: "Domain Computers",
            managedBy: "CN=John Doe,OU=IT,OU=Users,DC=example,DC=local",
            managedByName: "John Doe",
            distinguishedName: "CN=PC-JDOE,OU=Workstations,OU=Computers,DC=example,DC=local",
            objectGUID: "f1a2b3c4-d5e6-7890-abcd-ef0123456789",
            whenCreated: sixMonthsAgo,
            whenChanged: oneWeekAgo,
            objectClass: ["top", "person", "organizationalPerson", "user", "computer"],
            ouID: workstationsOUID
        )
        
        let ws2 = ComputerDescriptor(
            id: UUID(),
            name: "PC-ASMITH",
            sAMAccountName: "PC-ASMITH$",
            dnsHostName: "pc-asmith.example.local",
            description: "Poste de travail d'Alice Smith",
            location: "Bureau 205",
            computerType: .workstation,
            operatingSystem: "Windows 11 Pro",
            operatingSystemVersion: "10.0 (22631)",
            operatingSystemServicePack: nil,
            objectSID: "S-1-5-21-1234567890-1234567890-1234567890-2002",
            userAccountControl: 4096,
            isEnabled: true,
            accountExpires: nil,
            lastLogon: yesterday,
            logonCount: 312,
            badPasswordCount: 0,
            badPasswordTime: nil,
            passwordLastSet: oneMonthAgo,
            isTrustedForDelegation: false,
            memberOf: ["CN=Domain Computers,OU=Groups,DC=example,DC=local"],
            memberOfNames: ["Domain Computers"],
            primaryGroupID: 515,
            primaryGroup: "Domain Computers",
            managedBy: "CN=Alice Smith,OU=HR,OU=Users,DC=example,DC=local",
            managedByName: "Alice Smith",
            distinguishedName: "CN=PC-ASMITH,OU=Workstations,OU=Computers,DC=example,DC=local",
            objectGUID: "a2b3c4d5-e6f7-8901-bcde-f12345678901",
            whenCreated: sixMonthsAgo,
            whenChanged: oneWeekAgo,
            objectClass: ["top", "person", "organizationalPerson", "user", "computer"],
            ouID: workstationsOUID
        )
        
        let ws3 = ComputerDescriptor(
            id: UUID(),
            name: "PC-OLD01",
            sAMAccountName: "PC-OLD01$",
            dnsHostName: "pc-old01.example.local",
            description: "Ancien poste de travail (désactivé)",
            location: "Stock IT",
            computerType: .workstation,
            operatingSystem: "Windows 10 Pro",
            operatingSystemVersion: "10.0 (19045)",
            operatingSystemServicePack: nil,
            objectSID: "S-1-5-21-1234567890-1234567890-1234567890-2003",
            userAccountControl: 4098, // Disabled
            isEnabled: false,
            accountExpires: nil,
            lastLogon: threeMonthsAgo,
            logonCount: 1245,
            badPasswordCount: 0,
            badPasswordTime: nil,
            passwordLastSet: sixMonthsAgo,
            isTrustedForDelegation: false,
            memberOf: ["CN=Domain Computers,OU=Groups,DC=example,DC=local"],
            memberOfNames: ["Domain Computers"],
            primaryGroupID: 515,
            primaryGroup: "Domain Computers",
            managedBy: nil,
            managedByName: nil,
            distinguishedName: "CN=PC-OLD01,OU=Workstations,OU=Computers,DC=example,DC=local",
            objectGUID: "b3c4d5e6-f7a8-9012-cdef-234567890123",
            whenCreated: oneYearAgo,
            whenChanged: threeMonthsAgo,
            objectClass: ["top", "person", "organizationalPerson", "user", "computer"],
            ouID: workstationsOUID
        )
        
        let srv1 = ComputerDescriptor(
            id: UUID(),
            name: "SRV-DC01",
            sAMAccountName: "SRV-DC01$",
            dnsHostName: "srv-dc01.example.local",
            description: "Contrôleur de domaine principal",
            location: "Salle serveur",
            computerType: .domainController,
            operatingSystem: "Windows Server 2022 Datacenter",
            operatingSystemVersion: "10.0 (20348)",
            operatingSystemServicePack: nil,
            objectSID: "S-1-5-21-1234567890-1234567890-1234567890-1000",
            userAccountControl: 532480, // SERVER_TRUST_ACCOUNT + TRUSTED_FOR_DELEGATION
            isEnabled: true,
            accountExpires: nil,
            lastLogon: yesterday,
            logonCount: 15234,
            badPasswordCount: 0,
            badPasswordTime: nil,
            passwordLastSet: oneMonthAgo,
            isTrustedForDelegation: true,
            memberOf: [
                "CN=Domain Controllers,OU=Groups,DC=example,DC=local",
                "CN=Cert Publishers,OU=Groups,DC=example,DC=local"
            ],
            memberOfNames: ["Domain Controllers", "Cert Publishers"],
            primaryGroupID: 516,
            primaryGroup: "Domain Controllers",
            managedBy: "CN=Marie Martin,OU=IT,OU=Users,DC=example,DC=local",
            managedByName: "Marie Martin",
            distinguishedName: "CN=SRV-DC01,OU=Domain Controllers,DC=example,DC=local",
            objectGUID: "c4d5e6f7-a8b9-0123-def0-345678901234",
            whenCreated: oneYearAgo,
            whenChanged: yesterday,
            objectClass: ["top", "person", "organizationalPerson", "user", "computer"],
            ouID: serversOUID
        )
        
        let srv2 = ComputerDescriptor(
            id: UUID(),
            name: "SRV-FILE01",
            sAMAccountName: "SRV-FILE01$",
            dnsHostName: "srv-file01.example.local",
            description: "Serveur de fichiers",
            location: "Salle serveur",
            computerType: .server,
            operatingSystem: "Windows Server 2022 Standard",
            operatingSystemVersion: "10.0 (20348)",
            operatingSystemServicePack: nil,
            objectSID: "S-1-5-21-1234567890-1234567890-1234567890-3001",
            userAccountControl: 4096,
            isEnabled: true,
            accountExpires: nil,
            lastLogon: yesterday,
            logonCount: 8765,
            badPasswordCount: 0,
            badPasswordTime: nil,
            passwordLastSet: oneMonthAgo,
            isTrustedForDelegation: false,
            memberOf: ["CN=Domain Computers,OU=Groups,DC=example,DC=local"],
            memberOfNames: ["Domain Computers"],
            primaryGroupID: 515,
            primaryGroup: "Domain Computers",
            managedBy: "CN=John Doe,OU=IT,OU=Users,DC=example,DC=local",
            managedByName: "John Doe",
            distinguishedName: "CN=SRV-FILE01,OU=Servers,OU=Computers,DC=example,DC=local",
            objectGUID: "d5e6f7a8-b9c0-1234-ef01-456789012345",
            whenCreated: oneYearAgo,
            whenChanged: oneWeekAgo,
            objectClass: ["top", "person", "organizationalPerson", "user", "computer"],
            ouID: serversOUID
        )
        
        let srv3 = ComputerDescriptor(
            id: UUID(),
            name: "SRV-SQL01",
            sAMAccountName: "SRV-SQL01$",
            dnsHostName: "srv-sql01.example.local",
            description: "Serveur SQL Server",
            location: "Salle serveur",
            computerType: .server,
            operatingSystem: "Windows Server 2019 Standard",
            operatingSystemVersion: "10.0 (17763)",
            operatingSystemServicePack: nil,
            objectSID: "S-1-5-21-1234567890-1234567890-1234567890-3002",
            userAccountControl: 4096,
            isEnabled: true,
            accountExpires: nil,
            lastLogon: yesterday,
            logonCount: 4532,
            badPasswordCount: 0,
            badPasswordTime: nil,
            passwordLastSet: oneMonthAgo,
            isTrustedForDelegation: true,
            memberOf: ["CN=Domain Computers,OU=Groups,DC=example,DC=local"],
            memberOfNames: ["Domain Computers"],
            primaryGroupID: 515,
            primaryGroup: "Domain Computers",
            managedBy: "CN=John Doe,OU=IT,OU=Users,DC=example,DC=local",
            managedByName: "John Doe",
            distinguishedName: "CN=SRV-SQL01,OU=Servers,OU=Computers,DC=example,DC=local",
            objectGUID: "e6f7a8b9-c0d1-2345-f012-567890123456",
            whenCreated: oneYearAgo,
            whenChanged: oneWeekAgo,
            objectClass: ["top", "person", "organizationalPerson", "user", "computer"],
            ouID: serversOUID
        )
        
        computers = [ws1, ws2, ws3, srv1, srv2, srv3]
    }

    // MARK: - DirectoryConnector Protocol

    func fetchOUTree() throws -> [OUDescriptor] {
        return ous
    }

    func fetchObjects(in ouID: OUDescriptor.ID) throws -> (users: [UserDescriptor], groups: [GroupDescriptor], computers: [ComputerDescriptor]) {
        let u = users.filter { $0.ouID == ouID }
        let g = groups.filter { $0.ouID == ouID }
        let c = computers.filter { $0.ouID == ouID }
        return (u, g, c)
    }

    func searchObjects(query: String) throws -> [DirectorySearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let lower = trimmed.lowercased()

        let matchedUsers = users.filter {
            $0.sAMAccountName.lowercased().contains(lower) ||
            $0.displayName.lowercased().contains(lower) ||
            ($0.firstName?.lowercased().contains(lower) ?? false) ||
            ($0.lastName?.lowercased().contains(lower) ?? false) ||
            ($0.email?.lowercased().contains(lower) ?? false) ||
            ($0.department?.lowercased().contains(lower) ?? false) ||
            ($0.title?.lowercased().contains(lower) ?? false)
        }.map {
            DirectorySearchResult(
                id: $0.id,
                kind: .user,
                displayName: $0.fullName,
                secondaryText: $0.userPrincipalName ?? $0.sAMAccountName,
                distinguishedName: $0.distinguishedName
            )
        }
        
        let matchedGroups = groups.filter {
            $0.name.lowercased().contains(lower) ||
            $0.sAMAccountName.lowercased().contains(lower) ||
            ($0.description?.lowercased().contains(lower) ?? false)
        }.map {
            DirectorySearchResult(
                id: $0.id,
                kind: .group,
                displayName: $0.name,
                secondaryText: "\($0.groupScope.rawValue) - \($0.groupType.rawValue)",
                distinguishedName: $0.distinguishedName
            )
        }
        
        let matchedComputers = computers.filter {
            $0.name.lowercased().contains(lower) ||
            $0.sAMAccountName.lowercased().contains(lower) ||
            ($0.dnsHostName?.lowercased().contains(lower) ?? false) ||
            ($0.description?.lowercased().contains(lower) ?? false) ||
            ($0.operatingSystem?.lowercased().contains(lower) ?? false)
        }.map {
            DirectorySearchResult(
                id: $0.id,
                kind: .computer,
                displayName: $0.displayName,
                secondaryText: $0.osInfo,
                distinguishedName: $0.distinguishedName
            )
        }

        return matchedUsers + matchedGroups + matchedComputers
    }
    
    func fetchUserDetails(id: UserDescriptor.ID) throws -> UserDescriptor? {
        return users.first { $0.id == id }
    }
    
    func fetchGroupDetails(id: GroupDescriptor.ID) throws -> GroupDescriptor? {
        return groups.first { $0.id == id }
    }
    
    func fetchComputerDetails(id: ComputerDescriptor.ID) throws -> ComputerDescriptor? {
        return computers.first { $0.id == id }
    }
    
    func fetchAllUsers() throws -> [UserDescriptor] {
        return users
    }
    
    func fetchAllGroups() throws -> [GroupDescriptor] {
        return groups
    }
    
    func fetchAllComputers() throws -> [ComputerDescriptor] {
        return computers
    }
}
