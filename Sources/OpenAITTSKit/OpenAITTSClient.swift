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
    /// Timeout for streaming synthesis requests.
    public let requestTimeoutSeconds: TimeInterval
    /// Maximum retry attempts for retryable errors (429, 5xx).
    public let maxRetries: Int

    private let urlSession: URLSession

    private static let defaultBaseUrl = "https://api.openai.com/v1"
    private static let defaultTimeoutSeconds: TimeInterval = 30
    private static let defaultMaxRetries = 3
    private static let streamChunkSize = 2048
    private static let retryDelays: [TimeInterval] = [0.25, 0.75, 1.5]

    /// Creates a client.
    ///
    /// - Parameters:
    ///   - apiKey: OpenAI API key.
    ///   - baseUrl: Base URL for the API (defaults to `https://api.openai.com/v1`).
    ///   - requestTimeoutSeconds: Timeout for synthesis requests (default 30s).
    ///   - maxRetries: Maximum retry attempts for retryable errors (default 3).
    ///   - urlSession: URL session to use (defaults to `.shared` for connection pooling).
    public init(
        apiKey: String,
        baseUrl: String? = nil,
        requestTimeoutSeconds: TimeInterval = 30,
        maxRetries: Int = 3,
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey
        let raw = (baseUrl ?? Self.defaultBaseUrl)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseUrl = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.maxRetries = maxRetries
        self.urlSession = urlSession
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
        body: Data,
        timeoutSeconds: TimeInterval = 30
    ) -> URLRequest {
        let trimmed = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        let url = URL(string: "\(trimmed)/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    // MARK: - Error Parsing

    /// Parse an OpenAI API error response.
    public static func parseAPIError(statusCode: Int, data: Data) -> OpenAITTSError {
        if let parsed = try? JSONDecoder().decode(OpenAIAPIErrorResponse.self, from: data),
           let detail = parsed.error {
            return OpenAITTSError(
                statusCode: statusCode,
                message: detail.message ?? "Unknown error",
                type: detail.type,
                code: detail.code)
        }
        let fallback = String(data: data.prefix(4096), encoding: .utf8) ?? "Unknown error"
        return OpenAITTSError(
            statusCode: statusCode,
            message: fallback.replacingOccurrences(of: "\n", with: " "))
    }

    /// Whether an HTTP status code is retryable (429 rate limit or 5xx server error).
    static func isRetryableStatus(_ statusCode: Int) -> Bool {
        statusCode == 429 || statusCode >= 500
    }

    // MARK: - Non-Streaming Synthesis

    /// Synthesize speech and return the full audio data.
    ///
    /// Use this when you don't need streaming playback and prefer to
    /// download the complete audio before playing.
    public func synthesize(_ request: OpenAITTSRequest) async throws -> Data {
        let body = try Self.encodeRequestBody(request)
        let urlRequest = Self.buildURLRequest(
            baseUrl: self.baseUrl,
            apiKey: self.apiKey,
            body: body,
            timeoutSeconds: self.requestTimeoutSeconds
        )

        var lastError: Error?
        for attempt in 0..<self.maxRetries {
            do {
                let (data, response) = try await self.urlSession.data(for: urlRequest)
                guard let http = response as? HTTPURLResponse else {
                    throw OpenAITTSError(statusCode: -1, message: "Non-HTTP response")
                }
                if Self.isRetryableStatus(http.statusCode) {
                    lastError = Self.parseAPIError(statusCode: http.statusCode, data: data)
                    if attempt < self.maxRetries - 1 {
                        let retryAfter = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "")
                        let baseDelay = Self.retryDelays[min(attempt, Self.retryDelays.count - 1)]
                        try await Task.sleep(nanoseconds: UInt64(max(baseDelay, retryAfter ?? 0) * 1_000_000_000))
                        continue
                    }
                    throw lastError!
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw Self.parseAPIError(statusCode: http.statusCode, data: data)
                }
                return data
            } catch let error as OpenAITTSError {
                throw error
            } catch {
                lastError = error
                if attempt < self.maxRetries - 1 {
                    let delay = Self.retryDelays[min(attempt, Self.retryDelays.count - 1)]
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                throw error
            }
        }
        throw lastError ?? OpenAITTSError(statusCode: -1, message: "Synthesis failed")
    }

    // MARK: - Streaming Synthesis

    /// Stream synthesized audio from the OpenAI TTS API.
    ///
    /// Returns an `AsyncThrowingStream<Data, Error>` of audio chunks (~2KB each).
    /// The caller feeds chunks to an audio player for incremental playback.
    /// Retries automatically on 429/5xx errors with exponential backoff.
    public func streamSynthesize(_ request: OpenAITTSRequest) -> AsyncThrowingStream<Data, Error> {
        let body: Data
        do {
            body = try Self.encodeRequestBody(request)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }

        let baseUrl = self.baseUrl
        let apiKey = self.apiKey
        let timeout = self.requestTimeoutSeconds
        let session = self.urlSession
        let maxRetries = self.maxRetries

        return AsyncThrowingStream { continuation in
            let task = Task {
                var lastError: Error?

                for attempt in 0..<maxRetries {
                    let urlRequest = Self.buildURLRequest(
                        baseUrl: baseUrl,
                        apiKey: apiKey,
                        body: body,
                        timeoutSeconds: timeout
                    )

                    do {
                        let (bytes, response) = try await session.bytes(for: urlRequest)

                        guard let http = response as? HTTPURLResponse else {
                            throw OpenAITTSError(statusCode: -1, message: "Non-HTTP response")
                        }

                        if Self.isRetryableStatus(http.statusCode) {
                            var errorBody = Data()
                            for try await byte in bytes {
                                errorBody.append(byte)
                                if errorBody.count >= 4096 { break }
                            }
                            lastError = Self.parseAPIError(statusCode: http.statusCode, data: errorBody)
                            if attempt < maxRetries - 1 {
                                let retryAfter = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "")
                                let baseDelay = Self.retryDelays[min(attempt, Self.retryDelays.count - 1)]
                                try await Task.sleep(nanoseconds: UInt64(max(baseDelay, retryAfter ?? 0) * 1_000_000_000))
                                continue
                            }
                            continuation.finish(throwing: lastError!)
                            return
                        }

                        guard (200..<300).contains(http.statusCode) else {
                            var errorBody = Data()
                            for try await byte in bytes {
                                errorBody.append(byte)
                                if errorBody.count >= 4096 { break }
                            }
                            continuation.finish(throwing: Self.parseAPIError(statusCode: http.statusCode, data: errorBody))
                            return
                        }

                        // Stream audio chunks.
                        var buffer = Data()
                        buffer.reserveCapacity(Self.streamChunkSize)
                        for try await byte in bytes {
                            try Task.checkCancellation()
                            buffer.append(byte)
                            if buffer.count >= Self.streamChunkSize {
                                continuation.yield(buffer)
                                buffer.removeAll(keepingCapacity: true)
                            }
                        }
                        if !buffer.isEmpty {
                            continuation.yield(buffer)
                        }
                        continuation.finish()
                        return
                    } catch is CancellationError {
                        continuation.finish(throwing: CancellationError())
                        return
                    } catch {
                        lastError = error
                        if attempt < maxRetries - 1 {
                            let delay = Self.retryDelays[min(attempt, Self.retryDelays.count - 1)]
                            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                            continue
                        }
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish(throwing: lastError ?? OpenAITTSError(statusCode: -1, message: "Synthesis failed"))
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Convenience

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

    /// Convenience: synthesize (non-streaming) with type-safe parameters.
    public func synthesize(
        model: OpenAITTSModel = .gpt4oMiniTTS,
        voice: OpenAITTSVoice = .alloy,
        text: String,
        speed: Double? = nil,
        instructions: String? = nil,
        responseFormat: OpenAITTSResponseFormat = .mp3
    ) async throws -> Data {
        try await self.synthesize(OpenAITTSRequest(
            model: model,
            input: text,
            voice: voice,
            responseFormat: responseFormat,
            speed: speed,
            instructions: instructions
        ))
    }
}
