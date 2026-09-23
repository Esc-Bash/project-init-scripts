#!/usr/bin/env bash
# esc bash - Project: Kubernetes - deploy it, break it, bring it back.
# Drops /root/k8s-ops with the shop's Helm chart, values-prod.yaml, break.sh and a README.
# Creates no cluster and touches nothing outside /root/k8s-ops. Safe to re-run: it only
# writes files that are missing, so your edits are never overwritten.
# Generated from escbash-content projects/k8s-deploy-break-recover/_solution; edit there.
set -euo pipefail
OPS=${OPS_DIR:-/root/k8s-ops}
mkdir -p "$OPS/chart/templates"
cd "$OPS"
written=0
if [ ! -f chart/Chart.yaml ]; then
cat > chart/Chart.yaml <<'ESCBASH_EOF'
apiVersion: v2
name: shop
description: The esc bash shop - a static web front and a small api, for the deploy-break-recover project.
type: application
version: 0.1.0
appVersion: "1"
ESCBASH_EOF
written=$((written+1))
fi
if [ ! -f chart/values.yaml ]; then
cat > chart/values.yaml <<'ESCBASH_EOF'
# Chart defaults. The environment's real settings live in /root/k8s-ops/values-prod.yaml,
# which is what every `helm install` and `helm upgrade` in this project passes with -f.
web:
  replicas: 2
  image: nginx:1.27-alpine
  page: |
    esc bash web v1
  resources:
    requests: {cpu: 20m, memory: 16Mi}
    limits: {memory: 64Mi}
  pdb:
    minAvailable: 1
api:
  replicas: 2
  image: python:3.13-alpine
  message: esc bash api v1
  resources:
    requests: {cpu: 20m, memory: 48Mi}
    limits: {memory: 96Mi}
ESCBASH_EOF
written=$((written+1))
fi
if [ ! -f chart/templates/web.yaml ]; then
cat > chart/templates/web.yaml <<'ESCBASH_EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: web-page
  labels: {app: web}
data:
  index.html: {{ .Values.web.page | quote }}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  labels: {app: web}
spec:
  replicas: {{ .Values.web.replicas }}
  selector:
    matchLabels: {app: web}
  strategy:
    type: RollingUpdate
    rollingUpdate: {maxUnavailable: 0, maxSurge: 1}
  template:
    metadata:
      labels: {app: web}
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          nodeTaintsPolicy: Honor
          labelSelector:
            matchLabels: {app: web}
      containers:
        - name: web
          image: {{ .Values.web.image }}
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 80
          readinessProbe:
            httpGet: {path: /, port: 80}
            periodSeconds: 5
          resources:
            {{- toYaml .Values.web.resources | nindent 12 }}
          volumeMounts:
            - name: page
              mountPath: /usr/share/nginx/html
      volumes:
        - name: page
          configMap:
            name: web-page
---
apiVersion: v1
kind: Service
metadata:
  name: web
  labels: {app: web}
spec:
  selector: {app: web}
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-budget
  labels: {app: web}
spec:
  minAvailable: {{ .Values.web.pdb.minAvailable }}
  selector:
    matchLabels: {app: web}
ESCBASH_EOF
written=$((written+1))
fi
if [ ! -f chart/templates/api.yaml ]; then
cat > chart/templates/api.yaml <<'ESCBASH_EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-code
  labels: {app: api}
data:
  server.py: |
    import http.server, os, sys
    MESSAGE = os.environ.get("API_MESSAGE")
    if not MESSAGE:
        print("fatal: API_MESSAGE is not set; refusing to start", file=sys.stderr, flush=True)
        sys.exit(1)
    # warm a 24 MiB in-memory cache, the way the real service does at start
    CACHE = b"x" * (24 * 1024 * 1024)
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            body = (MESSAGE + "\n").encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        def log_message(self, *args):
            pass
    print("api listening on :8080", flush=True)
    http.server.ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  labels: {app: api}
