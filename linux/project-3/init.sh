#!/usr/bin/env bash
# esc bash - Linux Project #3 setup
# Recreates a sloppy handover: a world-readable secrets file, an SSH key
# folder with loose permissions, and a deploy helper that isn't on PATH.
# The keys below are dummy placeholders, not real credentials.
# Safe to re-run (resets to the messy starting state).
set -euo pipefail

# 1) Secrets file left world-readable (should be owner-only).
mkdir -p /root/app
cat > /root/app/secrets.env <<'EOF'
API_KEY=sk-escbash-9f3c1a7b42-not-real
DB_PASSWORD=changeme-not-real
EOF
chmod 644 /root/app/secrets.env

# 2) SSH key folder with wrong permissions (dummy keys, practice only).
mkdir -p /root/.ssh
cat > /root/.ssh/id_rsa <<'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
ZXNjYmFzaC1kdW1teS1rZXktZm9yLXByYWN0aWNlLW9ubHktbm90LXJlYWw=
-----END OPENSSH PRIVATE KEY-----
EOF
echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEscBashDummyPracticeKey deploy@escbash' \
  > /root/.ssh/id_rsa.pub
chmod 777 /root/.ssh
chmod 644 /root/.ssh/id_rsa
chmod 644 /root/.ssh/id_rsa.pub

# 3) A working deploy helper that isn't runnable from anywhere yet.
mkdir -p /root/tools
cat > /root/tools/deploy-helper.sh <<'EOF'
#!/bin/bash
echo "esc bash deploy helper: rolling out the latest release..."
EOF
chmod +x /root/tools/deploy-helper.sh

echo "Project 3 ready. Current state to clean up:"
echo "- secrets file (too open):"
ls -l /root/app/secrets.env
echo "- ssh key folder (too open):"
ls -ld /root/.ssh
ls -l /root/.ssh
echo "- helper not on PATH: /root/tools/deploy-helper.sh"
