#!/usr/bin/env bash
### ==============================================================================
### SO HOW DO YOU PROCEED WITH YOUR SCRIPT?
### 1. define the flags/options/parameters and defaults you need in Option:config()
### 2. implement the different actions in Script:main() directly or with helper functions do_action1
### 3. implement helper functions you defined in previous step
### ==============================================================================

### Created by Peter Forret ( pforret ) on 2025-11-27
### Based on https://github.com/pforret/bashew 1.22.0
script_version="0.0.1" # if there is a VERSION.md in this script's folder, that will have priority over this version number
readonly script_author="peter@forret.com"
readonly script_created="2025-11-27"
readonly run_as_root=-1 # run_as_root: 0 = don't check anything / 1 = script MUST run as root / -1 = script MAY NOT run as root
readonly script_description="Execute .prompt templates in bash pipelines."

function Option:config() {
  ### Change the next lines to reflect which flags/options/parameters you need
  ### flag:   switch a flag 'on' / no value specified
  ###     flag|<short>|<long>|<description>
  ###     e.g. "-v" or "--VERBOSE" for VERBOSE output / default is always 'off'
  ###     will be available as $<long> in the script e.g. $VERBOSE
  ### option: set an option / 1 value specified
  ###     option|<short>|<long>|<description>|<default>
  ###     e.g. "-e <extension>" or "--extension <extension>" for a file extension
  ###     will be available a $<long> in the script e.g. $extension
  ### list: add an list/array item / 1 value specified
  ###     list|<short>|<long>|<description>| (default is ignored)
  ###     e.g. "-u <user1> -u <user2>" or "--user <user1> --user <user2>"
  ###     will be available a $<long> array in the script e.g. ${user[@]}
  ### param:  comes after the options
  ###     param|<type>|<long>|<description>
  ###     <type> = 1 for single parameters - e.g. param|1|output expects 1 parameter <output>
  ###     <type> = ? for optional parameters - e.g. param|1|output expects 1 parameter <output>
  ###     <type> = n for list parameter    - e.g. param|n|inputs expects <input1> <input2> ... <input99>
  ###     will be available as $<long> in the script after option/param parsing
  ### choice:  is like a param, but when there are limited options
  ###     choice|<type>|<long>|<description>|choice1,choice2,...
  ###     <type> = 1 for single parameters - e.g. param|1|output expects 1 parameter <output>
  grep <<<"
#commented lines will be filtered
flag|h|help|show usage
flag|Q|QUIET|no output
flag|V|VERBOSE|also show debug messages
flag|f|FORCE|do not ask for confirmation (always yes)
option|L|LOG_DIR|folder for log files |$HOME/log/$script_prefix
option|T|TMP_DIR|folder for temp files|/tmp/$script_prefix
option|M|MODEL|LLM model as provider/model|
option|A|ANTHROPIC_API_KEY|Anthropic/Claude API key|
option|G|GOOGLE_API_KEY|Google/Gemini API key|
option|O|OPENAI_API_KEY|OpenAI/ChatGPT API key|
option|R|OPENROUTER_API_KEY|OpenRouter API key|
option|S|SAVE|save raw API response to file|
option|t|TIMEOUT|API request timeout in seconds|120
choice|1|action|action to perform|template,check,env,update
param|?|input|input .prompt file
" -v -e '^#' -e '^\s*$'
}

#####################################################################
## Put your Script:main script here
#####################################################################

function Script:main() {
  IO:log "[$script_basename] $script_version started"

  Os:require "awk"

  case "${action,,}" in
  template)
    #TIP: use «$script_prefix template» to execute a .prompt template against an LLM
    #TIP:> echo '{"name":"World"}' | $script_prefix --MODEL anthropic/claude-haiku-4-20250514 template hello.prompt
    #TIP:> cat article.txt | $script_prefix --MODEL openrouter/google/gemini-2.5-flash template summarize.prompt
    #TIP: API keys can be provided via CLI, environment variables, or .env file
    #TIP:> $script_prefix --MODEL anthropic/claude-haiku-4 --ANTHROPIC_API_KEY sk-ant-xxx template hello.prompt
    #TIP: Create a .env file in the script folder with your API keys:
    #TIP:> echo 'ANTHROPIC_API_KEY=sk-ant-xxx' >> .env
    #TIP:> echo 'OPENROUTER_API_KEY=sk-or-xxx' >> .env
    #TIP:> echo 'OPENAI_API_KEY=sk-xxx' >> .env
    #TIP:> echo 'GOOGLE_API_KEY=xxx' >> .env
    Os:require "curl"
    Os:require "jq"
    do_template
    ;;

  check | env)
    ## leave this default action, it will make it easier to test your script
    #TIP: use «$script_prefix check» to check if this script is ready to execute and what values the options/flags are
    #TIP:> $script_prefix check
    #TIP: use «$script_prefix env» to generate an example .env file
    #TIP:> $script_prefix env > .env
    Script:check
    ;;

  update)
    ## leave this default action, it will make it easier to test your script
    #TIP: use «$script_prefix update» to update to the latest version
    #TIP:> $script_prefix update
    Script:git_pull
    ;;

  *)
    IO:die "action [$action] not recognized"
    ;;
  esac
  IO:log "[$script_basename] ended after $SECONDS secs"
  #TIP: >>> bash script created with «pforret/bashew»
  #TIP: >>> for bash development, also check out «pforret/setver» and «pforret/progressbar»
}

#####################################################################
## Put your helper scripts here
#####################################################################

# Global variables for prompt parsing
declare -gA YAML_DATA=()
declare -gA TEMPLATE_VARS=()
PROMPT_TEMPLATE=""
STDIN_RAW=""

#####################################################################
## Provider Configuration
#####################################################################

function Provider:get_config() {
  local provider="$1"
  case "$provider" in
    openrouter)
      PROVIDER_URL="https://openrouter.ai/api/v1/chat/completions"
      PROVIDER_ENV="OPENROUTER_API_KEY"
      ;;
    googleai)
      PROVIDER_URL="https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
      PROVIDER_ENV="GOOGLE_API_KEY"
      ;;
    anthropic)
      PROVIDER_URL="https://api.anthropic.com/v1/messages"
      PROVIDER_ENV="ANTHROPIC_API_KEY"
      ;;
    openai)
      PROVIDER_URL="https://api.openai.com/v1/chat/completions"
      PROVIDER_ENV="OPENAI_API_KEY"
      ;;
    test)
      PROVIDER_URL=""
      PROVIDER_ENV=""
      ;;
    *)
      IO:die "Unknown provider: $provider"
      ;;
  esac
}

function Provider:parse_model() {
  local model_str="$1"
  if [[ "$model_str" == "test" ]]; then
    PROVIDER="test"
    MODEL_NAME=""
    return 0
  fi
  if [[ "$model_str" == *"/"* ]]; then
    PROVIDER="${model_str%%/*}"
    MODEL_NAME="${model_str#*/}"
  else
    IO:die "Invalid model format. Expected provider/model, got: $model_str"
  fi
}

