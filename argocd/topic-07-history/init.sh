#!/usr/bin/env bash
# esc bash - Argo CD topic 07 setup: installs Argo CD v3.5.3 and connects your fork on branch topic-07-history
set -euo pipefail
export TOPIC_BRANCH="topic-07-history"
curl -fsSL https://raw.githubusercontent.com/Esc-Bash/project-init-scripts/main/argocd/lib.sh | bash
