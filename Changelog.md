# Changelog

All notable changes to speak will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- Hardware detection via /proc/meminfo (RAM, CPU cores, AVX2)
- Disk-based KV cache (ds4-style) with SHA1 token keys
- Persistent user memory across sessions via user.md
- Agent loop for multi-step tool calls (up to 10 iterations)
- Tool system with read_file, search_web, remember, finish
- Web search via DuckDuckGo (30s timeout, 10 results max)
- Model registry with 13+ pre-configured models
- Interactive model selection on first run
- Auto-setup mode for headless installation
- Resumable model downloads with progress bar
- Multi-threaded downloads via aria2c (falls back to HTTP)
- Streaming chat interface with Readline support
- System prompt customization via embedded system_prompt.txt
- Hardware-aware config.json with detected and active sections
- Memory mapping (mmap) for low-RAM systems (<8GB)
- LRU cache cleanup (max 50 cache files)
- JSON serialization for all config structures
- Crystal spec tests for core functionality
- GitHub Actions CI workflow

### Changed
- N/A (initial development)

### Fixed
- N/A (initial development)

### Removed
- N/A (initial development)

### Security
- Path traversal protection in read_file tool
- File size limit (13MB) for read operations
- Working directory restriction for file access

## [0.12.0-beta] - 2026-05-27

### Added
- First public beta release
- Nanbeige 4.1 3B model support (Q2_K, Q4_K_M, Q6_K)
- Basic chat functionality
- Command history with Readline
- Save and load conversation history
- Memory commands (memory, clearmemory)
- Clear screen command
- Help text in interface

### Known Issues
- macOS support is experimental
- Windows not yet supported
- Web search may be slow on first query
- Large files (>13MB) cannot be read
- Model download requires stable internet connection

### Notes
This is a beta release. Expect bugs and breaking changes.
Please report issues on GitHub.
