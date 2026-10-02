#!/usr/bin/env bash
# esc bash - Argo CD topic 08 setup: installs Argo CD v3.5.3 and connects your fork on branch topic-08-projects
set -euo pipefail
export TOPIC_BRANCH="topic-08-projects"
curl -fsSL https://raw.githubusercontent.com/Esc-Bash/project-init-scripts/main/argocd/lib.sh | bash
