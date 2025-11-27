# prompt.sh

![](prompt.jpg)

A pure Bash script for executing `.prompt` template files against LLM APIs. Inspired by [runprompt](https://github.com/chr15m/runprompt) and the [dotprompt](https://github.com/google/dotprompt) format.

## Features

- Execute `.prompt` templates with YAML frontmatter
- Support for multiple LLM providers (Anthropic, OpenAI, Google AI, OpenRouter)
- Pipe stdin as input (JSON or raw text)
- Mustache-like `{{variable}}` template substitution
- Structured JSON output via tool/function calling
- Test mode with cached responses
- No Python required - pure Bash with `curl` and `jq`

## Quick Start

```bash
# Clone or download
git clone https://github.com/pforret/prompt.git
cd prompt

# Set your API key
export ANTHROPIC_API_KEY="sk-ant-..."

# Create a simple prompt
cat > hello.prompt << 'EOF'
---
model: anthropic/claude-haiku-4-20250514
---
Say hello to {{name}} in a creative way!
EOF

# Run it
echo '{"name": "World"}' | ./prompt.sh template hello.prompt
```

## Installation

### Requirements

- Bash 4.0+
- `curl` - for HTTP requests
- `jq` - for JSON parsing

### macOS

```bash
brew install jq
```

### Ubuntu/Debian

```bash
sudo apt-get install jq curl
```

### Verify Installation

```bash
./prompt.sh check
```

## Usage

```
prompt.sh [-h] [-V] [-Q] [-M <MODEL>] [-S <SAVE>] [-t <TIMEOUT>]
          [-A <ANTHROPIC_API_KEY>] [-G <GOOGLE_API_KEY>]
          [-O <OPENAI_API_KEY>] [-R <OPENROUTER_API_KEY>]
          <action> <input?>

Actions:
  template  Execute a .prompt template against an LLM
  check     Check configuration and dependencies
  env       Generate example .env file
  update    Update to latest version (if git repo)

Options:
  -M, --MODEL              LLM model as provider/model
  -A, --ANTHROPIC_API_KEY  Anthropic/Claude API key
  -G, --GOOGLE_API_KEY     Google/Gemini API key
  -O, --OPENAI_API_KEY     OpenAI/ChatGPT API key
  -R, --OPENROUTER_API_KEY OpenRouter API key
  -S, --SAVE               Save raw API response to file
  -t, --TIMEOUT            API request timeout in seconds (default: 120)
  -V, --VERBOSE            Show debug messages
  -Q, --QUIET              Suppress output
  -h, --help               Show help
```

## Providers

Models are specified as `provider/model-name`:

| Provider   | Format                                 | API Key Variable     |
|------------|----------------------------------------|----------------------|
| Anthropic  | `anthropic/claude-haiku-4-20250514`    | `ANTHROPIC_API_KEY`  |
| OpenAI     | `openai/gpt-4o`                        | `OPENAI_API_KEY`     |
| Google AI  | `googleai/gemini-1.5-pro`              | `GOOGLE_API_KEY`     |
| OpenRouter | `openrouter/anthropic/claude-sonnet-4` | `OPENROUTER_API_KEY` |
| Test Mode  | `test`                                 | (none)               |

[OpenRouter](https://openrouter.ai) provides access to models from many providers through a single API key.

## .prompt File Format

Prompt files use YAML frontmatter followed by a template body:

```yaml
---
model: anthropic/claude-haiku-4-20250514
---
Your prompt template here with {{variables}}
```

### Basic Example

```yaml
---
model: anthropic/claude-haiku-4-20250514
---
Summarize the following text in one sentence:

{{STDIN}}
```

### With Input/Output Schema

```yaml
---
model: openrouter/google/gemini-2.5-pro
input:
  schema:
    text: string
output:
  format: json
  schema:
    name?: string, the person's name
    age?: number, the person's age
    occupation?: string, the person's job
---
Extract the requested information from the given text.
If a piece of information is not present, omit that field.

Text: {{text}}
```

Fields ending with `?` are optional. Format: `field: type, description`

## Configuration

### API Keys

API keys can be provided in three ways (in order of priority):

#### 1. Command Line Option

```bash
./prompt.sh --MODEL anthropic/claude-haiku-4 \
  --ANTHROPIC_API_KEY "sk-ant-xxx" \
  template hello.prompt
```

#### 2. Environment Variable

```bash
export ANTHROPIC_API_KEY="sk-ant-xxx"
./prompt.sh --MODEL anthropic/claude-haiku-4 template hello.prompt
```

#### 3. .env File

Create a `.env` file in the script directory:

```bash
# .env
ANTHROPIC_API_KEY=sk-ant-api03-xxx
OPENROUTER_API_KEY=sk-or-v1-xxx
OPENAI_API_KEY=sk-xxx
GOOGLE_API_KEY=AIza-xxx
```

The script automatically loads these files if present:
- `.env`
- `.prompt.env`
- `prompt.env`

Generate a template .env file:

```bash
./prompt.sh env > .env
# Then edit .env and add your API keys
```

### Environment Overrides

Override any frontmatter value via `RUNPROMPT_*` environment variables:

```bash
# Override the model
RUNPROMPT_MODEL=anthropic/claude-haiku-4 ./prompt.sh template hello.prompt

# Override template variables
RUNPROMPT_name=Alice ./prompt.sh template hello.prompt
```

## Examples

### Basic Prompt with stdin

```bash
# Pipe text directly
echo "The quick brown fox jumps over the lazy dog" | \
  ./prompt.sh --MODEL anthropic/claude-haiku-4 template summarize.prompt

# Pipe file contents
cat article.txt | ./prompt.sh --MODEL anthropic/claude-haiku-4 template summarize.prompt
```

### JSON Input

When stdin is valid JSON, fields become template variables:

```bash
echo '{"name": "Alice", "topic": "quantum physics"}' | \
  ./prompt.sh --MODEL anthropic/claude-haiku-4 template explain.prompt
```

With `explain.prompt`:
```yaml
---
model: anthropic/claude-haiku-4-20250514
---
Explain {{topic}} to {{name}} in simple terms.
```

### Structured JSON Output

Extract structured data using output schemas:

```bash
echo "John is a 30 year old software engineer from Seattle" | \
  ./prompt.sh --MODEL openrouter/google/gemini-2.5-pro template extract.prompt
```

Output:
```json
{"name": "John", "age": 30, "occupation": "software engineer"}
```

### Chaining Prompts

Pipe JSON output between prompts:

```bash
echo "Marie Curie won two Nobel Prizes" | \
  ./prompt.sh --MODEL anthropic/claude-haiku-4 template extract-person.prompt | \
  ./prompt.sh --MODEL anthropic/claude-haiku-4 template write-bio.prompt
```

### Save Raw API Response

```bash
./prompt.sh --MODEL anthropic/claude-haiku-4 \
  --SAVE response.json \
  template hello.prompt
```

### Verbose Mode

Debug your prompts with verbose output:

```bash
./prompt.sh -V --MODEL anthropic/claude-haiku-4 template hello.prompt
```

### Test Mode

Use cached responses for testing without API calls:

```bash
# Create a test response file
echo '{"choices":[{"message":{"content":"Hello!"}}]}' > hello.prompt.test-response

# Run in test mode
./prompt.sh --MODEL test template hello.prompt
```

The test response file should match the provider's response format and include `_provider` field:
```json
{
  "_provider": "openai",
  "choices": [{"message": {"content": "Hello!"}}]
}
```

## Template Variables

### Special Variables

| Variable | Description |
|----------|-------------|
| `{{STDIN}}` | Raw stdin content as string |
| `{{input}}` | Alias for stdin (when not JSON) |

### From JSON Input

When stdin is valid JSON, all top-level keys become variables:

```bash
echo '{"name": "Alice", "age": 30}' | ./prompt.sh template greet.prompt
```

Available as `{{name}}` and `{{age}}` in the template.

### From Input Schema

When stdin is plain text and an input schema is defined, the text is assigned to the first schema field:

```yaml
---
model: anthropic/claude-haiku-4
input:
  schema:
    text: string
---
Summarize: {{text}}
```

## Troubleshooting

### Check Dependencies

```bash
./prompt.sh check
```

### Missing API Key

```
⛔ prompt.sh: Missing API key: ANTHROPIC_API_KEY (use --ANTHROPIC_API_KEY or set environment variable)
```

Solution: Set the API key via CLI option, environment variable, or .env file.

### Invalid Model Format

```
⛔ prompt.sh: Invalid model format. Expected provider/model, got: claude-haiku
```

Solution: Use full format `provider/model-name`, e.g., `anthropic/claude-haiku-4-20250514`

### API Errors

Enable verbose mode to see full request/response:

```bash
./prompt.sh -V --MODEL anthropic/claude-haiku-4 template hello.prompt
```

## Comparison with runprompt

This script is a pure Bash reimplementation of [chr15m/runprompt](https://github.com/chr15m/runprompt):

| Feature           | prompt.sh        | runprompt                         |
|-------------------|------------------|-----------------------------------|
| Language          | Bash             | Python                            |
| Dependencies      | curl, jq         | None (stdlib only)                |
| Providers         | 4                | 4                                 |
| Template syntax   | `{{var}}`        | `{{var}}`, `{{#each}}`, `{{#if}}` |
| Structured output | Yes              | Yes                               |
| Test mode         | Yes              | Yes                               |
| .env support      | Yes (via bashew) | No                                |

## Credits

- Based on [bashew](https://github.com/pforret/bashew) bash script template
- Inspired by [runprompt](https://github.com/chr15m/runprompt) by Chris McCormick
- Uses the [dotprompt](https://github.com/google/dotprompt) file format

## License

MIT License - See [LICENSE](LICENSE) for details.

## Author

Peter Forret - [peter@forret.com](mailto:peter@forret.com)
