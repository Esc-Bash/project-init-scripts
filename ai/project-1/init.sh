#!/usr/bin/env bash
# esc bash - AI Project 1 setup: seed a folder of raw support tickets.
set -euo pipefail

mkdir -p /root/tickets

cat > /root/tickets/double-charge.txt <<'EOF'
Subject: Charged twice this month
I just checked my statement and I was billed for the Pro plan twice on the 3rd.
Please refund the extra charge. This is urgent, it overdrew my account.
EOF

cat > /root/tickets/deploy-500.txt <<'EOF'
Subject: Deploy button returns 500
Every time I click Deploy in the dashboard I get a 500 error. It started this
morning. Staging deploys fine, production does not.
EOF

cat > /root/tickets/reset-password.txt <<'EOF'
Subject: Cannot reset my password
The reset email never arrives and I already checked spam. I have been locked out
of my account since yesterday.
EOF

cat > /root/tickets/dark-mode.txt <<'EOF'
Subject: Dark mode?
Not urgent at all, just wondering whether a dark mode is on the roadmap. Would
love to have it some day.
EOF

cat > /root/tickets/api-latency.txt <<'EOF'
Subject: API latency very high
Our calls to the reports endpoint have been taking 8 to 10 seconds since the
weekend. Nothing changed on our side. Customers are noticing.
EOF

echo "Setup complete: 5 raw tickets are in /root/tickets/"
