#!/usr/bin/env bash
# esc bash - Observability Fundamentals topic 07 setup: rebuilds the state at the end of topic 6 on this machine
set -euo pipefail
export OBS_TOPIC=07
curl -fsSL "${INIT_RAW:-https://raw.githubusercontent.com/Esc-Bash/project-init-scripts/main}/observability/lib.sh" | bash
