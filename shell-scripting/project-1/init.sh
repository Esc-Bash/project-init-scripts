#!/usr/bin/env bash
# esc bash - Shell Scripting Project #1 setup
set -euo pipefail
mkdir -p /root/mission
cat > /root/mission/access.log <<'EOF'
10.0.0.5 GET /api/users 200
10.0.0.5 GET /api/users 200
10.0.0.5 GET /api/users 500
10.0.0.6 GET /api/users 200
10.0.0.6 POST /api/users 200
10.0.0.7 GET /api/users 200
10.0.0.8 GET /api/users 200
10.0.0.5 GET /api/orders 200
10.0.0.5 POST /api/orders 404
10.0.0.6 GET /api/orders 200
10.0.0.7 GET /api/orders 200
10.0.0.8 POST /api/orders 200
10.0.0.5 GET /health 200
10.0.0.5 GET /health 200
10.0.0.6 GET /health 503
10.0.0.7 GET /health 200
10.0.0.7 GET /health 200
10.0.0.5 POST /login 200
10.0.0.6 POST /login 502
10.0.0.8 POST /login 200
EOF
echo "Project 1 ready. Sample log: /root/mission/access.log ($(wc -l < /root/mission/access.log) lines)."
echo "Write /root/scripts/logreport.sh to summarize it."