spec:
  replicas: {{ .Values.api.replicas }}
  selector:
    matchLabels: {app: api}
  strategy:
    type: RollingUpdate
    rollingUpdate: {maxUnavailable: 0, maxSurge: 1}
  template:
    metadata:
      labels: {app: api}
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels: {app: api}
      containers:
        - name: api
          image: {{ .Values.api.image }}
          imagePullPolicy: IfNotPresent
          command: ["python3", "/app/server.py"]
          {{- with .Values.api.message }}
          env:
            - name: API_MESSAGE
              value: {{ . | quote }}
          {{- end }}
          ports:
            - containerPort: 8080
          readinessProbe:
            httpGet: {path: /, port: 8080}
            periodSeconds: 5
          resources:
            {{- toYaml .Values.api.resources | nindent 12 }}
          volumeMounts:
            - name: code
              mountPath: /app
      volumes:
        - name: code
          configMap:
            name: api-code
---
apiVersion: v1
kind: Service
metadata:
  name: api
  labels: {app: api}
spec:
  selector: {app: api}
  ports:
    - port: 80
      targetPort: 8080
ESCBASH_EOF
written=$((written+1))
fi
if [ ! -f values-prod.yaml ]; then
cat > values-prod.yaml <<'ESCBASH_EOF'
# Production settings for the shop. This file is the source of truth:
# every change to how the shop runs goes here first, then `helm upgrade -f values-prod.yaml`.
web:
  replicas: 2
  pdb:
    minAvailable: 1
api:
  replicas: 2
  message: esc bash api v1
  resources:
    requests: {cpu: 20m, memory: 48Mi}
    limits: {memory: 96Mi}
ESCBASH_EOF
written=$((written+1))
fi
if [ ! -f break.sh ]; then
cat > break.sh <<'ESCBASH_EOF'
#!/usr/bin/env bash
# esc bash - k8s-deploy-break-recover: plant one incident at a time in namespace shop.
#   bash /root/k8s-ops/break.sh 1        a release that should never have shipped
#   bash /root/k8s-ops/break.sh 2        pods that cannot find a node
#   bash /root/k8s-ops/break.sh 3        a pod that keeps dying
#   bash /root/k8s-ops/break.sh mystery  two problems at once, and a job to do
# Before planting anything it records the objects' uids and the Helm revision in
# /root/k8s-ops/.baseline/, so the checks can tell a repair from a delete-and-recreate.
# It refuses to run while the shop is unhealthy, and it plants each incident once.
set -euo pipefail
OPS=${OPS_DIR:-/root/k8s-ops}
NS=shop
BASE=$OPS/.baseline
mkdir -p "$BASE"

proxy() { kubectl get --raw "/api/v1/namespaces/$NS/services/$1:80/proxy/" 2>/dev/null; }
uid() { kubectl -n "$NS" get "$1" -o jsonpath='{.metadata.uid}' 2>/dev/null; }
revision() { helm history shop -n "$NS" -o json | python3 -c 'import sys, json; print(json.load(sys.stdin)[-1]["revision"])'; }
healthy() {
  kubectl -n "$NS" rollout status deploy/web --timeout=15s >/dev/null 2>&1 &&
    kubectl -n "$NS" rollout status deploy/api --timeout=15s >/dev/null 2>&1 &&
    proxy web | grep -q 'esc bash web v1' &&
    proxy api | grep -q 'esc bash api v1' &&
    ! kubectl get nodes -o jsonpath='{.items[*].spec.taints[*].key}' | grep -qw maintenance &&
    [ -z "$(kubectl get nodes -o jsonpath='{.items[*].spec.unschedulable}')" ]
}
record() {
  printf '{"incident":"%s","revision":%s,"deployment/web":"%s","deployment/api":"%s","pdb/web-budget":"%s","recordedAt":"%s"}\n' \
    "$1" "$(revision)" "$(uid deployment/web)" "$(uid deployment/api)" "$(uid pdb/web-budget)" \
    "$(date -u +%FT%TZ)" > "$BASE/incident-$1.json"
}
need() {
  # usage: need <this> <previous or ->
  if [ -f "$BASE/incident-$1.json" ]; then
    echo "Incident $1 was already planted ($(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["recordedAt"])' "$BASE/incident-$1.json")). Fix it, then move on." >&2
    exit 0
  fi
  if [ "$2" != "-" ] && [ ! -f "$BASE/incident-$2.json" ]; then
    echo "Plant and fix incident $2 first." >&2
    exit 1
  fi
  healthy || { echo "The shop is not healthy yet. Fix what is broken before planting the next incident." >&2; exit 1; }
}
upgrade() { helm upgrade shop "$OPS/chart" -n "$NS" -f "$OPS/values-prod.yaml" --description "$1" "${@:2}" >/dev/null; }
set_value() {
  # set_value <python regex> <replacement>: edit values-prod.yaml the way a teammate's commit would
  python3 - "$OPS/values-prod.yaml" "$1" "$2" <<'PY'
import re, sys
path, pattern, repl = sys.argv[1:4]
text = open(path).read()
new, n = re.subn(pattern, repl, text, count=1, flags=re.M)
if n != 1:
    sys.exit(f"values-prod.yaml does not look like the starter any more ({pattern!r} not found)")
open(path, "w").write(new)
PY
}

