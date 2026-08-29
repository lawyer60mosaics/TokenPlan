import Foundation

struct ProfileStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load() throws -> [Profile] {
        let url = try fileURL()
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([Profile].self, from: Data(contentsOf: url))
    }

    func save(_ profiles: [Profile]) throws {
        try validate(profiles)
        let url = try fileURL()
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        let data = try JSONEncoder().encode(profiles)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    func validate(_ profiles: [Profile]) throws {
        var ids = Set<String>()
        for profile in profiles {
            try profile.validate()
            guard ids.insert(profile.id).inserted else { throw TokenPlanError.invalidProfiles }
        }
    }

    private func fileURL() throws -> URL {
        guard let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return directory.appendingPathComponent("TokenPlan", isDirectory: true)
            .appendingPathComponent("profiles.json")
    }
}
