
# Security Policy

## Supported Versions

Only the latest stable version of speak receives security updates.

| Version | Supported |
|---------|-----------|
| latest | ✅ |
| < latest | ❌ |

## Reporting a Vulnerability

If you discover a security vulnerability in speak, please report it privately.

**Do NOT report security issues through public GitHub issues.**

### How to Report

1. Email the maintainer directly at [ynwghosted@icloud.com]
2. Include detailed steps to reproduce the issue
3. Include your system information (OS, Crystal version)
4. Allow up to 48 hours for initial response

### What to Expect

- You will receive acknowledgment of your report within 48 hours
- The maintainer will investigate and confirm the vulnerability
- A fix will be developed and tested
- A security advisory will be published after the fix is released

## Security Measures in speak

### File System Protection

- Path traversal attacks are blocked (files with `..` are rejected)
- File reading is restricted to the current working directory
- Maximum file size is limited to 13MB
- Directory reading is not allowed

### Memory Safety

- speak is written in Crystal, a memory-safe language
- No unsafe pointers or manual memory management
- Bounds checking is performed on all array accesses

### Network Security

- Web search uses DuckDuckGo (no API key required)
- No telemetry or data collection
- All network requests are HTTPS only
- Model downloads verify file size integrity

### Input Validation

- All user input is sanitized before processing
- Tool call arguments are validated before execution
- JSON parsing includes error handling

## Known Limitations

| Area | Limitation | Mitigation |
|------|------------|------------|
| Model files | Downloaded from Hugging Face over HTTPS | Verify file size checksum |
| Web search | DuckDuckGo HTML scraping | No API key, only used when user requests |
| Dependencies | llama.cpp is C++ code | Upstream library, security updates tracked |

## Responsible Disclosure

We follow responsible disclosure practices:

1. Vulnerability is reported privately
2. Maintainer confirms and fixes the issue
3. Fix is tested and released
4. Security advisory is published
5. Public announcement after fix is available

## Cryptographic Measures

speak does not implement any cryptographic functions directly. It relies on Crystal's standard library for SHA1 hashing (used for KV cache keys). The SHA1 algorithm is used only for cache key generation, not for security-critical purposes.

## Third-Party Dependencies

| Dependency | Purpose | Security Notes |
|------------|---------|----------------|
| llama.cr | Crystal bindings to llama.cpp | Upstream library, monitor for updates |
| llama.cpp | Inference engine | C++ library, monitor for CVEs |
| readline | Command line input | Standard system library |

## Reporting Format

When reporting a vulnerability, please include:

```yaml
# Example report format
version: "0.12.0-beta"
os: "Ubuntu 24.04"
crystal: "1.12.0"

description: |
  Detailed description of the issue

steps_to_reproduce: |
  1. Run ./speak
  2. Type specific command
  3. Observe unexpected behavior

impact: |
  What an attacker could potentially do

proposed_fix: |
  Optional: suggested solution
```

Security Contact

- Email: [ynwghosted@icloud.com]
- GitHub: @zendrx
- Response time: 24-48 hours

Acknowledgments

We thank the following people for reporting security issues:

· List will be updated with contributors who report vulnerabilities


