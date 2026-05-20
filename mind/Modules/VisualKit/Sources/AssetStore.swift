import Foundation
import GraphCore

public enum AssetStoreError: Error, LocalizedError, Sendable {
    case noContainer
    case writeFailed(String)
    case readFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noContainer:
            return "Pas de container App Group disponible (Simulator non signé ?). Les images seront tout de même générées en mémoire."
        case .writeFailed(let path): return "Écriture impossible: \(path)"
        case .readFailed(let path):  return "Lecture impossible: \(path)"
        }
    }
}

/// Local filesystem cache for the generated visual concepts. Stores
/// every client's board under `<AppGroup>/Documents/visual-boards/<clientNodeID>/`
/// with one PNG per concept + a `manifest.json` describing the set.
///
/// Falls back to the app's own Documents directory when the App Group
/// container isn't available (unsigned Simulator) so the feature still
/// works for dev iteration — just doesn't sync across processes.
public enum AssetStore {
    private static let boardsFolder = "visual-boards"
    private static let manifestFilename = "manifest.json"

    // MARK: - Public API

    public static func writeImage(
        data: Data,
        filename: String,
        for clientKey: String
    ) throws -> URL {
        let dir = try directory(for: clientKey)
        let url = dir.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw AssetStoreError.writeFailed(url.path)
        }
    }

    public static func imageURL(
        filename: String,
        for clientKey: String
    ) -> URL? {
        guard let dir = try? directory(for: clientKey) else { return nil }
        let url = dir.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public static func writeManifest(_ manifest: VisualBoardManifest) throws -> URL {
        let dir = try directory(for: manifest.clientKey)
        let url = dir.appendingPathComponent(manifestFilename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(manifest)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw AssetStoreError.writeFailed(url.path)
        }
    }

    public static func readManifest(for clientKey: String) -> VisualBoardManifest? {
        guard let dir = try? directory(for: clientKey) else { return nil }
        let url = dir.appendingPathComponent(manifestFilename)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(VisualBoardManifest.self, from: data)
    }

    public static func clearBoard(for clientKey: String) {
        guard let dir = try? directory(for: clientKey) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Directory resolution

    private static func directory(for clientKey: String) throws -> URL {
        let root = try baseDirectory()
        let folder = root
            .appendingPathComponent(boardsFolder, isDirectory: true)
            .appendingPathComponent(clientKey, isDirectory: true)

        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true
            )
        }
        return folder
    }

    /// Prefer the App-Group-shared Documents folder so the widget
    /// extension (and any future Watch / Mac target) can read the same
    /// generated assets. Falls back to the app's private Documents on
    /// unsigned Simulators where the App Group entitlement isn't vended.
    private static func baseDirectory() throws -> URL {
        if let shared = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: GraphCore.appGroupIdentifier
        ) {
            let documents = shared.appendingPathComponent("Documents", isDirectory: true)
            if !FileManager.default.fileExists(atPath: documents.path) {
                try FileManager.default.createDirectory(
                    at: documents, withIntermediateDirectories: true
                )
            }
            return documents
        }
        // Local fallback
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard let local = urls.first else {
            throw AssetStoreError.noContainer
        }
        return local
    }
}
