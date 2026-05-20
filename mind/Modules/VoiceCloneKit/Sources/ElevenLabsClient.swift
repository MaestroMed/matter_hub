import Foundation
import GraphCore

/// Pure value type returned by `ElevenLabsClient.listVoices()`. Decoded
/// from the `voices[]` array of `GET /v1/voices`. Only the fields we
/// actually consume in the iOS Settings + AuditSheet are surfaced —
/// the upstream payload ships much more (samples, settings, fine
/// tuning state) that we don't need today.
public struct ElevenLabsVoice: Sendable, Codable, Identifiable, Hashable {
    public let id: String                // voice_id
    public let name: String
    public let category: String?         // "cloned" / "professional" / "premade"
    public let previewURL: String?

    public init(id: String, name: String, category: String? = nil, previewURL: String? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.previewURL = previewURL
    }

    /// Custom decoder so the upstream `voice_id` / `preview_url` keys
    /// map onto Swift idiomatic names without forcing the consumer to
    /// reach for snake_case property names everywhere.
    private enum CodingKeys: String, CodingKey {
        case id = "voice_id"
        case name
        case category
        case previewURL = "preview_url"
    }
}

/// Errors surfaced by `ElevenLabsClient`. Cases map 1-to-1 onto the
/// failure modes the UI cares about — the Settings "Tester la voix"
/// CTA and the AuditSheet "Générer le pitch audio" CTA both render
/// the case as a short toast.
public enum ElevenLabsClientError: Error, Sendable, Equatable {
    /// `ElevenLabsTokenStore.read()` returned nil — the user hasn't
    /// pasted an API key yet.
    case noToken

    /// Any non-2xx HTTP response. The status code + decoded server
    /// message (when present) get preserved so the UI can surface
    /// them in error toasts.
    case http(Int, message: String)

    /// JSONSerialization or response decoding failed.
    case decoding(String)

    /// The voice sample bytes don't look like a valid container
    /// ElevenLabs would accept (empty / way too short).
    case audioFormat

    public static func == (lhs: ElevenLabsClientError, rhs: ElevenLabsClientError) -> Bool {
        switch (lhs, rhs) {
        case (.noToken, .noToken), (.audioFormat, .audioFormat):
            return true
        case let (.http(a1, m1), .http(a2, m2)):
            return a1 == a2 && m1 == m2
        case let (.decoding(a), .decoding(b)):
            return a == b
        default:
            return false
        }
    }
}

