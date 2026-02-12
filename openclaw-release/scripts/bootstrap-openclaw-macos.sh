#!/usr/bin/env bash
set -euo pipefail

cd "$HOME"

if ! command -v openclaw >/dev/null 2>&1; then
  echo "openclaw was not found. Install openclaw first."
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "node was not found. Install Node.js 18+ first."
  exit 1
fi

prompt_secret() {
  local prompt="$1"
  local value=""
  if [[ -r /dev/tty ]]; then
    read -r -s -p "$prompt" value </dev/tty
    echo >/dev/tty
  else
    return 1
  fi
  printf '%s' "$value"
}

primary_provider="${OPENCLAW_PRIMARY_PROVIDER:-primary}"
primary_base_url="${OPENCLAW_PRIMARY_BASE_URL:-https://www.aistock.tech/v1}"
primary_model="${OPENCLAW_PRIMARY_MODEL:-gpt-5.3-codex}"
primary_api="${OPENCLAW_PRIMARY_API:-openai-responses}"

backup_provider="${OPENCLAW_BACKUP_PROVIDER:-backup}"
backup_base_url="${OPENCLAW_BACKUP_BASE_URL:-https://cdn.12ai.org/v1}"
backup_model="${OPENCLAW_BACKUP_MODEL:-gpt-5.3-codex}"
backup_api="${OPENCLAW_BACKUP_API:-openai-completions}"

primary_api_key="${OPENCLAW_PRIMARY_API_KEY:-}"
backup_api_key="${OPENCLAW_BACKUP_API_KEY:-}"

if [[ -z "$primary_api_key" ]]; then
  if ! primary_api_key="$(prompt_secret "Enter primary API key: ")"; then
    echo "Primary API key is required. Run interactively or set OPENCLAW_PRIMARY_API_KEY."
    exit 1
  fi
fi

if [[ -z "$primary_api_key" ]]; then
  echo "Primary API key cannot be empty."
  exit 1
fi

if [[ -z "$backup_api_key" ]]; then
  backup_input=""
  if backup_input="$(prompt_secret "Enter backup API key (press Enter to reuse primary): ")"; then
    backup_api_key="$backup_input"
  fi
fi

if [[ -z "$backup_api_key" ]]; then
  backup_api_key="$primary_api_key"
fi

config_dir="$HOME/.openclaw"
config_file="$config_dir/openclaw.json"
mkdir -p "$config_dir"

if [[ -f "$config_file" ]]; then
  cp "$config_file" "$config_file.bak.$(date +%Y%m%d-%H%M%S)"
fi

OPENCLAW_CONFIG_FILE="$config_file" \
OPENCLAW_PRIMARY_PROVIDER="$primary_provider" \
OPENCLAW_PRIMARY_BASE_URL="$primary_base_url" \
OPENCLAW_PRIMARY_MODEL="$primary_model" \
OPENCLAW_PRIMARY_API="$primary_api" \
OPENCLAW_PRIMARY_API_KEY="$primary_api_key" \
OPENCLAW_BACKUP_PROVIDER="$backup_provider" \
OPENCLAW_BACKUP_BASE_URL="$backup_base_url" \
OPENCLAW_BACKUP_MODEL="$backup_model" \
OPENCLAW_BACKUP_API="$backup_api" \
OPENCLAW_BACKUP_API_KEY="$backup_api_key" \
node -e '
const fs = require("fs");
const configFile = process.env.OPENCLAW_CONFIG_FILE;
const primaryProvider = process.env.OPENCLAW_PRIMARY_PROVIDER;
const primaryBaseUrl = process.env.OPENCLAW_PRIMARY_BASE_URL;
const primaryModel = process.env.OPENCLAW_PRIMARY_MODEL;
const primaryApi = process.env.OPENCLAW_PRIMARY_API;
const primaryApiKey = process.env.OPENCLAW_PRIMARY_API_KEY;
const backupProvider = process.env.OPENCLAW_BACKUP_PROVIDER;
const backupBaseUrl = process.env.OPENCLAW_BACKUP_BASE_URL;
const backupModel = process.env.OPENCLAW_BACKUP_MODEL;
const backupApi = process.env.OPENCLAW_BACKUP_API;
const backupApiKey = process.env.OPENCLAW_BACKUP_API_KEY;

const modelRecord = (model) => ({
  id: model,
  name: model,
  reasoning: false,
  input: ["text"],
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
  contextWindow: 200000,
  maxTokens: 8192
});

const providerRecord = ({ baseUrl, apiKey, api, model }) => ({
  baseUrl,
  apiKey,
  api,
  headers: {
    "User-Agent": "codex_cli_rs/0.98.0",
    "x-stainless-lang": "rust",
    "x-stainless-runtime": "rust",
    "x-stainless-runtime-version": "0.98.0",
    "x-stainless-package-version": "0.98.0"
  },
  models: [modelRecord(model)]
});

let config = {};
if (fs.existsSync(configFile)) {
  const raw = fs.readFileSync(configFile, "utf8").trim();
  if (raw) config = JSON.parse(raw);
}

config.models = config.models || {};
config.models.providers = config.models.providers || {};
config.models.providers[primaryProvider] = providerRecord({
  baseUrl: primaryBaseUrl,
  apiKey: primaryApiKey,
  api: primaryApi,
  model: primaryModel
});
config.models.providers[backupProvider] = providerRecord({
  baseUrl: backupBaseUrl,
  apiKey: backupApiKey,
  api: backupApi,
  model: backupModel
});

config.agents = config.agents || {};
config.agents.defaults = config.agents.defaults || {};
config.agents.defaults.model = config.agents.defaults.model || {};
config.agents.defaults.model.primary = `${primaryProvider}/${primaryModel}`;

fs.writeFileSync(configFile, JSON.stringify(config, null, 2) + "\n");
'

node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));' "$config_file"
echo "openclaw.json written: $config_file"

if ! openclaw gateway restart >/dev/null 2>&1; then
  openclaw gateway install >/dev/null 2>&1 || true
  openclaw gateway start >/dev/null 2>&1 || true
fi

health_check() {
  local result_file
  result_file="$(mktemp)"
  if openclaw agent --agent main --message "Please reply OK only" --json >"$result_file" 2>&1; then
    if grep -qi '"OK"' "$result_file" || grep -qi 'OK' "$result_file"; then
      rm -f "$result_file"
      return 0
    fi
  fi
  cat "$result_file"
  rm -f "$result_file"
  return 1
}

if health_check; then
  echo "Health check passed on ${primary_provider}/${primary_model}"
  exit 0
fi

echo "Primary failed, switching to backup provider..."
OPENCLAW_CONFIG_FILE="$config_file" \
OPENCLAW_BACKUP_PROVIDER="$backup_provider" \
OPENCLAW_BACKUP_MODEL="$backup_model" \
node -e '
const fs = require("fs");
const file = process.env.OPENCLAW_CONFIG_FILE;
const provider = process.env.OPENCLAW_BACKUP_PROVIDER;
const model = process.env.OPENCLAW_BACKUP_MODEL;
const data = JSON.parse(fs.readFileSync(file, "utf8"));
data.agents = data.agents || {};
data.agents.defaults = data.agents.defaults || {};
data.agents.defaults.model = data.agents.defaults.model || {};
data.agents.defaults.model.primary = `${provider}/${model}`;
fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n");
'

if health_check; then
  echo "Health check passed on ${backup_provider}/${backup_model}"
  exit 0
fi

echo "Both primary and backup providers failed health checks."
exit 1
