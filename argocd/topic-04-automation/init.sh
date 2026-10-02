#!/usr/bin/env bash
# esc bash - Argo CD topic 04 setup: installs Argo CD v3.5.3 and connects your fork on branch topic-04-automation
set -euo pipefail
export TOPIC_BRANCH="topic-04-automation"
curl -fsSL https://raw.githubusercontent.com/Esc-Bash/project-init-scripts/main/argocd/lib.sh | bash