function Provider:make_request() {
  local provider="$1"
  local model="$2"
  local prompt="$3"
  local output_schema="${4:-}"

  Provider:get_config "$provider"

  # Get API key from CLI option first, then environment variable
  local api_key=""
  case "$provider" in
    anthropic)  api_key="${ANTHROPIC_API_KEY:-${!PROVIDER_ENV:-}}" ;;
    googleai)   api_key="${GOOGLE_API_KEY:-${!PROVIDER_ENV:-}}" ;;
    openai)     api_key="${OPENAI_API_KEY:-${!PROVIDER_ENV:-}}" ;;
    openrouter) api_key="${OPENROUTER_API_KEY:-${!PROVIDER_ENV:-}}" ;;
    *)          api_key="${!PROVIDER_ENV:-}" ;;
  esac
  [[ -z "$api_key" ]] && IO:die "Missing API key: $PROVIDER_ENV (use --${PROVIDER_ENV} or set environment variable)"

  local json_prompt
  json_prompt=$(printf '%s' "$prompt" | jq -Rs .)

  local request_body
  local response

  if [[ "$provider" == "anthropic" ]]; then
    # Anthropic uses different API format
    if [[ -n "$output_schema" ]]; then
      local tool_def
      tool_def=$(Prompt:build_tool "$output_schema")
      request_body=$(jq -n \
        --arg model "$model" \
        --argjson prompt "$json_prompt" \
        --argjson tool "$tool_def" \
        '{
          model: $model,
          max_tokens: 4096,
          messages: [{role: "user", content: $prompt}],
          tools: [$tool],
          tool_choice: {type: "tool", name: "extract"}
        }')
    else
      request_body=$(jq -n \
        --arg model "$model" \
        --argjson prompt "$json_prompt" \
        '{
          model: $model,
          max_tokens: 4096,
          messages: [{role: "user", content: $prompt}]
        }')
    fi

    IO:debug "Request URL: $PROVIDER_URL"
    IO:debug "Request body: $request_body"

    response=$(curl -s --max-time "$TIMEOUT" \
      -H "x-api-key: $api_key" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      -d "$request_body" \
      "$PROVIDER_URL" 2>&1)
  else
    # OpenAI-compatible format (OpenAI, OpenRouter, GoogleAI)
    if [[ -n "$output_schema" ]]; then
      local tool_def
      tool_def=$(Prompt:build_openai_tool "$output_schema")
      request_body=$(jq -n \
        --arg model "$model" \
        --argjson prompt "$json_prompt" \
        --argjson tool "$tool_def" \
        '{
          model: $model,
          messages: [{role: "user", content: $prompt}],
          tools: [$tool],
          tool_choice: {type: "function", function: {name: "extract"}}
        }')
    else
      request_body=$(jq -n \
        --arg model "$model" \
        --argjson prompt "$json_prompt" \
        '{
          model: $model,
          messages: [{role: "user", content: $prompt}]
        }')
    fi

    IO:debug "Request URL: $PROVIDER_URL"
    IO:debug "Request body: $request_body"

    response=$(curl -s --max-time "$TIMEOUT" \
      -H "Authorization: Bearer $api_key" \
      -H "Content-Type: application/json" \
      -d "$request_body" \
      "$PROVIDER_URL" 2>&1)
  fi

  # Check for curl errors
  if [[ $? -ne 0 ]]; then
    IO:die "Request failed: $response"
  fi

  # Check for API errors in response
  local error_msg
  error_msg=$(echo "$response" | jq -r '.error.message // .error.type // .error // empty' 2>/dev/null)
  if [[ -n "$error_msg" ]]; then
    IO:die "API error: $error_msg"
  fi

  IO:debug "Response: $response"
  echo "$response"
}

function Provider:extract() {
  local response="$1"
  local provider="$2"

  if [[ "$provider" == "anthropic" ]]; then
    # Check for tool_use block first
    local tool_input
    tool_input=$(echo "$response" | jq -r '.content[] | select(.type == "tool_use") | .input' 2>/dev/null)
    if [[ -n "$tool_input" && "$tool_input" != "null" ]]; then
      echo "$tool_input" | jq .
      return 0
    fi
    # Fall back to text content
    echo "$response" | jq -r '.content[] | select(.type == "text") | .text // empty' 2>/dev/null
  else
    # OpenAI-compatible format
    local tool_args
    tool_args=$(echo "$response" | jq -r '.choices[0].message.tool_calls[0].function.arguments // empty' 2>/dev/null)
    if [[ -n "$tool_args" ]]; then
      echo "$tool_args"
      return 0
    fi
    echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null
  fi
}

#####################################################################
## Prompt File Parsing
#####################################################################

function Prompt:parse_file() {
  local file="$1"
  [[ ! -f "$file" ]] && IO:die "Prompt file not found: $file"

  local content
  content=$(cat "$file")

  # Check if file has frontmatter
  if [[ "$content" != "---"* ]]; then
    YAML_DATA=()
    PROMPT_TEMPLATE="$content"
    return 0
  fi

  # Split frontmatter from template
  local yaml_section
  local template_section

  # Use awk to split the file
  yaml_section=$(awk 'BEGIN{found=0} /^---$/{found++; next} found==1{print}' "$file")
  template_section=$(awk 'BEGIN{found=0} /^---$/{found++; next} found>=2{print}' "$file")

  IO:debug "YAML section: $yaml_section"
  IO:debug "Template section: $template_section"

  Prompt:parse_yaml "$yaml_section"
  PROMPT_TEMPLATE="$template_section"
}

