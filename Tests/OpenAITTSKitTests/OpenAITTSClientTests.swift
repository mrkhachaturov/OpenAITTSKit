import Foundation
import Testing
@testable import OpenAITTSKit

@Suite struct OpenAITTSRequestTests {
    @Test func encodesRequiredFields() throws {
        let request = OpenAITTSRequest(model: .gpt4oMiniTTS, input: "Hello", voice: .ash)
        let data = try OpenAITTSClient.encodeRequestBody(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["model"] as? String == "gpt-4o-mini-tts")
        #expect(json["voice"] as? String == "ash")
        #expect(json["input"] as? String == "Hello")
        #expect(json["response_format"] as? String == "mp3")
    }

    @Test func encodesOptionalFields() throws {
        let request = OpenAITTSRequest(
            model: .gpt4oMiniTTS,
            input: "Test",
            voice: .alloy,
            speed: 1.5,
            instructions: "Speak calmly"
        )
        let data = try OpenAITTSClient.encodeRequestBody(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["speed"] as? Double == 1.5)
        #expect(json["instructions"] as? String == "Speak calmly")
    }

    @Test func omitsEmptyInstructions() throws {
        let request = OpenAITTSRequest(model: .tts1, input: "Hi", voice: .nova, instructions: "")
        let data = try OpenAITTSClient.encodeRequestBody(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["instructions"] == nil)
    }

    @Test func rawStringInit() throws {
        let request = OpenAITTSRequest(
            modelId: "custom-model",
            input: "Hello",
            voiceId: "custom-voice",
            responseFormat: "opus"
        )
        let data = try OpenAITTSClient.encodeRequestBody(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["model"] as? String == "custom-model")
        #expect(json["voice"] as? String == "custom-voice")
        #expect(json["response_format"] as? String == "opus")
    }

    @Test func customVoiceIdEncodesAsObject() throws {
        let request = OpenAITTSRequest(
            input: "Hello",
            customVoiceId: "voice_1234"
        )
        let data = try OpenAITTSClient.encodeRequestBody(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let voice = json["voice"] as? [String: Any]
        #expect(voice?["id"] as? String == "voice_1234")
    }

    @Test func builtinVoiceEncodesAsString() throws {
        let request = OpenAITTSRequest(input: "Hello", voice: .coral)
        let data = try OpenAITTSClient.encodeRequestBody(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["voice"] as? String == "coral")
    }
}

@Suite struct OpenAITTSSpeedTests {
    @Test func normalSpeedPassesThrough() {
        #expect(OpenAITTSRequest.normalizeSpeed(1.0) == 1.0)
        #expect(OpenAITTSRequest.normalizeSpeed(2.5) == 2.5)
    }

    @Test func nilSpeedReturnsNil() {
        #expect(OpenAITTSRequest.normalizeSpeed(nil) == nil)
    }

    @Test func clampsToMinimum() {
        #expect(OpenAITTSRequest.normalizeSpeed(0.1) == 0.25)
        #expect(OpenAITTSRequest.normalizeSpeed(-1.0) == 0.25)
    }

    @Test func clampsToMaximum() {
        #expect(OpenAITTSRequest.normalizeSpeed(5.0) == 4.0)
        #expect(OpenAITTSRequest.normalizeSpeed(100.0) == 4.0)
    }

    @Test func boundaryValues() {
        #expect(OpenAITTSRequest.normalizeSpeed(0.25) == 0.25)
        #expect(OpenAITTSRequest.normalizeSpeed(4.0) == 4.0)
    }
}

@Suite struct OpenAITTSURLRequestTests {
    @Test func setsCorrectHeaders() {
        let request = OpenAITTSClient.buildURLRequest(
            baseUrl: "https://api.openai.com/v1",
            apiKey: "sk-test-key",
            body: Data()
        )
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/audio/speech")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func handlesCustomBaseUrl() {
        let request = OpenAITTSClient.buildURLRequest(
            baseUrl: "https://my-proxy.example.com/v1",
            apiKey: "sk-test",
            body: Data()
        )
        #expect(request.url?.absoluteString == "https://my-proxy.example.com/v1/audio/speech")
    }

    @Test func stripsTrailingSlash() {
        let request = OpenAITTSClient.buildURLRequest(
            baseUrl: "https://api.openai.com/v1/",
            apiKey: "sk-test",
            body: Data()
        )
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/audio/speech")
    }
}

@Suite struct OpenAITTSClientTests {
    @Test func defaultBaseUrl() {
        let client = OpenAITTSClient(apiKey: "sk-test")
        #expect(client.baseUrl == "https://api.openai.com/v1")
    }

    @Test func customBaseUrl() {
        let client = OpenAITTSClient(apiKey: "sk-test", baseUrl: "https://proxy.local/v1")
        #expect(client.baseUrl == "https://proxy.local/v1")
    }

    @Test func customBaseUrlTrimsTrailingSlash() {
        let client = OpenAITTSClient(apiKey: "sk-test", baseUrl: "https://proxy.local/v1/")
        #expect(client.baseUrl == "https://proxy.local/v1")
    }
}

@Suite struct OpenAITTSErrorTests {
    @Test func parsesStructuredAPIError() {
        let json = """
        {"error":{"message":"Invalid API key","type":"invalid_request_error","code":"invalid_api_key"}}
        """
        let error = OpenAITTSClient.parseAPIError(statusCode: 401, data: json.data(using: .utf8)!)
        #expect(error.statusCode == 401)
        #expect(error.message == "Invalid API key")
        #expect(error.type == "invalid_request_error")
        #expect(error.code == "invalid_api_key")
    }

    @Test func fallsBackToRawTextOnInvalidJSON() {
        let raw = "Something went wrong"
        let error = OpenAITTSClient.parseAPIError(statusCode: 500, data: raw.data(using: .utf8)!)
        #expect(error.statusCode == 500)
        #expect(error.message == "Something went wrong")
        #expect(error.type == nil)
    }

    @Test func errorDescription() {
        let error = OpenAITTSError(statusCode: 403, message: "Quota exceeded")
        #expect(error.localizedDescription == "OpenAI TTS failed (403): Quota exceeded")
    }
}

@Suite struct OpenAITTSVoiceTests {
    @Test func allBuiltinVoices() {
        let voices = OpenAITTSVoice.allCases
        #expect(voices.count == 13)
        #expect(voices.contains(.ash))
        #expect(voices.contains(.marin))
        #expect(voices.contains(.cedar))
    }

    @Test func voiceParamEquality() {
        #expect(OpenAITTSVoiceParam.builtin(.ash) == OpenAITTSVoiceParam.builtin(.ash))
        #expect(OpenAITTSVoiceParam.custom(id: "v1") == OpenAITTSVoiceParam.custom(id: "v1"))
        #expect(OpenAITTSVoiceParam.builtin(.ash) != OpenAITTSVoiceParam.raw("ash"))
    }
}

@Suite struct OpenAITTSModelTests {
    @Test func modelRawValues() {
        #expect(OpenAITTSModel.tts1.rawValue == "tts-1")
        #expect(OpenAITTSModel.tts1HD.rawValue == "tts-1-hd")
        #expect(OpenAITTSModel.gpt4oMiniTTS.rawValue == "gpt-4o-mini-tts")
        #expect(OpenAITTSModel.gpt4oMiniTTS20251215.rawValue == "gpt-4o-mini-tts-2025-12-15")
    }

    @Test func allModels() {
        #expect(OpenAITTSModel.allCases.count == 4)
    }
}
