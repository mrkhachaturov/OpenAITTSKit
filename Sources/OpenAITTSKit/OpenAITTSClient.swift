import Foundation

/// Streaming TTS client for the OpenAI audio/speech API.
///
/// Usage:
/// ```swift
/// let client = OpenAITTSClient(apiKey: "sk-...")
/// let stream = client.streamSynthesize(
///     OpenAITTSRequest(input: "Hello", voice: .ash)
/// )
/// for try await chunk in stream {
///     player.enqueue(chunk)
/// }
/// ```
public final class OpenAITTSClient: Sendable {
    public let apiKey: String
    public let baseUrl: String

    private static let defaultBaseUrl = "https://api.openai.com/v1"
    private static let defaultTimeoutSeconds: TimeInterval = 30
    private static let streamChunkSize = 2048

    public init(apiKey: String, baseUrl: String? = nil) {
        self.apiKey = apiKey
        let raw = (baseUrl ?? Self.defaultBaseUrl)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseUrl = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
    }

    // MARK: - Request Building

    /// Encode the request as JSON data.
    public static func encodeRequestBody(_ request: OpenAITTSRequest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        return try encoder.encode(request)
    }

    /// Build a URLRequest for the audio/speech endpoint.
    public static func buildURLRequest(
        baseUrl: String,
        apiKey: String,
        body: Data
    ) -> URLRequest {
        let trimmed = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        let url = URL(string: "\(trimmed)/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    // MARK: - Error Parsing

    /// Parse an OpenAI API error response.
    static func parseAPIError(statusCode: Int, data: Data) -> OpenAITTSError {
        if let parsed = try? JSONDecoder().decode(OpenAIAPIErrorResponse.self, from: data),
           let detail = parsed.error {
            return OpenAITTSError(
                statusCode: statusCode,
                message: detail.message ?? "Unknown error",
                type: detail.type,
                code: detail.code)
        }
        let fallback = String(data: data, encoding: .utf8) ?? "Unknown error"
        return OpenAITTSError(statusCode: statusCode, message: fallback)
    }

    // MARK: - Streaming Synthesis

    /// Stream synthesized audio from the OpenAI TTS API.
    ///
    /// Returns an `AsyncThrowingStream<Data, Error>` of audio chunks.
    /// Each chunk is up to 8KB. The caller feeds chunks to an audio player
    /// for incremental playback.
    public func streamSynthesize(_ request: OpenAITTSRequest) -> AsyncThrowingStream<Data, Error> {
        let body: Data
        do {
            body = try Self.encodeRequestBody(request)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        let urlRequest = Self.buildURLRequest(
            baseUrl: self.baseUrl,
            apiKey: self.apiKey,
            body: body
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let config = URLSessionConfiguration.default
                    config.timeoutIntervalForRequest = Self.defaultTimeoutSeconds
                    let session = URLSession(configuration: config)
                    let (bytes, response) = try await session.bytes(for: urlRequest)

                    guard let http = response as? HTTPURLResponse else {
                        throw OpenAITTSError(statusCode: -1, message: "Non-HTTP response")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var errorBody = Data()
                        for try await byte in bytes { errorBody.append(byte) }
                        throw Self.parseAPIError(statusCode: http.statusCode, data: errorBody)
                    }

                    var buffer = Data()
                    buffer.reserveCapacity(Self.streamChunkSize)
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        buffer.append(byte)
                        if buffer.count >= Self.streamChunkSize {
                            continuation.yield(buffer)
                            buffer = Data()
                            buffer.reserveCapacity(Self.streamChunkSize)
                        }
                    }
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Convenience: stream with type-safe parameters.
    public func streamSynthesize(
        model: OpenAITTSModel = .gpt4oMiniTTS,
        voice: OpenAITTSVoice = .alloy,
        text: String,
        speed: Double? = nil,
        instructions: String? = nil,
        responseFormat: OpenAITTSResponseFormat = .mp3
    ) -> AsyncThrowingStream<Data, Error> {
        self.streamSynthesize(OpenAITTSRequest(
            model: model,
            input: text,
            voice: voice,
            responseFormat: responseFormat,
            speed: speed,
            instructions: instructions
        ))
    }

    /// Convenience: stream with raw string parameters (for gateway config passthrough).
    public func streamSynthesize(
        model: String,
        voice: String,
        text: String,
        speed: Double? = nil,
        instructions: String? = nil,
        responseFormat: String = "mp3"
    ) -> AsyncThrowingStream<Data, Error> {
        self.streamSynthesize(OpenAITTSRequest(
            modelId: model,
            input: text,
            voiceId: voice,
            responseFormat: responseFormat,
            speed: speed,
            instructions: instructions
        ))
    }
}
