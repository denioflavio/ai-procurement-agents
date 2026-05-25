#!/usr/bin/env bash
set -euo pipefail

app_path="${1:-application/ai-procurement-agents}"
apexctl="${APEXCTL:-/Users/denioflavio/.codex/skills/apex/apexlang/tools/apexctl.mjs}"

node "$apexctl" apexlang validate --app-path "$app_path"
node "$apexctl" apexlang compiler-truth audit --app-path "$app_path" --verify-component-attributes
