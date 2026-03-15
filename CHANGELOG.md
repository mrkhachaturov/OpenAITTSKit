# Changelog

## 0.2.0

- Retry with exponential backoff (0.25s, 0.75s, 1.5s) on 429/5xx errors
- Respects `Retry-After` header from API responses
- Non-streaming `synthesize()` method for full-download use cases
- Configurable `requestTimeoutSeconds` (default 30s)
- Configurable `maxRetries` (default 3)
- `URLSession` injection (defaults to `.shared` for connection pooling)
- Buffer reuse with `removeAll(keepingCapacity: true)` for memory efficiency
- Truncated error body parsing (4KB cap)
- 31 tests across 8 suites

## 0.1.1

- Reduce stream chunk size from 8KB to 2KB to match ElevenLabsKit
- Smoother streaming playback with more frequent, smaller audio chunks

## 0.1.0

- Initial release
- Streaming TTS client for OpenAI audio/speech API
- Type-safe enums for 13 voices (`OpenAITTSVoice`), 4 models (`OpenAITTSModel`), and 6 response formats (`OpenAITTSResponseFormat`)
- Custom voice ID support (`{"id": "voice_1234"}`)
- Speed validation and normalization (0.25-4.0)
- Structured API error parsing (`OpenAITTSError`)
- Raw string parameter support for gateway config passthrough
- Custom base URL support (proxies, local servers)
- Zero external dependencies
- Swift 6.2 strict concurrency
