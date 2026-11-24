import Foundation

struct HealthIncident: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    let at: Date
    let summary: String
}

/// One stored ride. No raw audio and no location is stored here.
struct RideSession: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    let detectorName: String
    let detectorIsSimulated: Bool
    let microphoneEnabled: Bool
    let microphonePreference: MicrophonePreference
    var groupName: String?
    var counts = AlertCounts()
    var healthIncidents: [HealthIncident] = []
    var locationSharingUsed = false

    var duration: TimeInterval? {
        endedAt.map { $0.timeIntervalSince(startedAt) }
    }
}

protocol RideStoring: Sendable {
    func load() throws -> [RideSession]
    func save(_ rides: [RideSession]) throws
}

/// JSON file in Application Support, excluded from backup.
struct JSONFileRideStore: RideStoring {
    let url: URL

    static func defaultURL() throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("RideAware", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("rides.json")
    }

    func load() throws -> [RideSession] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([RideSession].self, from: data)
    }

    func save(_ rides: [RideSession]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(rides).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }
}

/// Stored ride sessions.
@MainActor
@Observable
final class RideHistory {
    private(set) var rides: [RideSession] = []
    private(set) var lastError: String?
    @ObservationIgnored private let store: any RideStoring

    init(store: any RideStoring) {
        self.store = store
        do {
            rides = try store.load().sorted { $0.startedAt > $1.startedAt }
        } catch {
            lastError = "Could not load rides: \(error.localizedDescription)"
        }
    }

    func record(_ ride: RideSession) {
        rides.insert(ride, at: 0)
        persist()
    }

    func delete(ids: Set<UUID>) {
        rides.removeAll { ids.contains($0.id) }
        persist()
    }

    func deleteAll() {
        rides.removeAll()
        persist()
    }

    private func persist() {
        do {
            try store.save(rides)
            lastError = nil
        } catch {
            lastError = "Could not save rides: \(error.localizedDescription)"
        }
    }
}