/// Actor that owns every outbound ElevenLabs API call.
///
/// Why an actor?
/// -------------
/// The client holds no mutable state beyond its `URLSession` reference
/// today, but keeping it as an actor leaves room for v1.0-alpha.18.x
/// retry queues, per-character usage accounting, and the eventual
/// streaming-MP3 swap without breaking call sites. Every call site
/// already awaits the methods, so the boundary stays clean.
public actor ElevenLabsClient {
    /// Shared instance used by Settings + AuditSheet. The UI never
    /// constructs its own — keeping a single instance means a future
    /// retry queue / rate-limit bucket can live on the actor without
    /// duplicating state.
    public static let shared = ElevenLabsClient()

    /// Base URL pinned to the v1 endpoint. ElevenLabs guarantees
    /// forward-compatibility for the `xi-api-key` header on v1 so
    /// pinning here is the safe move.
    static let baseURL: URL = URL(string: "https://api.elevenlabs.io")!

    /// Default cloud model. `eleven_multilingual_v2` carries excellent
    /// French phonetic support — Mehdi pitches in FR and the model
    /// keeps the accent intact instead of flattening it to English.
    public static let defaultModelID: String = "eleven_multilingual_v2"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// Uploads a voice sample WAV file (or any other accepted
    /// container — MP3 / FLAC / WebM / Ogg) to create a cloned
    /// voice. Returns the new `voice_id` on success so the caller
    /// can persist it in `MINDPreferences.elevenLabsVoiceID`.
    public func cloneVoice(
        name: String,
        description: String,
        sampleWAVData: Data
    ) async throws -> String {
        guard let token = ElevenLabsTokenStore.read(), !token.isEmpty else {
            throw ElevenLabsClientError.noToken
        }
        // Anything under ~10 KB is almost certainly garbage — ElevenLabs
        // recommends 1-3 minutes for the best clone quality, and even a
        // 5-second 44.1kHz mono PCM 16-bit clip is ~880 KB.
        guard sampleWAVData.count >= 10_000 else {
            throw ElevenLabsClientError.audioFormat
        }

        let url = Self.baseURL.appendingPathComponent("v1/voices/add")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "xi-api-key")

        let boundary = "MIND-Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.buildCloneMultipartBody(
            boundary: boundary,
            name: name,
            description: description,
            sampleWAVData: sampleWAVData
        )

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ElevenLabsClientError.http(0, message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ElevenLabsClientError.decoding("response is not HTTPURLResponse")
        }
        switch http.statusCode {
        case 200..<300:
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let voiceID = json["voice_id"] as? String,
                !voiceID.isEmpty
            else {
                throw ElevenLabsClientError.decoding("voice_id missing from response")
            }
            return voiceID
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ElevenLabsClientError.http(http.statusCode, message: body)
        }
    }

    /// Synthesizes `text` with a previously-cloned voice. Returns the
    /// raw MP3 bytes on success — the UI persists those to
    /// `Documents/audit-audio/<auditID>.mp3` and plays them via
    /// AVAudioPlayer. The portal HTML inlines them as a base64
    /// data URL so the bundle stays single-folder self-contained.
    public func synthesize(
        voiceID: String,
        text: String,
        modelID: String = ElevenLabsClient.defaultModelID
    ) async throws -> Data {
        guard let token = ElevenLabsTokenStore.read(), !token.isEmpty else {
            throw ElevenLabsClientError.noToken
        }

        let url = Self.baseURL.appendingPathComponent("v1/text-to-speech/\(voiceID)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "xi-api-key")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = Self.buildSynthesisPayload(text: text, modelID: modelID)
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            throw ElevenLabsClientError.decoding("payload encode failed: \(error.localizedDescription)")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ElevenLabsClientError.http(0, message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ElevenLabsClientError.decoding("response is not HTTPURLResponse")
        }
        switch http.statusCode {
        case 200..<300:
            // ElevenLabs returns raw MP3 bytes when Accept: audio/mpeg.
            // Empty body would be an upstream bug — guard against it.
            guard !data.isEmpty else {
                throw ElevenLabsClientError.decoding("empty audio response")
            }
            return data
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ElevenLabsClientError.http(http.statusCode, message: body)
        }
    }

    /// Lists the user's voices via `GET /v1/voices` so the Settings
    /// flow can detect whether "Mehdi Nafaa" already exists before
    /// uploading a fresh sample. Decodes the upstream `voices[]`
    /// array into our pure `ElevenLabsVoice` value type.
    public func listVoices() async throws -> [ElevenLabsVoice] {
        guard let token = ElevenLabsTokenStore.read(), !token.isEmpty else {
            throw ElevenLabsClientError.noToken
        }
        let url = Self.baseURL.appendingPathComponent("v1/voices")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "xi-api-key")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ElevenLabsClientError.http(0, message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ElevenLabsClientError.decoding("response is not HTTPURLResponse")
        }
        switch http.statusCode {
        case 200..<300:
            return try Self.decodeVoices(from: data)
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ElevenLabsClientError.http(http.statusCode, message: body)
        }
    }

    /// `GET /v1/user`. Returns true on 200, false on 401 or any
    /// transport failure — used by Settings to surface the green/red
    /// dot next to the saved key.
    public func validateToken() async -> Bool {
        guard let token = ElevenLabsTokenStore.read(), !token.isEmpty else {
            return false
        }
        let url = Self.baseURL.appendingPathComponent("v1/user")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "xi-api-key")

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Pure helpers (exposed for tests)

    /// Builds the multipart/form-data body for `POST /v1/voices/add`.
    /// Exposed as a static so `ElevenLabsClientTests` can lock the
    /// byte shape (boundary placement, name + description fields,
    /// file field with sample.wav filename + audio/wav content type)
    /// without spinning up a URLSession.
    public static func buildCloneMultipartBody(
        boundary: String,
        name: String,
        description: String,
        sampleWAVData: Data
    ) -> Data {
        var body = Data()
        let crlf = "\r\n"
        // name field
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"name\"\(crlf)\(crlf)".data(using: .utf8)!)
        body.append("\(name)\(crlf)".data(using: .utf8)!)
        // description field
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"description\"\(crlf)\(crlf)".data(using: .utf8)!)
        body.append("\(description)\(crlf)".data(using: .utf8)!)
        // sample file
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"files\"; filename=\"sample.wav\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(sampleWAVData)
        body.append(crlf.data(using: .utf8)!)
        // closing boundary
        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)
        return body
    }

    /// Builds the JSON payload for `POST /v1/text-to-speech/<voice_id>`.
    /// Exposed so `ElevenLabsClientTests` can lock the shape (text +
    /// model_id + voice_settings) without an HTTP round-trip.
    public static func buildSynthesisPayload(
        text: String,
        modelID: String
    ) -> [String: Any] {
        return [
            "text": text,
            "model_id": modelID,
            // Tuned for the pitch use case — stability 0.5 keeps the
            // delivery consistent across paragraphs, similarity boost
            // 0.75 keeps the timbre close to the source sample without
            // making the audio feel robotic, style 0 leaves the
            // emotional default untouched, speaker_boost true keeps
            // the voice clearly distinguishable from any background
            // noise the listener might have on the other side.
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75,
                "style": 0.0,
                "use_speaker_boost": true,
            ],
        ]
    }

    /// Pure JSON → `[ElevenLabsVoice]` decoder. Exposed so the tests
    /// can exercise the parsing logic with a sample payload without
    /// hitting the network.
    public static func decodeVoices(from data: Data) throws -> [ElevenLabsVoice] {
        do {
            let decoder = JSONDecoder()
            struct Envelope: Decodable {
                let voices: [ElevenLabsVoice]
            }
            return try decoder.decode(Envelope.self, from: data).voices
        } catch {
            throw ElevenLabsClientError.decoding(error.localizedDescription)
        }
    }
}
