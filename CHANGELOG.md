# Changelog

## 0.1.0

- Initial release
- Streaming TTS client for OpenAI audio/speech API
- Type-safe enums for voices (`OpenAITTSVoice`), models (`OpenAITTSModel`), and response formats (`OpenAITTSResponseFormat`)
- Speed validation and normalization (0.25–4.0)
- Structured API error parsing (`OpenAITTSError`)
- Raw string parameter support for gateway config passthrough
- Custom base URL support (proxies, local servers)
- Zero external dependencies
- Swift 6.2 strict concurrency
