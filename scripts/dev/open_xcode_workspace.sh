#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PACKAGE_PATH="${REPO_ROOT}/apps/macos/Package.swift"

if [[ ! -f "${PACKAGE_PATH}" ]]; then
  echo "Swift package not found: ${PACKAGE_PATH}" >&2
  exit 1
fi

open -a Xcode "${PACKAGE_PATH}"
