# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **bashew-based** Bash script that executes `.prompt` template files against LLM APIs (Anthropic, OpenAI, Google AI, OpenRouter). It's a pure Bash reimplementation of the Python `runprompt` tool.

## Commands

```bash
# Check syntax
bash -n prompt.sh

# Run shellcheck
shellcheck prompt.sh

# Test with test mode (uses .test-response files, no API calls)
echo "Hello" | ./prompt.sh --MODEL test template runprompt/tests/stdin-test.prompt

# Test with real API
echo '{"name":"World"}' | ./prompt.sh --MODEL anthropic/claude-haiku-4-20250514 template hello.prompt

# Check dependencies and config
./prompt.sh check

# Show help
./prompt.sh -h

# Verbose/debug mode
./prompt.sh -V --MODEL test template test.prompt
```

## Architecture

### Bashew Framework

This script is built on [pforret/bashew](https://github.com/pforret/bashew). Key conventions:

- **`Option:config()`** - Define CLI flags, options, and parameters
- **`Script:main()`** - Main entry point with action dispatch
- **`do_<action>()`** - Handler functions for each action
- **`IO:*` functions** - Output helpers (`IO:print`, `IO:debug`, `IO:die`, `IO:log`)
- **`Os:require`** - Declare required binaries
- Auto-loads `.env`, `.prompt.env`, `prompt.env` files

### Code Organization (prompt.sh)

| Section           | Lines   | Purpose                                                |
|-------------------|---------|--------------------------------------------------------|
| `Option:config()` | 17-58   | CLI option definitions                                 |
| `Script:main()`   | 64-109  | Action dispatch (`template`, `check`, `env`, `update`) |
| `Provider:*`      | 125-305 | API provider config, requests, response extraction     |
| `Prompt:*`        | 311-450 | File parsing, YAML parsing, template rendering         |
| `Prompt:build_*`  | 459-600 | Tool/schema building for structured output             |
| `do_template()`   | 620-665 | Main template execution logic                          |

### Key Global Variables

```bash
declare -gA YAML_DATA=()      # Parsed YAML frontmatter
declare -gA TEMPLATE_VARS=()  # Variables for template substitution
PROMPT_TEMPLATE=""            # Template body after frontmatter
STDIN_RAW=""                  # Raw stdin content
PROVIDER=""                   # Current provider (anthropic, openai, etc.)
MODEL_NAME=""                 # Model name after provider prefix
```

### .prompt File Format

```yaml
---
model: provider/model-name
input:
  schema:
    fieldname: type
output:
  format: json
  schema:
    fieldname?: type, description
---
Template with {{variable}} placeholders
```

## Providers

- **anthropic** - Uses `x-api-key` header, different response format
- **openai/googleai/openrouter** - OpenAI-compatible format with `Authorization: Bearer` header
- **test** - Loads `<prompt>.test-response` JSON files for testing without API calls

## Testing

Test files are in `runprompt/tests/`:

```bash
# Run all test cases
echo "Test" | ./prompt.sh --MODEL test template runprompt/tests/stdin-test.prompt
echo "John is 30" | ./prompt.sh --MODEL test template runprompt/tests/job.prompt
./prompt.sh --MODEL test template runprompt/tests/self.prompt
```

Test mode requires a `.test-response` file alongside the `.prompt` file containing the expected API response JSON with `_provider` field.