function Prompt:parse_yaml() {
  local yaml_content="$1"

  # Reset associative array
  YAML_DATA=()

  local current_section=""
  local current_subsection=""

  while IFS= read -r line; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    # Detect indentation level
    local indent="${line%%[![:space:]]*}"
    local indent_level=${#indent}

    # Remove leading whitespace for processing
    local trimmed="${line#"${line%%[![:space:]]*}"}"

    # Check for section (key with no value or colon only)
    if [[ "$trimmed" =~ ^([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*$ ]]; then
      local key="${BASH_REMATCH[1]}"
      if [[ $indent_level -eq 0 ]]; then
        current_section="$key"
        current_subsection=""
      elif [[ $indent_level -eq 2 && -n "$current_section" ]]; then
        current_subsection="$key"
      fi
      continue
    fi

    # Key-value pair
    if [[ "$trimmed" =~ ^([a-zA-Z_?][a-zA-Z0-9_?]*)[[:space:]]*:[[:space:]]*(.+)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"

      # Build full key path
      local full_key="$key"
      if [[ -n "$current_subsection" ]]; then
        full_key="${current_section}.${current_subsection}.${key}"
      elif [[ -n "$current_section" && $indent_level -gt 0 ]]; then
        full_key="${current_section}.${key}"
      fi

      YAML_DATA["$full_key"]="$value"
      IO:debug "YAML: $full_key = $value"
    fi
  done <<< "$yaml_content"
}

function Prompt:get_meta() {
  local key="$1"
  echo "${YAML_DATA[$key]:-}"
}

#####################################################################
## Template Rendering
#####################################################################

function Prompt:render() {
  local template="$1"
  local result="$template"

  # Replace {{STDIN}} with raw stdin content
  if [[ -n "$STDIN_RAW" ]]; then
    result="${result//\{\{STDIN\}\}/$STDIN_RAW}"
  fi

  # Replace other {{variable}} placeholders
  for key in "${!TEMPLATE_VARS[@]}"; do
    local placeholder="{{${key}}}"
    local value="${TEMPLATE_VARS[$key]}"
    result="${result//$placeholder/$value}"
  done

  echo "$result"
}

function Prompt:read_stdin() {
  STDIN_RAW=""
  TEMPLATE_VARS=()

  # Check if stdin has data
  if [[ ! -t 0 ]]; then
    STDIN_RAW=$(cat)
    IO:debug "Read stdin: ${#STDIN_RAW} chars"

    # Try to parse as JSON
    if echo "$STDIN_RAW" | jq . >/dev/null 2>&1; then
      IO:debug "Stdin is valid JSON, parsing variables"
      # Extract all top-level keys and values
      while IFS="=" read -r key value; do
        [[ -n "$key" ]] && TEMPLATE_VARS["$key"]="$value"
        IO:debug "Template var: $key = $value"
      done < <(echo "$STDIN_RAW" | jq -r 'to_entries | .[] | "\(.key)=\(.value)"' 2>/dev/null)
    else
      IO:debug "Stdin is not JSON, treating as raw text"
      # Check if there's an input schema to determine the variable name
      local first_input_key
      first_input_key=$(Prompt:get_meta "input.schema" | head -1)
      if [[ -n "$first_input_key" ]]; then
        # Get first key from input schema
        for key in "${!YAML_DATA[@]}"; do
          if [[ "$key" == input.schema.* ]]; then
            local var_name="${key#input.schema.}"
            var_name="${var_name%%\?}"  # Remove trailing ?
            TEMPLATE_VARS["$var_name"]="$STDIN_RAW"
            IO:debug "Assigned stdin to input schema var: $var_name"
            break
          fi
        done
      fi
      # Also set "input" as fallback
      TEMPLATE_VARS["input"]="$STDIN_RAW"
    fi
  fi
}

#####################################################################
## Tool/Schema Building for Structured Output
#####################################################################

function Prompt:build_tool() {
  # Build Anthropic tool format from output schema
  local schema_json="{}"

  local properties="{}"
  local required="[]"

  for key in "${!YAML_DATA[@]}"; do
    if [[ "$key" == output.schema.* ]]; then
      local field_name="${key#output.schema.}"
      local field_def="${YAML_DATA[$key]}"
      local is_optional=false

      # Check if field is optional (ends with ?)
      if [[ "$field_name" == *"?" ]]; then
        is_optional=true
        field_name="${field_name%?}"
      fi

      # Parse type and description: "type, description"
      local field_type="string"
      local field_desc=""
      if [[ "$field_def" == *","* ]]; then
        field_type="${field_def%%,*}"
        field_type="${field_type// /}"
        field_desc="${field_def#*,}"
        field_desc="${field_desc# }"
      else
        field_type="${field_def// /}"
      fi

      # Map to JSON Schema types
      local json_type="string"
      case "$field_type" in
        number) json_type="number" ;;
        boolean) json_type="boolean" ;;
        *) json_type="string" ;;
      esac

      # Build property
      if [[ -n "$field_desc" ]]; then
        properties=$(echo "$properties" | jq --arg k "$field_name" --arg t "$json_type" --arg d "$field_desc" \
          '. + {($k): {type: $t, description: $d}}')
      else
        properties=$(echo "$properties" | jq --arg k "$field_name" --arg t "$json_type" \
          '. + {($k): {type: $t}}')
      fi

      # Add to required if not optional
      if [[ "$is_optional" == "false" ]]; then
        required=$(echo "$required" | jq --arg k "$field_name" '. + [$k]')
      fi
    fi
  done

  # Build Anthropic tool format
  jq -n \
    --argjson props "$properties" \
    --argjson req "$required" \
    '{
      name: "extract",
      description: "Extract structured data",
      input_schema: {
        type: "object",
        properties: $props,
        required: $req
      }
    }'
}

function Prompt:build_openai_tool() {
  # Build OpenAI tool format from output schema
  local properties="{}"
  local required="[]"

  for key in "${!YAML_DATA[@]}"; do
    if [[ "$key" == output.schema.* ]]; then
      local field_name="${key#output.schema.}"
      local field_def="${YAML_DATA[$key]}"
      local is_optional=false

      if [[ "$field_name" == *"?" ]]; then
        is_optional=true
        field_name="${field_name%?}"
      fi

      local field_type="string"
      local field_desc=""
      if [[ "$field_def" == *","* ]]; then
        field_type="${field_def%%,*}"
        field_type="${field_type// /}"
        field_desc="${field_def#*,}"
        field_desc="${field_desc# }"
      else
        field_type="${field_def// /}"
      fi

      local json_type="string"
      case "$field_type" in
        number) json_type="number" ;;
        boolean) json_type="boolean" ;;
        *) json_type="string" ;;
      esac

      if [[ -n "$field_desc" ]]; then
        properties=$(echo "$properties" | jq --arg k "$field_name" --arg t "$json_type" --arg d "$field_desc" \
          '. + {($k): {type: $t, description: $d}}')
      else
        properties=$(echo "$properties" | jq --arg k "$field_name" --arg t "$json_type" \
          '. + {($k): {type: $t}}')
      fi

      if [[ "$is_optional" == "false" ]]; then
        required=$(echo "$required" | jq --arg k "$field_name" '. + [$k]')
      fi
    fi
  done

  jq -n \
    --argjson props "$properties" \
    --argjson req "$required" \
    '{
      type: "function",
      function: {
        name: "extract",
        description: "Extract structured data",
        parameters: {
          type: "object",
          properties: $props,
          required: $req
        }
      }
    }'
}

function Prompt:has_output_schema() {
  for key in "${!YAML_DATA[@]}"; do
    if [[ "$key" == output.schema.* ]]; then
      return 0
    fi
  done
  return 1
}

#####################################################################
## Main Template Action
#####################################################################

function Prompt:apply_env_overrides() {
  # Apply RUNPROMPT_* environment variable overrides to YAML_DATA
  for env_key in $(compgen -A variable | grep "^RUNPROMPT_"); do
    local key="${env_key#RUNPROMPT_}"
    key="${key,,}"  # lowercase
    local value="${!env_key}"
    IO:debug "Override from env $env_key: $key = $value"
    YAML_DATA["$key"]="$value"
    # Also add to template vars for direct substitution
    TEMPLATE_VARS["$key"]="$value"
  done
}

function do_template() {
  local prompt_file="$input"
  [[ -z "$prompt_file" ]] && IO:die "No prompt file specified"
  [[ ! -f "$prompt_file" ]] && IO:die "Prompt file not found: $prompt_file"

  IO:debug "Processing prompt file: $prompt_file"

  # Parse the prompt file
  Prompt:parse_file "$prompt_file"

  # Read stdin and parse variables
  Prompt:read_stdin

  # Apply RUNPROMPT_* environment overrides
  Prompt:apply_env_overrides

  # Get model from CLI or YAML (CLI takes precedence)
  local model_str="${MODEL:-}"
  [[ -z "$model_str" ]] && model_str=$(Prompt:get_meta "model")
  [[ -z "$model_str" ]] && IO:die "No model specified. Use --MODEL or set model in prompt file"

  IO:debug "Using model: $model_str"

  # Parse provider and model name
  Provider:parse_model "$model_str"
  IO:debug "Provider: $PROVIDER, Model: $MODEL_NAME"

  # Render the template
  local rendered_prompt
  rendered_prompt=$(Prompt:render "$PROMPT_TEMPLATE")
  IO:debug "Rendered prompt: $rendered_prompt"

  # Make API request or load test response
  local response
  if [[ "$PROVIDER" == "test" ]]; then
    local test_file="${prompt_file}.test-response"
    [[ ! -f "$test_file" ]] && IO:die "Test response file not found: $test_file"
    response=$(cat "$test_file")
    # Get provider from test response for extraction
    local test_provider
    test_provider=$(echo "$response" | jq -r '._provider // "openai"')
    PROVIDER="$test_provider"
    IO:debug "Loaded test response, provider: $PROVIDER"
  else
    # Check for output schema
    local output_schema=""
    if Prompt:has_output_schema; then
      output_schema="yes"
      IO:debug "Output schema detected"
    fi
    response=$(Provider:make_request "$PROVIDER" "$MODEL_NAME" "$rendered_prompt" "$output_schema")
  fi

  # Save response if requested
  if [[ -n "${SAVE:-}" ]]; then
    echo "$response" > "$SAVE"
    IO:debug "Saved response to: $SAVE"
  fi

  # Extract and output result
  Provider:extract "$response" "$PROVIDER"
}

