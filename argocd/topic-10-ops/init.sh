#!/usr/bin/env bash
# esc bash - Argo CD topic 10 setup: installs Argo CD v3.5.3 and connects your fork on branch topic-10-ops
set -euo pipefail
export TOPIC_BRANCH="topic-10-ops"
curl -fsSL https://raw.githubusercontent.com/Esc-Bash/project-init-scripts/main/argocd/lib.sh | bash
