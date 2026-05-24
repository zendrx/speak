
# Contributing to speak

Thank you for considering contributing to `speak`. This document outlines the guidelines for contributing to the project.

## Code of Conduct

By participating in this project, you agree to maintain a respectful and constructive environment. Be kind, be professional, and focus on the code.

## How Can I Contribute?

### Reporting Bugs

Before reporting a bug, please check the existing issues to avoid duplicates.

When reporting a bug, include:

- Your operating system and version
- Crystal version (`crystal --version`)
- The exact command you ran
- The full error message (if any)
- Steps to reproduce the issue

### Suggesting Features

Feature suggestions are welcome. Please provide:

- A clear description of the feature
- Why it would be useful for `speak` users
- Any implementation ideas you may have

### Improving Documentation

Documentation improvements are always appreciated. This includes:

- Fixing typos or unclear sections in README.md
- Adding examples or clarifying existing ones
- Translating documentation (if applicable)

### Writing Code

Pull requests for bug fixes, performance improvements, and new features are encouraged.

## Development Setup

### Prerequisites

- Crystal 1.12 or later
- Git
- `libllama.so` (llama.cpp shared library)
- `aria2c` (optional, for faster downloads)

### First Time Setup

```bash
git clone https://github.com/zendrx/speak.git
cd speak
mkdir -p lib
git clone https://github.com/kojix2/llama.cr.git lib/llama.cr
cd lib/llama.cr
git checkout $(cat ../../shard.yml | grep version | head -1 | cut -d: -f2 | tr -d ' "')
cd ../..
shards install
crystal build src/speak.cr --release -o speak_app
```

See development.md for detailed setup instructions.

Pull Request Guidelines

Before Submitting

1. Test your changes – Run ./speak_app and verify that existing features still work.
2. Keep changes focused – One feature or bug fix per pull request.
3. Update documentation – If you change user-facing behavior, update README.md.
4. Follow the code style – 2 spaces indentation, no trailing whitespace.

Commit Messages

Use clear, descriptive commit messages:

```
Add: description of new feature
Fix: description of bug fixed
Docs: description of documentation change
Refactor: description of refactoring
```

Pull Request Description

Include:

- What the change does
- Why the change is needed
- Any potential side effects or breaking changes
- How to test the change

Code Style Guidelines

Crystal Specific

- Use 2 spaces for indentation (no tabs)
- Use snake_case for methods and variables
- Use CamelCase for classes and modules
- Use UPPER_SNAKE_CASE for constants
- Use ? suffix for predicate methods (returning Bool)
- Use ! suffix for methods that raise exceptions

Example

```crystal
module Speak
  class Example
    CONSTANT_VALUE = 42

    property name : String

    def initialize(@name : String)
    end

    def valid? : Bool
      !name.empty?
    end

    def process!
      raise "Name is empty" unless valid?
      puts "Processing #{name}"
    end
  end
end
```

Comments

- Use # for single-line comments
-  Use # :ditto: for repeating previous comment (when applicable)
- Document public methods with a brief description

```crystal
# Loads configuration from the JSON file.
# Returns a Config instance on success.
def self.load_config(path : String) : Config
  # implementation
end
```

Testing

Run the existing test suite:

```bash
crystal spec
```

When adding new features, add corresponding tests in the spec/ directory.

Test Structure

```
spec/
├── spec_helper.cr
├── system_spec.cr
├── config_spec.cr
└── ...
```


When adding a new feature, update the relevant documentation files.

Issue Triage

You can help by:

- Reproducing issues and adding details
- Suggesting possible fixes
- Testing pull requests

Recognition

Contributors will be acknowledged in the README.md and in release notes.

Questions?

Open an issue on GitHub with your question, and someone will respond as soon as possible.

License

By contributing to speak, you agree that your contributions will be licensed under the MIT License.

```
```
