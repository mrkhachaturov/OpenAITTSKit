# OpenAITTSKit — OpenAI TTS on tap, SwiftPM-friendly, streaming-native.

Swift client for [OpenAI Text-to-Speech](https://platform.openai.com/docs/api-reference/audio/createSpeech) on Apple platforms (iOS/macOS).

![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2018%2B%20%7C%20macOS%2015%2B-blue)
![License](https://img.shields.io/badge/License-MIT-green)

## What's Included

- Streaming HTTP TTS client (incremental audio playback)
- Type-safe enums for voices, models, and response formats
- Speed validation and normalization (0.25–4.0)
- Structured API error parsing
- Zero external dependencies
- Strict concurrency (`Sendable`)

## Requirements

- Swift 6.2 (SwiftPM `swift-tools-version: 6.2`)
- iOS 18+
- macOS 15+

## Install (Swift Package Manager)

### Xcode

**File > Add Package Dependencies...** and enter:
```
https://github.com/mrkhachaturov/OpenAITTSKit.git
```

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/mrkhachaturov/OpenAITTSKit.git", from: "0.1.0"),
]
```

## Quick Start

```swift
import OpenAITTSKit

let client = OpenAITTSClient(apiKey: "<api-key>")

// Type-safe API
let stream = client.streamSynthesize(
    model: .gpt4oMiniTTS,
    voice: .ash,
    text: "Hello, world!",
    instructions: "Speak in a calm, warm tone"
)

for try await chunk in stream {
    audioPlayer.enqueue(chunk) // feed to your audio player
}
```

## Streaming

The client returns an `AsyncThrowingStream<Data, Error>` of audio chunks (~8KB each). Audio starts playing as soon as the first chunk arrives — no need to wait for the full response.

```swift
let stream = client.streamSynthesize(
    model: .gpt4oMiniTTS,
    voice: .nova,
    text: longText,
    speed: 1.2,
    responseFormat: .mp3
)

for try await chunk in stream {
    // Each chunk is up to 8KB of audio data.
    // Feed to StreamingAudioPlayer, AVAudioEngine, or any player.
}
```

## Request Object

For full control, construct an `OpenAITTSRequest` directly:

```swift
let request = OpenAITTSRequest(
    model: .gpt4oMiniTTS,
    input: "Hello",
    voice: .ash,
    responseFormat: .opus,
    speed: 1.5,
    instructions: "Whisper softly"
)
let stream = client.streamSynthesize(request)
```

### Raw String Parameters

For dynamic config (e.g. gateway passthrough), use raw strings:

```swift
let request = OpenAITTSRequest(
    modelId: "gpt-4o-mini-tts",
    input: "Hello",
    voiceId: "ash",
    responseFormat: "mp3"
)
```

## Custom Base URL

Point to a proxy, local server, or OpenAI-compatible endpoint:

```swift
let client = OpenAITTSClient(
    apiKey: "<key>",
    baseUrl: "https://my-proxy.example.com/v1"
)
```

## Voices

All OpenAI TTS voices are available as type-safe enum values:

| Voice | Description |
|-------|-------------|
| `.alloy` | Neutral, balanced |
| `.ash` | Warm, conversational |
| `.ballad` | Expressive, melodic |
| `.cedar` | Friendly, natural |
| `.coral` | Clear, engaging |
| `.echo` | Smooth, resonant |
| `.fable` | Storytelling, animated |
| `.marin` | Poised, articulate |
| `.nova` | Friendly, upbeat |
| `.onyx` | Deep, authoritative |
| `.sage` | Calm, wise |
| `.shimmer` | Bright, optimistic |
| `.verse` | Versatile, dynamic |

Preview voices at [openai.fm](https://openai.fm).

### Custom Voice IDs

You can also use custom voices by providing a voice ID:

```swift
let request = OpenAITTSRequest(
    input: "Hello",
    customVoiceId: "voice_1234"
)
```

This encodes as `{"voice": {"id": "voice_1234"}}` per the API spec.

## Models

| Model | Quality | Latency | Instructions |
|-------|---------|---------|-------------|
| `.tts1` | Standard | Low | No |
| `.tts1HD` | High | Higher | No |
| `.gpt4oMiniTTS` | High | Low | Yes |

The `instructions` parameter only works with `gpt-4o-mini-tts`.

## Response Formats

| Format | Use Case |
|--------|----------|
| `.mp3` | Default, widely compatible |
| `.opus` | Low latency streaming |
| `.aac` | Apple ecosystem |
| `.flac` | Lossless |
| `.wav` | Uncompressed |
| `.pcm` | Raw audio (24kHz 16-bit mono) |

## Error Handling

API errors are parsed into structured `OpenAITTSError` with status code, message, type, and code:

```swift
do {
    for try await chunk in stream { ... }
} catch let error as OpenAITTSError {
    print("Status: \(error.statusCode)")  // e.g. 401
    print("Message: \(error.message)")     // e.g. "Invalid API key"
    print("Code: \(error.code ?? "?")")    // e.g. "invalid_api_key"
} catch {
    print("Other error: \(error)")
}
```

## Speed

Speed is automatically clamped to the valid range (0.25–4.0):

```swift
// These are equivalent:
OpenAITTSRequest.normalizeSpeed(0.1)   // → 0.25 (clamped)
OpenAITTSRequest.normalizeSpeed(1.5)   // → 1.5 (unchanged)
OpenAITTSRequest.normalizeSpeed(10.0)  // → 4.0 (clamped)
```

## Dev

```bash
swift test            # Run all tests
swift build           # Build the package
```

## License

MIT
