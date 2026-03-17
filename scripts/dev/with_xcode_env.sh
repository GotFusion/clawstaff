#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
FULL_XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
COMMAND_LINE_TOOLS_DIR="/Library/Developer/CommandLineTools"

if [[ -z "${DEVELOPER_DIR:-}" ]] && [[ -d "${FULL_XCODE_DEVELOPER_DIR}" ]]; then
  ACTIVE_DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
  if [[ "${ACTIVE_DEVELOPER_DIR}" == "${COMMAND_LINE_TOOLS_DIR}" ]]; then
    export DEVELOPER_DIR="${FULL_XCODE_DEVELOPER_DIR}"
  fi
fi

CACHE_KEY="$(printf '%s' "${REPO_ROOT}" | shasum -a 256 | awk '{print substr($1, 1, 12)}')"
SWIFT_MODULE_CACHE_DIR="${REPO_ROOT}/.build/module-cache-${CACHE_KEY}"
CLANG_MODULE_CACHE_DIR="${REPO_ROOT}/.build/clang-module-cache-${CACHE_KEY}"

mkdir -p "${SWIFT_MODULE_CACHE_DIR}" "${CLANG_MODULE_CACHE_DIR}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFT_MODULE_CACHE_DIR}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_DIR}"

exec "$@"
