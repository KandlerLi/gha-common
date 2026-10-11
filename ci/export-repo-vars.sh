#!/usr/bin/env bash
# Usage and why ALL_VARS_JSON comes from the caller: see README, "ci/export-repo-vars.sh".

set -euo pipefail

for name in "$@"; do
  value="$(echo "${ALL_VARS_JSON}" | jq -r --arg k "${name}" '.[$k] // empty')"
  if [ -z "${value}" ]; then
    echo "::error::Missing repository variable ${name}"
    exit 1
  fi
  lower="$(echo "${name}" | tr '[:upper:]' '[:lower:]')"
  echo "TF_VAR_${lower}=${value}" >> "${GITHUB_ENV}"
done