#####################################################################
################### DO NOT MODIFY BELOW THIS LINE ###################
#####################################################################

action=""
error_prefix=""
git_repo_remote=""
git_repo_root=""
install_package=""
os_kernel=""
os_machine=""
os_name=""
os_version=""
script_basename=""
script_hash="?"
script_lines="?"
script_prefix=""
shell_brand=""
shell_version=""
temp_files=()

# set strict mode -  via http://redsymbol.net/articles/unofficial-bash-strict-mode/
# removed -e because it made basic [[ testing ]] difficult
set -uo pipefail
IFS=$'\n\t'
FORCE=0
help=0

#to enable VERBOSE even before option parsing
VERBOSE=0
[[ $# -gt 0 ]] && [[ $1 == "-v" ]] && VERBOSE=1

#to enable QUIET even before option parsing
QUIET=0
[[ $# -gt 0 ]] && [[ $1 == "-q" ]] && QUIET=1

txtReset=""
txtError=""
txtInfo=""
txtInfo=""
txtWarn=""
txtBold=""
txtItalic=""
txtUnderline=""

char_succes="OK "
char_fail="!! "
char_alert="?? "
char_wait="..."
info_icon="(i)"
config_icon="[c]"
clean_icon="[c]"
require_icon="[r]"

### stdIO:print/stderr output
function IO:initialize() {
  script_started_at="$(Tool:time)"
  IO:debug "script $script_basename started at $script_started_at"

  [[ "${BASH_SOURCE[0]:-}" != "${0}" ]] && sourced=1 || sourced=0
  [[ -t 1 ]] && piped=0 || piped=1 # detect if output is piped
  if [[ $piped -eq 0 && -n "$TERM" ]]; then
    txtReset=$(tput sgr0)
    txtError=$(tput setaf 160)
    txtInfo=$(tput setaf 2)
    txtWarn=$(tput setaf 214)
    txtBold=$(tput bold)
    txtItalic=$(tput sitm)
    txtUnderline=$(tput smul)
  fi

  [[ $(echo -e '\xe2\x82\xac') == '€' ]] && unicode=1 || unicode=0 # detect if unicode is supported
  if [[ $unicode -gt 0 ]]; then
    char_succes="✅"
    char_fail="⛔"
    char_alert="✴️"
    char_wait="⏳"
    info_icon="🌼"
    config_icon="🌱"
    clean_icon="🧽"
    require_icon="🔌"
  fi
  error_prefix="${txtError}>${txtReset}"
}

function IO:print() {
  ((QUIET)) && true || printf '%b\n' "$*"
}

function IO:debug() {
  ((VERBOSE)) && IO:print "${txtInfo}# $* ${txtReset}" >&2
  true
}

function IO:die() {
  IO:print "${txtError}${char_fail} $script_basename${txtReset}: $*" >&2
  Os:beep
  Script:exit
}

function IO:alert() {
  IO:print "${txtWarn}${char_alert}${txtReset}: ${txtUnderline}$*${txtReset}" >&2
}

function IO:success() {
  IO:print "${txtInfo}${char_succes}${txtReset}  ${txtBold}$*${txtReset}"
}

function IO:announce() {
  IO:print "${txtInfo}${char_wait}${txtReset}  ${txtItalic}$*${txtReset}"
  sleep 1
}

function IO:progress() {
  ((QUIET)) || (
    local screen_width
    screen_width=$(tput cols 2>/dev/null || echo 80)
    local rest_of_line
    rest_of_line=$((screen_width - 5))

    if ((piped)); then
      IO:print "... $*" >&2
    else
      printf "... %-${rest_of_line}b\r" "$*                                             " >&2
    fi
  )
}

function IO:countdown() {
  local seconds=${1:-5}
  local message=${2:-Countdown :}
  local i

  if ((piped)); then
    IO:print "$message $seconds seconds"
  else
    for ((i = 0; i < "$seconds"; i++)); do
      IO:progress "${txtInfo}$message $((seconds - i)) seconds${txtReset}"
      sleep 1
    done
    IO:print "                         "
  fi
}

### interactive
function IO:confirm() {
  ((FORCE)) && return 0
  read -r -p "$1 [y/N] " -n 1
  echo " "
  [[ $REPLY =~ ^[Yy]$ ]]
}

function IO:question() {
  local ANSWER
  local DEFAULT=${2:-}
  read -r -p "$1 ($DEFAULT) > " ANSWER
  [[ -z "$ANSWER" ]] && echo "$DEFAULT" || echo "$ANSWER"
}

function IO:log() {
  [[ -n "${log_file:-}" ]] && echo "$(date '+%H:%M:%S') | $*" >>"$log_file"
}

function Tool:calc() {
  awk "BEGIN {print $*} ; "
}

function Tool:round() {
  local number="${1}"
  local decimals="${2:-0}"

  awk "BEGIN {print sprintf( \"%.${decimals}f\" , $number )};"
}

function Tool:time() {
  if [[ $(command -v perl) ]]; then
    perl -MTime::HiRes=time -e 'printf "%f\n", time'
  elif [[ $(command -v php) ]]; then
    php -r 'printf("%f\n",microtime(true));'
  elif [[ $(command -v python) ]]; then
    python -c 'import time; print(time.time()) '
  elif [[ $(command -v python3) ]]; then
    python3 -c 'import time; print(time.time()) '
  elif [[ $(command -v node) ]]; then
    node -e 'console.log(+new Date() / 1000)'
  elif [[ $(command -v ruby) ]]; then
    ruby -e 'STDOUT.puts(Time.now.to_f)'
  else
    date '+%s.000'
  fi
}

function Tool:throughput() {
  local time_started="$1"
  [[ -z "$time_started" ]] && time_started="$script_started_at"
  local operations="${2:-1}"
  local name="${3:-operation}"

  local time_finished
  local duration
  local seconds
  time_finished="$(Tool:time)"
  duration="$(Tool:calc "$time_finished - $time_started")"
  seconds="$(Tool:round "$duration")"
  local ops
  if [[ "$operations" -gt 1 ]]; then
    if [[ $operations -gt $seconds ]]; then
      ops=$(Tool:calc "$operations / $duration")
      ops=$(Tool:round "$ops" 3)
      duration=$(Tool:round "$duration" 2)
      IO:print "$operations $name finished in $duration secs: $ops $name/sec"
    else
      ops=$(Tool:calc "$duration / $operations")
      ops=$(Tool:round "$ops" 3)
      duration=$(Tool:round "$duration" 2)
      IO:print "$operations $name finished in $duration secs: $ops sec/$name"
    fi
  else
    duration=$(Tool:round "$duration" 2)
    IO:print "$name finished in $duration secs"
  fi
}

### string processing

function Str:trim() {
  local var="$*"
  # remove leading whitespace characters
  var="${var#"${var%%[![:space:]]*}"}"
  # remove trailing whitespace characters
  var="${var%"${var##*[![:space:]]}"}"
  printf '%s' "$var"
}

function Str:lower() {
  if [[ -n "$1" ]]; then
    local input="$*"
    echo "${input,,}"
  else
    awk '{print tolower($0)}'
  fi
}

function Str:upper() {
  if [[ -n "$1" ]]; then
    local input="$*"
    echo "${input^^}"
  else
    awk '{print toupper($0)}'
  fi
}

function Str:ascii() {
  # remove all characters with accents/diacritics to latin alphabet
  # shellcheck disable=SC2020
  sed 'y/àáâäæãåāǎçćčèéêëēėęěîïííīįìǐłñńôöòóœøōǒõßśšûüǔùǖǘǚǜúūÿžźżÀÁÂÄÆÃÅĀǍÇĆČÈÉÊËĒĖĘĚÎÏÍÍĪĮÌǏŁÑŃÔÖÒÓŒØŌǑÕẞŚŠÛÜǓÙǕǗǙǛÚŪŸŽŹŻ/aaaaaaaaaccceeeeeeeeiiiiiiiilnnooooooooosssuuuuuuuuuuyzzzAAAAAAAAACCCEEEEEEEEIIIIIIIILNNOOOOOOOOOSSSUUUUUUUUUUYZZZ/'
}

function Str:slugify() {
  # Str:slugify <input> <separator>
  # Str:slugify "Jack, Jill & Clémence LTD"      => jack-jill-clemence-ltd
  # Str:slugify "Jack, Jill & Clémence LTD" "_"  => jack_jill_clemence_ltd
  separator="${2:-}"
  [[ -z "$separator" ]] && separator="-"
  Str:lower "$1" |
    Str:ascii |
    awk '{
          gsub(/[\[\]@#$%^&*;,.:()<>!?\/+=_]/," ",$0);
          gsub(/^  */,"",$0);
          gsub(/  *$/,"",$0);
          gsub(/  */,"-",$0);
          gsub(/[^a-z0-9\-]/,"");
          print;
          }' |
    sed "s/-/$separator/g"
}

function Str:title() {
  # Str:title <input> <separator>
  # Str:title "Jack, Jill & Clémence LTD"     => JackJillClemenceLtd
  # Str:title "Jack, Jill & Clémence LTD" "_" => Jack_Jill_Clemence_Ltd
  separator="${2:-}"
  # shellcheck disable=SC2020
  Str:lower "$1" |
    tr 'àáâäæãåāçćčèéêëēėęîïííīįìłñńôöòóœøōõßśšûüùúūÿžźż' 'aaaaaaaaccceeeeeeeiiiiiiilnnoooooooosssuuuuuyzzz' |
    awk '{ gsub(/[\[\]@#$%^&*;,.:()<>!?\/+=_-]/," ",$0); print $0; }' |
    awk '{
          for (i=1; i<=NF; ++i) {
              $i = toupper(substr($i,1,1)) tolower(substr($i,2))
          };
          print $0;
          }' |
    sed "s/ /$separator/g" |
    cut -c1-50
}

function Str:digest() {
  local length=${1:-6}
  if [[ -n $(command -v md5sum) ]]; then
    # regular linux
    md5sum | cut -c1-"$length"
  else
    # macos
    md5 | cut -c1-"$length"
  fi
}

# Gha: function should only be run inside of a Github Action

function Gha:finish() {
  [[ -z "${RUNNER_OS:-}" ]] && IO:die "This should only run inside a Github Action, don't run it on your machine"
  local timestamp message
  git config user.name "Bashew Runner"
  git config user.email "actions@users.noreply.github.com"
  git add -A
  timestamp="$(date -u)"
  message="$timestamp < $script_basename $script_version"
  IO:print "Commit Message: $message"
  git commit -m "${message}" || exit 0
  git pull --rebase
  git push
  IO:success "Commit OK!"
}

trap "IO:die \"ERROR \$? after \$SECONDS seconds \n\
\${error_prefix} last command : '\$BASH_COMMAND' \" \
\$(< \$script_install_path awk -v lineno=\$LINENO \
'NR == lineno {print \"\${error_prefix} from line \" lineno \" : \" \$0}')" INT TERM EXIT
# cf https://askubuntu.com/questions/513932/what-is-the-bash-command-variable-good-for

Script:exit() {
  local temp_file
  for temp_file in "${temp_files[@]-}"; do
    [[ -f "$temp_file" ]] && (
      IO:debug "Delete temp file [$temp_file]"
      rm -f "$temp_file"
    )
  done
  trap - INT TERM EXIT
  IO:debug "$script_basename finished after $SECONDS seconds"
  exit 0
}

Script:check_version() {
  (
    # shellcheck disable=SC2164
    pushd "$script_install_folder" &>/dev/null
    if [[ -d .git ]]; then
      local remote
      remote="$(git remote -v | grep fetch | awk 'NR == 1 {print $2}')"
      IO:progress "Check for updates - $remote"
      git remote update &>/dev/null
      if [[ $(git rev-list --count "HEAD...HEAD@{upstream}" 2>/dev/null) -gt 0 ]]; then
        IO:print "There is a more recent update of this script - run <<$script_prefix update>> to update"
      else
        IO:progress "                                         "
      fi
    fi
    # shellcheck disable=SC2164
    popd &>/dev/null
  )
}

Script:git_pull() {
  # run in background to avoid problems with modifying a running interpreted script
  (
    sleep 1
    cd "$script_install_folder" && git pull
  ) &
}

Script:show_tips() {
  ((sourced)) && return 0
  # shellcheck disable=SC2016
  grep <"${BASH_SOURCE[0]}" -v '$0' |
    awk \
      -v green="$txtInfo" \
      -v yellow="$txtWarn" \
      -v reset="$txtReset" \
      '
      /TIP: /  {$1=""; gsub(/«/,green); gsub(/»/,reset); print "*" $0}
      /TIP:> / {$1=""; print " " yellow $0 reset}
      ' |
    awk \
      -v script_basename="$script_basename" \
      -v script_prefix="$script_prefix" \
      '{
      gsub(/\$script_basename/,script_basename);
      gsub(/\$script_prefix/,script_prefix);
      print ;
      }'
}

Script:check() {
  local name
  if [[ -n $(Option:filter flag) ]]; then
    IO:print "## ${txtInfo}boolean flags${txtReset}:"
    Option:filter flag |
      grep -v help |
      while read -r name; do
        declare -p "$name" | cut -d' ' -f3-
      done
  fi

  if [[ -n $(Option:filter option) ]]; then
    IO:print "## ${txtInfo}option defaults${txtReset}:"
    Option:filter option |
      while read -r name; do
        declare -p "$name" | cut -d' ' -f3-
      done
  fi

  if [[ -n $(Option:filter list) ]]; then
    IO:print "## ${txtInfo}list options${txtReset}:"
    Option:filter list |
      while read -r name; do
        declare -p "$name" | cut -d' ' -f3-
      done
  fi

  if [[ -n $(Option:filter param) ]]; then
    if ((piped)); then
      IO:debug "Skip parameters for .env files"
    else
      IO:print "## ${txtInfo}parameters${txtReset}:"
      Option:filter param |
        while read -r name; do
          declare -p "$name" | cut -d' ' -f3-
        done
    fi
  fi

  if [[ -n $(Option:filter choice) ]]; then
    if ((piped)); then
      IO:debug "Skip choices for .env files"
    else
      IO:print "## ${txtInfo}choice${txtReset}:"
      Option:filter choice |
        while read -r name; do
          declare -p "$name" | cut -d' ' -f3-
        done
    fi
  fi

  IO:print "## ${txtInfo}required commands${txtReset}:"
  Script:show_required
}

Option:usage() {
  IO:print "Program : ${txtInfo}$script_basename${txtReset}  by ${txtWarn}$script_author${txtReset}"
  IO:print "Version : ${txtInfo}v$script_version${txtReset} (${txtWarn}$script_modified${txtReset})"
  IO:print "Purpose : ${txtInfo}$script_description${txtReset}"
  echo -n "Usage   : $script_basename"
  Option:config |
    awk '
  BEGIN { FS="|"; OFS=" "; oneline="" ; fulltext="Flags, options and parameters:"}
  $1 ~ /flag/  {
    fulltext = fulltext sprintf("\n    -%1s|--%-12s: [flag] %s [default: off]",$2,$3,$4) ;
    oneline  = oneline " [-" $2 "]"
    }
  $1 ~ /option/  {
    fulltext = fulltext sprintf("\n    -%1s|--%-12s: [option] %s",$2,$3 " <?>",$4) ;
    if($5!=""){fulltext = fulltext "  [default: " $5 "]"; }
    oneline  = oneline " [-" $2 " <" $3 ">]"
    }
  $1 ~ /list/  {
    fulltext = fulltext sprintf("\n    -%1s|--%-12s: [list] %s (array)",$2,$3 " <?>",$4) ;
    fulltext = fulltext "  [default empty]";
    oneline  = oneline " [-" $2 " <" $3 ">]"
    }
  $1 ~ /secret/  {
    fulltext = fulltext sprintf("\n    -%1s|--%s <%s>: [secret] %s",$2,$3,"?",$4) ;
      oneline  = oneline " [-" $2 " <" $3 ">]"
    }
  $1 ~ /param/ {
    if($2 == "1"){
          fulltext = fulltext sprintf("\n    %-17s: [parameter] %s","<"$3">",$4);
          oneline  = oneline " <" $3 ">"
     }
     if($2 == "?"){
          fulltext = fulltext sprintf("\n    %-17s: [parameter] %s (optional)","<"$3">",$4);
          oneline  = oneline " <" $3 "?>"
     }
     if($2 == "n"){
          fulltext = fulltext sprintf("\n    %-17s: [parameters] %s (1 or more)","<"$3">",$4);
          oneline  = oneline " <" $3 " …>"
     }
    }
  $1 ~ /choice/ {
        fulltext = fulltext sprintf("\n    %-17s: [choice] %s","<"$3">",$4);
        if($5!=""){fulltext = fulltext "  [options: " $5 "]"; }
        oneline  = oneline " <" $3 ">"
    }
    END {print oneline; print fulltext}
  '
}

function Option:filter() {
  Option:config | grep "$1|" | cut -d'|' -f3 | sort | grep -v '^\s*$'
}

function Script:show_required() {
  grep 'Os:require' "$script_install_path" |
    grep -v -E '\(\)|grep|# Os:require' |
    awk -v install="# $install_package " '
    function ltrim(s) { sub(/^[ "\t\r\n]+/, "", s); return s }
    function rtrim(s) { sub(/[ "\t\r\n]+$/, "", s); return s }
    function trim(s) { return rtrim(ltrim(s)); }
    NF == 2 {print install trim($2); }
    NF == 3 {print install trim($3); }
    NF > 3  {$1=""; $2=""; $0=trim($0); print "# " trim($0);}
  ' |
    sort -u
}

function Option:initialize() {
  local init_command
  init_command=$(Option:config |
    grep -v "VERBOSE|" |
    awk '
    BEGIN { FS="|"; OFS=" ";}
    $1 ~ /flag/   && $5 == "" {print $3 "=0; "}
    $1 ~ /flag/   && $5 != "" {print $3 "=\"" $5 "\"; "}
    $1 ~ /option/ && $5 == "" {print $3 "=\"\"; "}
    $1 ~ /option/ && $5 != "" {print $3 "=\"" $5 "\"; "}
    $1 ~ /choice/   {print $3 "=\"\"; "}
    $1 ~ /list/     {print $3 "=(); "}
    $1 ~ /secret/   {print $3 "=\"\"; "}
    ')
  if [[ -n "$init_command" ]]; then
    eval "$init_command"
  fi
}

function Option:has_single() { Option:config | grep 'param|1|' >/dev/null; }
function Option:has_choice() { Option:config | grep 'choice|1' >/dev/null; }
function Option:has_optional() { Option:config | grep 'param|?|' >/dev/null; }
function Option:has_multi() { Option:config | grep 'param|n|' >/dev/null; }

function Option:parse() {
  if [[ $# -eq 0 ]]; then
    Option:usage >&2
    Script:exit
  fi

  ## first process all the -x --xxxx flags and options
  while true; do
    # flag <flag> is saved as $flag = 0/1
    # option <option> is saved as $option
    if [[ $# -eq 0 ]]; then
      ## all parameters processed
      break
    fi
    if [[ ! $1 == -?* ]]; then
      ## all flags/options processed
      break
    fi
    local save_option
    save_option=$(Option:config |
      awk -v opt="$1" '
        BEGIN { FS="|"; OFS=" ";}
        $1 ~ /flag/   &&  "-"$2 == opt {print $3"=1"}
        $1 ~ /flag/   && "--"$3 == opt {print $3"=1"}
        $1 ~ /option/ &&  "-"$2 == opt {print $3"=${2:-}; shift"}
        $1 ~ /option/ && "--"$3 == opt {print $3"=${2:-}; shift"}
        $1 ~ /list/ &&  "-"$2 == opt {print $3"+=(${2:-}); shift"}
        $1 ~ /list/ && "--"$3 == opt {print $3"=(${2:-}); shift"}
        $1 ~ /secret/ &&  "-"$2 == opt {print $3"=${2:-}; shift #noshow"}
        $1 ~ /secret/ && "--"$3 == opt {print $3"=${2:-}; shift #noshow"}
        ')
    if [[ -n "$save_option" ]]; then
      if echo "$save_option" | grep shift >>/dev/null; then
        local save_var
        save_var=$(echo "$save_option" | cut -d= -f1)
        IO:debug "$config_icon parameter: ${save_var}=$2"
      else
        IO:debug "$config_icon flag: $save_option"
      fi
      eval "$save_option"
    else
      IO:die "cannot interpret option [$1]"
    fi
    shift
  done

  ((help)) && (
    Option:usage
    Script:check_version
    IO:print "                                  "
    echo "### TIPS & EXAMPLES"
    Script:show_tips

  ) && Script:exit

  local option_list
  local option_count
  local choices
  local single_params
  ## then run through the given parameters
  if Option:has_choice; then
    choices=$(Option:config | awk -F"|" '
      $1 == "choice" && $2 == 1 {print $3}
      ')
    option_list=$(xargs <<<"$choices")
    option_count=$(wc <<<"$choices" -w | xargs)
    IO:debug "$config_icon Expect : $option_count choice(s): $option_list"
    [[ $# -eq 0 ]] && IO:die "need the choice(s) [$option_list]"

    local choices_list
    local valid_choice
    local param
    for param in $choices; do
      [[ $# -eq 0 ]] && IO:die "need choice [$param]"
      [[ -z "$1" ]] && IO:die "need choice [$param]"
      IO:debug "$config_icon Assign : $param=$1"
      # check if choice is in list
      choices_list=$(Option:config | awk -F"|" -v choice="$param" '$1 == "choice" && $3 = choice {print $5}')
      valid_choice=$(tr <<<"$choices_list" "," "\n" | grep "$1")
      [[ -z "$valid_choice" ]] && IO:die "choice [$1] is not valid, should be in list [$choices_list]"

      eval "$param=\"$1\""
      shift
    done
  else
    IO:debug "$config_icon No choices to process"
    choices=""
    option_count=0
  fi

  if Option:has_single; then
    single_params=$(Option:config | awk -F"|" '
      $1 == "param" && $2 == 1 {print $3}
      ')
    option_list=$(xargs <<<"$single_params")
    option_count=$(wc <<<"$single_params" -w | xargs)
    IO:debug "$config_icon Expect : $option_count single parameter(s): $option_list"
    [[ $# -eq 0 ]] && IO:die "need the parameter(s) [$option_list]"

    for param in $single_params; do
      [[ $# -eq 0 ]] && IO:die "need parameter [$param]"
      [[ -z "$1" ]] && IO:die "need parameter [$param]"
      IO:debug "$config_icon Assign : $param=$1"
      eval "$param=\"$1\""
      shift
    done
  else
    IO:debug "$config_icon No single params to process"
    single_params=""
    option_count=0
  fi

  if Option:has_optional; then
    local optional_params
    local optional_count
    optional_params=$(Option:config | grep 'param|?|' | cut -d'|' -f3)
    optional_count=$(wc <<<"$optional_params" -w | xargs)
    IO:debug "$config_icon Expect : $optional_count optional parameter(s): $(echo "$optional_params" | xargs)"

    for param in $optional_params; do
      IO:debug "$config_icon Assign : $param=${1:-}"
      eval "$param=\"${1:-}\""
      shift
    done
  else
    IO:debug "$config_icon No optional params to process"
    optional_params=""
    optional_count=0
  fi

  if Option:has_multi; then
    #IO:debug "Process: multi param"
    local multi_count
    local multi_param
    multi_count=$(Option:config | grep -c 'param|n|')
    multi_param=$(Option:config | grep 'param|n|' | cut -d'|' -f3)
    IO:debug "$config_icon Expect : $multi_count multi parameter: $multi_param"
    ((multi_count > 1)) && IO:die "cannot have >1 'multi' parameter: [$multi_param]"
    ((multi_count > 0)) && [[ $# -eq 0 ]] && IO:die "need the (multi) parameter [$multi_param]"
    # save the rest of the params in the multi param
    if [[ -n "$*" ]]; then
      IO:debug "$config_icon Assign : $multi_param=$*"
      eval "$multi_param=( $* )"
    fi
  else
    multi_count=0
    multi_param=""
    [[ $# -gt 0 ]] && IO:die "cannot interpret extra parameters"
  fi
}

function Os:require() {
  local install_instructions
  local binary
  local words
  local path_binary
  # $1 = binary that is required
  binary="$1"
  path_binary=$(command -v "$binary" 2>/dev/null)
  [[ -n "$path_binary" ]] && IO:debug "️$require_icon required [$binary] -> $path_binary" && return 0
  # $2 = how to install it
  IO:alert "$script_basename needs [$binary] but it cannot be found"
  words=$(echo "${2:-}" | wc -w)
  install_instructions="$install_package $1"
  [[ $words -eq 1 ]] && install_instructions="$install_package $2"
  [[ $words -gt 1 ]] && install_instructions="${2:-}"
  if ((FORCE)); then
    IO:announce "Installing [$1] ..."
    eval "$install_instructions"
  else
    IO:alert "1) install package  : $install_instructions"
    IO:alert "2) check path       : export PATH=\"[path of your binary]:\$PATH\""
    IO:die "Missing program/script [$binary]"
  fi
}

function Os:folder() {
  if [[ -n "$1" ]]; then
    local folder="$1"
    local max_days=${2:-365}
    if [[ ! -d "$folder" ]]; then
      IO:debug "$clean_icon Create folder : [$folder]"
      mkdir -p "$folder"
    else
      IO:debug "$clean_icon Cleanup folder: [$folder] - delete files older than $max_days day(s)"
      find "$folder" -mtime "+$max_days" -type f -exec rm {} \;
    fi
  fi
}

function Os:follow_link() {
  [[ ! -L "$1" ]] && echo "$1" && return 0 ## if it's not a symbolic link, return immediately
  local file_folder link_folder link_name symlink
  file_folder="$(dirname "$1")"                                                                                   ## check if file has absolute/relative/no path
  [[ "$file_folder" != /* ]] && file_folder="$(cd -P "$file_folder" &>/dev/null && pwd)"                          ## a relative path was given, resolve it
  symlink=$(readlink "$1")                                                                                        ## follow the link
  link_folder=$(dirname "$symlink")                                                                               ## check if link has absolute/relative/no path
  [[ -z "$link_folder" ]] && link_folder="$file_folder"                                                           ## if no link path, stay in same folder
  [[ "$link_folder" == \.* ]] && link_folder="$(cd -P "$file_folder" && cd -P "$link_folder" &>/dev/null && pwd)" ## a relative link path was given, resolve it
  link_name=$(basename "$symlink")
  IO:debug "$info_icon Symbolic ln: $1 -> [$link_folder/$link_name]"
  Os:follow_link "$link_folder/$link_name" ## recurse
}

function Os:notify() {
  # cf https://levelup.gitconnected.com/5-modern-bash-scripting-techniques-that-only-a-few-programmers-know-4abb58ddadad
  local message="$1"
  local source="${2:-$script_basename}"

  [[ -n $(command -v notify-send) ]] && notify-send "$source" "$message"                                      # for Linux
  [[ -n $(command -v osascript) ]] && osascript -e "display notification \"$message\" with title \"$source\"" # for MacOS
}

function Os:busy() {
  # show spinner as long as process $pid is running
  local pid="$1"
  local message="${2:-}"
  local frames=("|" "/" "-" "\\")
  (
    while kill -0 "$pid" &>/dev/null; do
      for frame in "${frames[@]}"; do
        printf "\r[ $frame ] %s..." "$message"
        sleep 0.5
      done
    done
    printf "\n"
  )
}

function Os:beep() {
  if [[ -n "$TERM" ]]; then
    tput bel
  fi
}

function Script:meta() {

  script_prefix=$(basename "${BASH_SOURCE[0]}" .sh)
  script_basename=$(basename "${BASH_SOURCE[0]}")
  execution_day=$(date "+%Y-%m-%d")

  script_install_path="${BASH_SOURCE[0]}"
  IO:debug "$info_icon Script path: $script_install_path"
  script_install_path=$(Os:follow_link "$script_install_path")
  IO:debug "$info_icon Linked path: $script_install_path"
  script_install_folder="$(cd -P "$(dirname "$script_install_path")" && pwd)"
  IO:debug "$info_icon In folder  : $script_install_folder"
  if [[ -f "$script_install_path" ]]; then
    script_hash=$(Str:digest <"$script_install_path" 8)
    script_lines=$(awk <"$script_install_path" 'END {print NR}')
  fi

  # get shell/operating system/versions
  shell_brand="sh"
  shell_version="?"
  [[ -n "${ZSH_VERSION:-}" ]] && shell_brand="zsh" && shell_version="$ZSH_VERSION"
  [[ -n "${BASH_VERSION:-}" ]] && shell_brand="bash" && shell_version="$BASH_VERSION"
  [[ -n "${FISH_VERSION:-}" ]] && shell_brand="fish" && shell_version="$FISH_VERSION"
  [[ -n "${KSH_VERSION:-}" ]] && shell_brand="ksh" && shell_version="$KSH_VERSION"
  IO:debug "$info_icon Shell type : $shell_brand - version $shell_version"
  if [[ "$shell_brand" == "bash" && "${BASH_VERSINFO:-0}" -lt 4 ]]; then
    IO:die "Bash version 4 or higher is required - current version = ${BASH_VERSINFO:-0}"
  fi

  os_kernel=$(uname -s)
  os_version=$(uname -r)
  os_machine=$(uname -m)
  install_package=""
  case "$os_kernel" in
  CYGWIN* | MSYS* | MINGW*)
    os_name="Windows"
    ;;
  Darwin)
    os_name=$(sw_vers -productName)       # macOS
    os_version=$(sw_vers -productVersion) # 11.1
    install_package="brew install"
    ;;
  Linux | GNU*)
    if [[ $(command -v lsb_release) ]]; then
      # 'normal' Linux distributions
      os_name=$(lsb_release -i | awk -F: '{$1=""; gsub(/^[\s\t]+/,"",$2); gsub(/[\s\t]+$/,"",$2); print $2}')    # Ubuntu/Raspbian
      os_version=$(lsb_release -r | awk -F: '{$1=""; gsub(/^[\s\t]+/,"",$2); gsub(/[\s\t]+$/,"",$2); print $2}') # 20.04
    else
      # Synology, QNAP,
      os_name="Linux"
    fi
    [[ -x /bin/apt-cyg ]] && install_package="apt-cyg install"     # Cygwin
    [[ -x /bin/dpkg ]] && install_package="dpkg -i"                # Synology
    [[ -x /opt/bin/ipkg ]] && install_package="ipkg install"       # Synology
    [[ -x /usr/sbin/pkg ]] && install_package="pkg install"        # BSD
    [[ -x /usr/bin/pacman ]] && install_package="pacman -S"        # Arch Linux
    [[ -x /usr/bin/zypper ]] && install_package="zypper install"   # Suse Linux
    [[ -x /usr/bin/emerge ]] && install_package="emerge"           # Gentoo
    [[ -x /usr/bin/yum ]] && install_package="yum install"         # RedHat RHEL/CentOS/Fedora
    [[ -x /usr/bin/apk ]] && install_package="apk add"             # Alpine
    [[ -x /usr/bin/apt-get ]] && install_package="apt-get install" # Debian
    [[ -x /usr/bin/apt ]] && install_package="apt install"         # Ubuntu
    ;;

  esac
  IO:debug "$info_icon System OS  : $os_name ($os_kernel) $os_version on $os_machine"
  IO:debug "$info_icon Package mgt: $install_package"

  # get last modified date of this script
  script_modified="??"
  [[ "$os_kernel" == "Linux" ]] && script_modified=$(stat -c %y "$script_install_path" 2>/dev/null | cut -c1-16) # generic linux
  [[ "$os_kernel" == "Darwin" ]] && script_modified=$(stat -f "%Sm" "$script_install_path" 2>/dev/null)          # for MacOS

  IO:debug "$info_icon Version  : $script_version"
  IO:debug "$info_icon Created  : $script_created"
  IO:debug "$info_icon Modified : $script_modified"

  IO:debug "$info_icon Lines    : $script_lines lines / md5: $script_hash"
  IO:debug "$info_icon User     : $USER@$HOSTNAME"

  # if run inside a git repo, detect for which remote repo it is
  if git status &>/dev/null; then
    git_repo_remote=$(git remote -v | awk '/(fetch)/ {print $2}')
    IO:debug "$info_icon git remote : $git_repo_remote"
    git_repo_root=$(git rev-parse --show-toplevel)
    IO:debug "$info_icon git folder : $git_repo_root"
  fi

  # get script version from VERSION.md file - which is automatically updated by pforret/setver
  [[ -f "$script_install_folder/VERSION.md" ]] && script_version=$(cat "$script_install_folder/VERSION.md")
  # get script version from git tag file - which is automatically updated by pforret/setver
  [[ -n "$git_repo_root" ]] && [[ -n "$(git tag &>/dev/null)" ]] && script_version=$(git tag --sort=version:refname | tail -1)
}

function Script:initialize() {
  log_file=""
  if [[ -n "${TMP_DIR:-}" ]]; then
    # clean up TMP folder after 1 day
    Os:folder "$TMP_DIR" 1
  fi
  if [[ -n "${LOG_DIR:-}" ]]; then
    # clean up LOG folder after 1 month
    Os:folder "$LOG_DIR" 30
    log_file="$LOG_DIR/$script_prefix.$execution_day.log"
    IO:debug "$config_icon log_file: $log_file"
  fi
}

function Os:tempfile() {
  local extension=${1:-txt}
  local file="${TMP_DIR:-/tmp}/$execution_day.$RANDOM.$extension"
  IO:debug "$config_icon tmp_file: $file"
  temp_files+=("$file")
  echo "$file"
}

function Os:import_env() {
  local env_files
  if [[ $(pwd) == "$script_install_folder" ]]; then
    env_files=(
      "$script_install_folder/.env"
      "$script_install_folder/.$script_prefix.env"
      "$script_install_folder/$script_prefix.env"
    )
  else
    env_files=(
      "$script_install_folder/.env"
      "$script_install_folder/.$script_prefix.env"
      "$script_install_folder/$script_prefix.env"
      "./.env"
      "./.$script_prefix.env"
      "./$script_prefix.env"
    )
  fi

  local env_file
  for env_file in "${env_files[@]}"; do
    if [[ -f "$env_file" ]]; then
      IO:debug "$config_icon Read  dotenv: [$env_file]"
      local clean_file
      clean_file=$(Os:clean_env "$env_file")
      # shellcheck disable=SC1090
      source "$clean_file" && rm "$clean_file"
    fi
  done
}

function Os:clean_env() {
  local input="$1"
  local output="$1.__.sh"
  [[ ! -f "$input" ]] && IO:die "Input file [$input] does not exist"
  IO:debug "$clean_icon Clean dotenv: [$output]"
  awk <"$input" '
      function ltrim(s) { sub(/^[ \t\r\n]+/, "", s); return s }
      function rtrim(s) { sub(/[ \t\r\n]+$/, "", s); return s }
      function trim(s) { return rtrim(ltrim(s)); }
      /=/ { # skip lines with no equation
        $0=trim($0);
        if(substr($0,1,1) != "#"){ # skip comments
          equal=index($0, "=");
          key=trim(substr($0,1,equal-1));
          val=trim(substr($0,equal+1));
          if(match(val,/^".*"$/) || match(val,/^\047.*\047$/)){
            print key "=" val
          } else {
            print key "=\"" val "\""
          }
        }
      }
  ' >"$output"
  echo "$output"
}

IO:initialize # output settings
Script:meta   # find installation folder

[[ $run_as_root == 1 ]] && [[ $UID -ne 0 ]] && IO:die "user is $USER, MUST be root to run [$script_basename]"
[[ $run_as_root == -1 ]] && [[ $UID -eq 0 ]] && IO:die "user is $USER, CANNOT be root to run [$script_basename]"

Option:initialize # set default values for flags & options
Os:import_env     # overwrite with .env if any

if [[ $sourced -eq 0 ]]; then
  Option:parse "$@" # overwrite with specified options if any
  Script:initialize # clean up folders
  Script:main       # run Script:main program
  Script:exit       # exit and clean up
else
  # just disable the trap, don't execute Script:main
  trap - INT TERM EXIT
fi
