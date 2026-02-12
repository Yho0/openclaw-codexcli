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

provider_name="${OPENCLAW_PROVIDER_NAME:-Aistock}"
base_url="${OPENCLAW_AISTOCK_BASE_URL:-https://www.aistock.tech/v1}"
model_name="${OPENCLAW_AISTOCK_MODEL:-gpt-5.3-codex}"
api_mode="${OPENCLAW_AISTOCK_API_MODE:-openai-responses}"
api_key="${OPENCLAW_AISTOCK_API_KEY:-${OPENCLAW_PRIMARY_API_KEY:-}}"

if [[ -z "$api_key" ]]; then
  if ! api_key="$(prompt_secret "Enter Aistock API key: ")"; then
    echo "Aistock API key is required. Run interactively or set OPENCLAW_AISTOCK_API_KEY."
    exit 1
  fi
fi

if [[ -z "$api_key" ]]; then
  echo "Aistock API key cannot be empty."
  exit 1
fi

config_dir="$HOME/.openclaw"
config_file="$config_dir/openclaw.json"
mkdir -p "$config_dir"

if [[ -f "$config_file" ]]; then
  cp "$config_file" "$config_file.bak.$(date +%Y%m%d-%H%M%S)"
fi

OPENCLAW_CONFIG_FILE="$config_file" \
OPENCLAW_PROVIDER_NAME="$provider_name" \
OPENCLAW_AISTOCK_BASE_URL="$base_url" \
OPENCLAW_AISTOCK_MODEL="$model_name" \
OPENCLAW_AISTOCK_API_MODE="$api_mode" \
OPENCLAW_AISTOCK_API_KEY="$api_key" \
node -e '
const fs = require("fs");
const configFile = process.env.OPENCLAW_CONFIG_FILE;
const providerName = process.env.OPENCLAW_PROVIDER_NAME;
const baseUrl = process.env.OPENCLAW_AISTOCK_BASE_URL;
const modelName = process.env.OPENCLAW_AISTOCK_MODEL;
const apiMode = process.env.OPENCLAW_AISTOCK_API_MODE;
const apiKey = process.env.OPENCLAW_AISTOCK_API_KEY;

let config = {};
if (fs.existsSync(configFile)) {
  const raw = fs.readFileSync(configFile, "utf8").trim();
  if (raw) config = JSON.parse(raw);
}

config.models = config.models || {};
config.models.providers = config.models.providers || {};
config.models.providers[providerName] = {
  baseUrl,
  apiKey,
  api: apiMode,
  headers: {
    "User-Agent": "codex_cli_rs/0.98.0",
    "x-stainless-lang": "rust",
    "x-stainless-runtime": "rust",
    "x-stainless-runtime-version": "0.98.0",
    "x-stainless-package-version": "0.98.0"
  },
  models: [
    {
      id: modelName,
      name: modelName
    }
  ]
};

config.agents = config.agents || {};
config.agents.defaults = config.agents.defaults || {};
config.agents.defaults.model = config.agents.defaults.model || {};
config.agents.defaults.model.primary = `${providerName}/${modelName}`;

fs.writeFileSync(configFile, JSON.stringify(config, null, 2) + "\n");
'

node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));' "$config_file"
echo "openclaw.json written: $config_file"

if ! openclaw gateway restart >/dev/null 2>&1; then
  openclaw gateway install >/dev/null 2>&1 || true
  openclaw gateway start >/dev/null 2>&1 || true
fi

result_file="$(mktemp)"
if openclaw agent --agent main --message "Please reply OK only" --json >"$result_file" 2>&1; then
  if grep -qi '"OK"' "$result_file" || grep -qi 'OK' "$result_file"; then
    rm -f "$result_file"
    echo "Health check passed on ${provider_name}/${model_name}"
    exit 0
  fi
fi
cat "$result_file"
rm -f "$result_file"
echo "Health check failed on ${provider_name}/${model_name}."
exit 1
