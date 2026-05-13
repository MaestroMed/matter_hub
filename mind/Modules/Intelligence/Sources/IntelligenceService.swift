import Foundation
import GraphCore

@MainActor
@Observable
public final class IntelligenceService {
    public var onDevice: OnDeviceIntelligence
    public var cloud: CloudIntelligence

    public init(
        onDevice: OnDeviceIntelligence = OnDeviceIntelligence(),
        cloud: CloudIntelligence = CloudIntelligence()
    ) {
        self.onDevice = onDevice
        self.cloud = cloud
    }

    public func autoTag(text: String) async -> [String] {
        await onDevice.autoTag(text: text)
    }

    public func summarize(text: String) async -> String? {
        await onDevice.summarize(text: text)
    }

    public func ask(_ prompt: String, contextNodes: [Node] = []) async throws -> String {
        try await cloud.complete(prompt: prompt, contextNodes: contextNodes)
    }
}