case "${1:-}" in
  1)
    need 1 -
    record 1
    upgrade "release 2026.09.24: drop the legacy API_MESSAGE setting" --set api.message=null
    echo "Incident 1 planted: a new release of the shop just went out. Something about it is wrong."
    ;;
  2)
    need 2 1
    record 2
    kubectl taint nodes kind-worker kind-worker2 maintenance=true:NoSchedule --overwrite >/dev/null
    kubectl annotate nodes kind-worker kind-worker2 --overwrite \
      escbash.io/maintenance="kernel patching window 2026-09-22 02:00-03:00 UTC, completed" >/dev/null
    set_value '^(web:\n  replicas: )2' '\g<1>4'
    upgrade "scale web to 4 for the sale"
    echo "Incident 2 planted: product asked for more web capacity. The shop did not get it."
    ;;
  3)
    need 3 2
    record 3
    set_value '^(  resources:\n    requests: \{cpu: 20m, memory: )48Mi\}\n    limits: \{memory: 96Mi\}' '\g<1>8Mi}\n    limits: {memory: 16Mi}'
    upgrade "cost review: trim api memory"
    echo "Incident 3 planted: a cost review went out as a release. Watch the api."
    ;;
  mystery)
    need mystery 3
    record mystery
    set_value '^(  pdb:\n    minAvailable: )1' '\g<1>4'
    upgrade "platform: never lose a web pod during the sale"
    kubectl -n "$NS" patch configmap web-page --type=json \
      -p '[{"op":"move","from":"/data/index.html","path":"/data/index.html.bak"}]' >/dev/null
    kubectl -n "$NS" rollout restart deploy/web >/dev/null
    cat > "$OPS/MISSION.md" <<'MD'
# Tonight's maintenance

1. Users report that the shop's web page is broken. Make it serve again.
2. kind-worker2 is being patched tonight. Drain it:

       kubectl drain kind-worker2 --ignore-daemonsets --delete-emptydir-data 2>&1 | tee /root/k8s-ops/drain.log

   The shop must keep serving from kind-worker while kind-worker2 is out.
3. When the drain has finished, bring kind-worker2 back with kubectl uncordon.

Every change to how the shop runs goes through values-prod.yaml and helm upgrade.
MD
    echo "Mystery planted. Read /root/k8s-ops/MISSION.md."
    ;;
  *) echo "usage: break.sh 1|2|3|mystery" >&2; exit 2 ;;
esac
ESCBASH_EOF
written=$((written+1))
fi
if [ ! -f README.md ]; then
cat > README.md <<'ESCBASH_EOF'
# k8s-ops: the shop, and tonight's incidents

chart/             the shop's Helm chart (web + api)
values-prod.yaml   the environment's settings: change things here, then helm upgrade
break.sh           plants one incident at a time: 1, 2, 3, then mystery

Install:  helm install shop ./chart -n shop --create-namespace -f values-prod.yaml --wait
Cluster:  already running (kind: kind-control-plane, kind-worker, kind-worker2) - kubectl get nodes
ESCBASH_EOF
written=$((written+1))
fi
chmod +x break.sh
echo "Ready: /root/k8s-ops has the shop chart, values-prod.yaml and break.sh ($written files written, existing files kept)."
