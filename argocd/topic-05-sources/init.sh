#!/usr/bin/env bash
# esc bash - Argo CD topic 05 setup: installs Argo CD v3.5.3 and connects your fork on branch topic-05-sources
set -euo pipefail
export TOPIC_BRANCH="topic-05-sources"
curl -fsSL https://raw.githubusercontent.com/Esc-Bash/project-init-scripts/main/argocd/lib.sh | bash
