#!/usr/bin/env bash
# esc bash - Project: versioned S3 document store with an audit trail. Creates the working folders only;
# every document is written by the learner during the project.
set -euo pipefail
mkdir -p /root/audit /root/docs
echo "Ready: write your documents under /root/docs, your evidence under /root/audit"
