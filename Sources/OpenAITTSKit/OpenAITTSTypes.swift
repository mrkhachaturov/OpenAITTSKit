import Foundation

/// Built-in voices for OpenAI TTS.
///
/// Preview voices at [openai.fm](https://openai.fm).
public enum OpenAITTSVoice: String, Codable, CaseIterable, Sendable {
    case alloy
    case ash
    case ballad
    case cedar
    case coral
    case echo
    case fable
    case marin
    case nova
    case onyx
    case sage
    case shimmer
    case verse
}

/// Available TTS models.
public enum OpenAITTSModel: String, Codable, CaseIterable, Sendable {
    case tts1 = "tts-1"
    case tts1HD = "tts-1-hd"
    case gpt4oMiniTTS = "gpt-4o-mini-tts"
    case gpt4oMiniTTS20251215 = "gpt-4o-mini-tts-2025-12-15"
}

/// Audio response formats supported by the OpenAI TTS API.
public enum OpenAITTSResponseFormat: String, Codable, CaseIterable, Sendable {
    case mp3
    case opus
    case aac
    case flac
    case wav
    case pcm
}

/// Request payload for OpenAI text-to-speech synthesis.
///
/// Supports both type-safe enum parameters and raw string passthrough
/// for dynamic configuration (e.g. gateway config, custom voice IDs).
public struct OpenAITTSRequest: Sendable {
    /// The TTS model to use.
    public let model: String
    /// The text to synthesize (max 4096 characters).
    public let input: String
    /// The voice to use (built-in name or custom voice ID).
    public let voice: OpenAITTSVoiceParam
    /// Audio output format.
    public let responseFormat: String?
    /// Playback speed (0.25–4.0). Defaults to 1.0.
    public let speed: Double?
    /// Voice style instructions (gpt-4o-mini-tts only).
    /// Does not work with tts-1 or tts-1-hd.
    public let instructions: String?

    /// Create a TTS request with type-safe enums.
    public init(
        model: OpenAITTSModel = .gpt4oMiniTTS,
        input: String,
        voice: OpenAITTSVoice = .alloy,
        responseFormat: OpenAITTSResponseFormat = .mp3,
        speed: Double? = nil,
        instructions: String? = nil
    ) {
        self.model = model.rawValue
        self.input = input
        self.voice = .builtin(voice)
        self.responseFormat = responseFormat.rawValue
        self.speed = Self.normalizeSpeed(speed)
        self.instructions = instructions?.isEmpty == true ? nil : instructions
    }

    /// Create a TTS request with a custom voice ID.
    public init(
        model: OpenAITTSModel = .gpt4oMiniTTS,
        input: String,
        customVoiceId: String,
        responseFormat: OpenAITTSResponseFormat = .mp3,
        speed: Double? = nil,
        instructions: String? = nil
    ) {
        self.model = model.rawValue
        self.input = input
        self.voice = .custom(id: customVoiceId)
        self.responseFormat = responseFormat.rawValue
        self.speed = Self.normalizeSpeed(speed)
        self.instructions = instructions?.isEmpty == true ? nil : instructions
    }

    /// Create a TTS request with raw string values (for gateway config passthrough).
    public init(
        modelId: String,
        input: String,
        voiceId: String,
        responseFormat: String = "mp3",
        speed: Double? = nil,
        instructions: String? = nil
    ) {
        self.model = modelId
        self.input = input
        self.voice = .raw(voiceId)
        self.responseFormat = responseFormat
        self.speed = Self.normalizeSpeed(speed)
        self.instructions = instructions?.isEmpty == true ? nil : instructions
    }

    /// Clamp speed to the valid range (0.25–4.0), defaulting to nil (API default 1.0).
    public static func normalizeSpeed(_ speed: Double?) -> Double? {
        guard let speed else { return nil }
        if speed < 0.25 { return 0.25 }
        if speed > 4.0 { return 4.0 }
        return speed
    }
}

// MARK: - Voice Parameter

/// Represents a voice for the TTS API.
///
/// The OpenAI API accepts either a string voice name (e.g. `"ash"`)
/// or an object with an `id` field for custom voices (e.g. `{"id": "voice_1234"}`).
public enum OpenAITTSVoiceParam: Sendable, Equatable {
    /// A built-in voice.
    case builtin(OpenAITTSVoice)
    /// A custom voice referenced by ID (e.g. `voice_1234`).
    case custom(id: String)
    /// A raw string value (for gateway config passthrough).
    case raw(String)
}

// MARK: - Codable

extension OpenAITTSRequest: Encodable {
    enum CodingKeys: String, CodingKey {
        case model, input, voice, speed, instructions
        case responseFormat = "response_format"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.model, forKey: .model)
        try container.encode(self.input, forKey: .input)
        try container.encode(self.voice, forKey: .voice)
        try container.encodeIfPresent(self.responseFormat, forKey: .responseFormat)
        try container.encodeIfPresent(self.speed, forKey: .speed)
        try container.encodeIfPresent(self.instructions, forKey: .instructions)
    }
}

extension OpenAITTSVoiceParam: Encodable {
    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .builtin(let voice):
            var container = encoder.singleValueContainer()
            try container.encode(voice.rawValue)
        case .custom(let id):
            var container = encoder.container(keyedBy: CustomVoiceCodingKeys.self)
            try container.encode(id, forKey: .id)
        case .raw(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        }
    }

    private enum CustomVoiceCodingKeys: String, CodingKey {
        case id
    }
}

// MARK: - Error Types

/// Structured error from the OpenAI TTS API.
public struct OpenAITTSError: Error, Sendable {
    /// HTTP status code.
    public let statusCode: Int
    /// Error message from the API.
    public let message: String
    /// Error type (e.g. "invalid_request_error").
    public let type: String?
    /// Error code (e.g. "invalid_api_key").
    public let code: String?

    public init(statusCode: Int, message: String, type: String? = nil, code: String? = nil) {
        self.statusCode = statusCode
        self.message = message
        self.type = type
        self.code = code
    }
}

extension OpenAITTSError: LocalizedError {
    public var errorDescription: String? {
        "OpenAI TTS failed (\(self.statusCode)): \(self.message)"
    }
}

/// JSON structure of OpenAI API error responses.
struct OpenAIAPIErrorResponse: Decodable {
    struct ErrorDetail: Decodable {
        let message: String?
        let type: String?
        let code: String?
    }
    let error: ErrorDetail?
}
