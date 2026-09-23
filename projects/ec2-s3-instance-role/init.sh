#!/usr/bin/env bash
# esc bash - Project: web server on EC2 reading from S3 through an instance role.
# Drops the page to serve and a user-data skeleton under /root/ec2. Learner-run,
# after the terminal opens; makes no AWS calls. Idempotent: keeps an existing marker.
set -euo pipefail

mkdir -p /root/ec2/site
cd /root/ec2

if [ ! -s marker.txt ]; then
  echo "escbash-page-$(date +%s)-$RANDOM" > marker.txt
fi
MARKER=$(cat marker.txt)

cat > site/index.html <<EOF
<!doctype html>
<title>Orders status</title>
<h1>Orders status</h1>
<p>All systems normal.</p>
<p id="marker">$MARKER</p>
EOF

cat > user-data.sh <<'EOF'
#!/bin/bash
# Runs once, as root, when the instance first boots (cloud-init user-data).
# It must NEVER contain an access key. Credentials come from the instance role.
BUCKET="__BUCKET__"            # replaced with your bucket name before launch
log() { echo "escbash-ec2-role $*" | tee /dev/console; }   # lines you can read with get-console-output

mkdir -p /srv/site

# 1. Fetch the page from the bucket. Keep trying: until a role is attached,
#    the CLI finds no credentials and this fails.
for i in $(seq 1 80); do
  # TODO: copy s3://$BUCKET/site/index.html to /srv/site/index.html (aws s3 cp, --region us-east-1),
  #       sending errors to /tmp/s3err; on success log "fetched site/index.html using the instance role" and break
  log "attempt $i: cannot read site/index.html: $(tail -1 /tmp/s3err 2>/dev/null)"
  sleep 15
done
[ -s /srv/site/index.html ] || { log "gave up: no credentials after 20 minutes"; exit 1; }

# 2. Serve it on port 80 and fetch it from the instance itself.
cd /srv/site && nohup python3 -m http.server 80 >/var/log/site.log 2>&1 &
sleep 3
curl -s http://127.0.0.1/index.html > /tmp/served.txt

# 3. Prove the role is narrow: a write to site/ must be refused.
# TODO: try to copy /etc/hostname to s3://$BUCKET/site/overwrite.txt;
#       append "site-write: denied" (or "site-write: allowed") to /tmp/served.txt and log the outcome

# 4. Report what was served, into the bucket.
# TODO: copy /tmp/served.txt to s3://$BUCKET/reports/served.txt and log "served page uploaded to reports/served.txt"
log "done"
EOF

echo "Ready: /root/ec2/site/index.html (marker $MARKER) and /root/ec2/user-data.sh (3 TODOs)"
