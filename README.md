
<div align="center">

# speak

**A local AI assistant that runs on your computer. No cloud. No subscription. Your data stays with you.**

![speak logo](https://raw.githubusercontent.com/zendrx/speak/master/speak.JPG)

[![Crystal](https://img.shields.io/badge/Crystal-1.12-000000?logo=crystal)](https://crystal-lang.org/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/zendrx/speak/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/zendrx/speak/actions/workflows/ci.yml)
[![Lines of Code](https://img.shields.io/badge/Lines%20of%20Code-1,133-blue?style=flat-square&logo=crystal)](https://github.com/zendrx/speak)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)
[![Made with Crystal](https://img.shields.io/badge/Made%20with-Crystal-000000)](https://crystal-lang.org/)

</div>

---

## Table of Contents

- [What is speak?](#what-is-speak)
- [Features](#features)
- [Quick Start](#quick-start)
- [Requirements](#requirements)
- [Usage](#usage)
- [Configuration](#configuration)
- [Architecture](#architecture)
- [How speak saves RAM](#how-speak-saves-ram)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## What is speak?

speak is a local AI assistant that runs entirely on your machine. It is designed for normal computers (4-6GB RAM), not expensive servers. No internet connection needed. No monthly fee. Your conversations never leave your computer.

> speak is inspired by [antirez's ds4](https://github.com/antirez/ds4) but built for everyday laptops, not high-end Macs.

It remembers who you are across sessions. It can read your files. It can search the web. And it does all of this using less than 2GB of RAM.

---

## Features

| Feature | What it means for you | Status |
|:--------|:----------------------|:------:|
| 100% Local | Runs on your laptop. No data sent to anyone. | Yes |
| Persistent Memory | Tell speak something once. It remembers forever. | Yes |
| File Reading | "Read my config.json" - speak shows you the content. | Yes |
| Web Search | "Search for latest news" - speak finds current information. | Yes |
| Low RAM Usage | Uses disk caching. Long conversations don't fill your memory. | Yes |
| Hardware Detection | Auto-configures itself for your computer. | Yes |
| Offline First | Works without internet. Web search is optional. | Yes |
| Streaming Output | Tokens appear as they are generated. | Yes |
| Agent Loop | Multi-step tool use (search, read, then answer). | Yes |
| Disk KV Cache | Conversation state saved to SSD, not RAM. | Yes |
| Resumable Downloads | Interrupted model downloads continue where they stopped. | Yes |

---

## Quick Start

### One-liner

```bash
git clone https://github.com/zendrx/speak.git && cd speak && shards install && crystal build src/speak.cr --release -o speak && ./speak
```

Step by step

```bash
# Clone the repository
git clone https://github.com/zendrx/speak.git
cd speak

# Install dependencies
shards install

# Build the binary
crystal build src/speak.cr --release -o speak

# Run speak
./speak
```

On first run, speak will:

1. Detect your RAM and CPU
2. Create a config file for your hardware
3. Download the AI model (2.5GB)
4. Start the chat

---

## Requirements

| Component | Minimum | Recommended | 
| ---- | ---- | ---- |
| RAM |  4 GB | 8 GB | 
| Storage | 3 GB free | 10 GB free | 
| OS  | Linux | Ubuntu 22.04+ | 
| CPU | Any 64-bit | AVX2 support | 

macOS works but is experimental. Windows support coming soon.

---

## Usage

Chat Commands

Inside the chat, type these commands:

| Command | Action | 
| ---- | ---- |
| exit or quit |  Save and quit |
| clear | Clear the screen | 
| history | Show conversation history | 
| save | Save conversation manually | 
| memory | Show what speak remembers about you | 
| clearmemory | Clear all memories | 
| reset | Reset working memory | 

Example conversation

```
$ ./speak

======================================================================
                         speak - Local AI Assistant
======================================================================

> Hello, who are you?

speak: I am speak, a local AI assistant running on your computer.
       I can read files, search the web, and remember things about you.

> My name is Sarah and I love Python

speak: I've remembered that your name is Sarah and you love Python.

> Read my config.json

speak: {
  "detected": {
    "total_ram_mb": 8192,
    "available_ram_mb": 6200
  },
  "active": {
    "context_size": 2048,
    "model_quant": "Q4_K_M"
  }
}

> Search for Python 3.13 features

speak: Search results for: Python 3.13 features

1. Python 3.13 Release Notes
   URL: https://docs.python.org/3.13/whatsnew/3.13.html
   Improved error messages, incremental garbage collection...

> What do you know about me?

speak: Your name is Sarah and you love Python.

> exit

Goodbye.
```

---

## Configuration

All settings are stored in ./speak/config.json. You can edit this file to customize speak.

Configuration Structure

```json
{
  "detected": {
    "total_ram_mb": 8192,
    "available_ram_mb": 6200,
    "os_reserved_ram_mb": 512
  },
  "active": {
    "cpu_cores": 4,
    "has_avx2": true,
    "free_disk_space_mb": 51200,
    "context_size": 2048,
    "kv_cache_type": "standard",
    "model_quant": "Q4_K_M",
    "model_file": "nanbeige-3b-q4_k_m.gguf",
    "temperature": 0.7,
    "max_tokens": 512,
    "use_mmap": true
  },
  "user_overrides": {
    "os_reserved_ram_mb": null,
    "context_size": null,
    "kv_cache_type": null,
    "model_quant": null,
    "temperature": null,
    "max_tokens": null,
    "use_mmap": null
  }
}
```

## Common Settings

| Setting | What it does |  Default |
---- | ---- | ---- |
|context_size | How many tokens the AI remembers|  2048|
|temperature | Creativity (0.0 = strict, 1.5 = creative) | 0.7|
|max_tokens | Maximum response length | 512|
|model_quant | Quality vs speed (Q2_K, Q4_K_M, Q6_K) | Q4_K_M|

Make AI more creative

Edit ./speak/config.json:

```json
"user_overrides": {
  "temperature": 1.2
}
```

Reduce RAM usage

```json
"user_overrides": {
  "context_size": 1024,
  "model_quant": "Q2_K"
}
```

Custom System Prompt

Edit src/speak/system_prompt.txt and recompile. The prompt is embedded at build time.

---

## Architecture

System Flow

```
User Input
    |
    v
[Launch] ---> [Agent Loop] ---> [Tool Calls]
    |              |                  |
    v              v                  v
[Config]      [Memory]           [Tool Executor]
    |              |                  |
    v              v                  v
[Model] <---- [Disk Cache] <---- [Web Search]
    |
    v
Response
```

## File Structure

```
speak/
+-- src/
    +-- speak.cr              Entry point
    +-- speak/
        +-- system.cr         Hardware detection
        +-- config.cr         JSON configuration
        +-- install.cr        Model downloader
        +-- disk.cr           Disk-backed KV cache
        +-- tool.cr           Tool system
        +-- memory.cr         Agent memory
        +-- launch.cr         Chat interface
        +-- system_prompt.txt Embedded prompt
+-- lib/                      Shards
+-- shard.yml
+-- README.md
```

RAM Tiers

| Available RAM |  Model Quant|  Context Size|  mmap | 
| ---- | ---- | ----| ---- |
| 3 GB | Q2_K | 512 | Enabled
|  3-6 GB | Q4_K_M | 1024 |  Enabled
| 6-12 GB | Q4_K_M | 2048 |  Enabled
|  12 GB | Q6_K | 4096 |  Disabled

---

## How speak saves RAM

speak uses two techniques to keep memory low:

1. Memory Mapping (mmap)

The model stays on disk. Only the parts needed are loaded into RAM. This reduces RAM usage from 2.5GB to under 500MB for the model.

2. Disk KV Cache

Conversation memory (KV cache) is saved to SSD, not RAM. Each turn extends the cache on disk, not in memory.

```
Without Disk Cache:  RAM usage grows with conversation length (2GB -> 8GB crash)
With Disk Cache:     RAM usage stays flat (2GB for 10 turns or 10,000 turns)
```

---

## Troubleshooting

Unable to create dir ./speak

Your binary is named speak and conflicts with the data directory. Rename the binary:

```bash
mv speak speak_app
./speak_app
```

401 Unauthorized during download

The model repository requires authentication. Run:

```bash
./hfd.sh Edge-Quant/Nanbeige4.1-3B-Q4_K_M-GGUF --include *.gguf --local-dir ./speak/models
```

Then run ./speak again.

Model loads slowly on HDD

Use the smaller Q2_K model. Edit config.json:

```json
"user_overrides": {
  "model_quant": "Q2_K"
}
```

Then delete the old model file in ./speak/models/ and restart speak.

Readline not working

Install the system library:

```bash
# Ubuntu/Debian
sudo apt install libreadline-dev

# macOS
brew install readline
```

Undefined method 'tokenize'

Ensure you are using the correct API: @vocab.tokenize not context.tokenize.

---

## Contributing

Contributions are welcome. Please see CONTRIBUTING.md for guidelines.

```bash
git clone https://github.com/zendrx/speak.git
cd speak
# Make your changes
crystal build src/speak.cr --release -o speak_app
./speak_app
```

---

## License

MIT License. See LICENSE file for details.

---

## Credits

| Project | Role | 
| ---- | ---- | 
|  **Crystal | Language** | 
| **llama.cpp | Inference engine** | 
| **llama.cr | Crystal bindings** | 
| **Nanbeige | Model** | 
| **ds4 | Disk cache inspiration** | 

---

<div align="center">speak - Your local AI assistant

Built with Crystal

</div>
