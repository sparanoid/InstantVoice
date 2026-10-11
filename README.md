<div align="center">
  <img src=".github/assets/app-icon.png" width="180" height="180" alt="InstantVoice app icon" />
  <h1>InstantVoice</h1>
  <p>Voice to text for macOS, almost instantly</p>

  [![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](LICENSE)
  ![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-brightgreen)
</div>

InstantVoice is a native macOS app that transcribes your speech and pastes the text wherever you're typing.

## Relationship to VoiceInk

InstantVoice is a modified version of [VoiceInk](https://github.com/Beingpax/VoiceInk) by Prakash Joshi Pax, forked from VoiceInk 2.21 in October 2026. Its development decisions have since moved far from upstream, so it's been detached from the upstream fork and is now developed as an independent project. The Git history records every change made since the fork.

The biggest differences from VoiceInk:

- A native macOS 26 interface with Liquid Glass and System Settings–style navigation
- No license, trial, or paywall
- Cloud model lists that come live from each provider's API, chosen per mode
- No Cerebras, Mistral, Speechmatics, or AssemblyAI support

## Features

- **Local or cloud transcription**: run Whisper, Parakeet, SenseVoice, Apple Speech, and other models on your Mac, or use a cloud provider such as Soniox, Deepgram, ElevenLabs, Gemini, or Groq, with real-time streaming where the provider supports it.
- **Modes**: each mode has its own model, language, and AI settings, and can switch on automatically for specific apps or websites.
- **AI enhancement**: clean up or rewrite transcripts with OpenAI, Anthropic, Gemini, Groq, OpenRouter, or a custom endpoint, or locally with Ollama or the on-device InstantVoice Refine model. Screen, clipboard, and selected text can be added as context.
- **Assistant**: ask a question by voice and get an AI answer, with follow-ups.
- **Dictionary**: custom vocabulary and word replacements.
- **Shortcuts**: keyboard or mouse shortcuts, including push-to-talk.
- **History**: search, replay, and retranscribe past recordings, or transcribe audio files.

## Building

InstantVoice requires macOS 26 or later. Build it with Xcode 26 or later:

```bash
git clone https://github.com/sparanoid/InstantVoice.git
cd InstantVoice
make local
```

`make local` puts `InstantVoice.app` in `~/Downloads`. See [BUILDING.md](BUILDING.md) for signing options, Xcode builds, and other commands.

## Contributing

InstantVoice doesn't accept pull requests. You're welcome to fork and modify it under the GPL.

## License

InstantVoice is licensed under the [GNU General Public License v3.0](LICENSE), the same license as VoiceInk.

## Acknowledgments

- [VoiceInk](https://github.com/Beingpax/VoiceInk) by Prakash Joshi Pax, the project InstantVoice started from, and its [LLMkit](https://github.com/Beingpax/LLMkit) provider library, vendored in `Packages/LLMkit`
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for Whisper models
- [FluidAudio](https://github.com/FluidInference/FluidAudio) for Parakeet models
- [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp), through [TranscribeCpp for Swift](https://github.com/Beingpax/Transcribe-cpp-swift), for local GGUF models
- [SenseVoice Small](https://huggingface.co/FunAudioLLM/SenseVoiceSmall) by FunAudioLLM / Alibaba, available under the [FunASR Model Open Source License Agreement](https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE)
- [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm) and [swift-transformers](https://github.com/huggingface/swift-transformers) for the on-device InstantVoice Refine model
- [Sparkle](https://github.com/sparkle-project/Sparkle), [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui), [MediaRemoteAdapter](https://github.com/ejbills/mediaremote-adapter), [SelectedTextKit](https://github.com/tisfeng/SelectedTextKit), [Zip](https://github.com/marmelroy/Zip), and [Swift Atomics](https://github.com/apple/swift-atomics)
