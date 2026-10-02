#!/usr/bin/env bash
# esc bash - Argo CD topic setup (shared library)
#
# Run through a topic wrapper, never directly:
#   export GH_TOKEN=ghp_...
#   curl -fsSL https://raw.githubusercontent.com/Esc-Bash/project-init-scripts/main/argocd/topic-05-sources/init.sh | bash
#
# The wrapper exports TOPIC_BRANCH and pipes this file to bash. What it does:
#   1. saves the GitHub token to /root/.github/token and checks it
#   2. waits for the kind node
#   3. installs Argo CD v3.5.3 and lights up ESCBASH letter by letter as pods come up
#   4. installs the argocd command line tool
#   5. exposes the server on a NodePort for the CLI and starts the port-forward
#      on 8080 for the lab browser as a background service (unit argocd-ui)
#   6. logs the command line tool in as admin through the NodePort
#   7. configures git, forks argoproj/argocd-example-apps, clones it, pushes TOPIC_BRANCH
#   8. registers the fork with Argo CD
# Safe to run again: every step checks before it acts. Output goes to the
# screen as short status lines; every command's output goes to /root/argocd-init.log.
set -euo pipefail

ARGOCD_VERSION="v3.5.3"
LOG="${ARGOCD_INIT_LOG:-/root/argocd-init.log}"
TOKEN_FILE="/root/.github/token"
CLONE_DIR="/root/argocd-example-apps"
UPSTREAM="argoproj/argocd-example-apps"
INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
CLI_URL="https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
DRY_RUN="${DRY_RUN:-0}"

if [[ -z "${TOPIC_BRANCH:-}" ]]; then
  echo "TOPIC_BRANCH is not set. Run the init.sh for your topic, not lib.sh directly." >&2
  exit 1
fi

# ---------------------------------------------------------------- output
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  TTY=1
  C_OK=$'\e[32m'; C_WARN=$'\e[33m'; C_ERR=$'\e[31m'; C_DIM=$'\e[2m'; C_OFF=$'\e[0m'
else
  TTY=0
  C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""; C_OFF=""
fi

STEP="starting"
START_TS=$(date +%s)

ok()   { printf '%s✔%s %s\n' "$C_OK" "$C_OFF" "$*"; }
info() { printf '%s…%s %s\n' "$C_DIM" "$C_OFF" "$*"; }
die()  {
  printf '%s✖%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2
  if [[ -s "$LOG" ]]; then
    printf '  last lines of the log:\n' >&2
    tail -n 6 "$LOG" | sed 's/^/    /' >&2
  fi
  printf '  full output: %s\n' "$LOG" >&2
  exit 1
}
trap 'die "step failed: ${STEP}"' ERR

log() { printf '\n## %s  (%s)\n' "$*" "$(date +%H:%M:%S)" >>"$LOG"; }
# run: log the command line, send all output to the log, keep the exit code
run() { log "$*"; "$@" >>"$LOG" 2>&1; }

elapsed() {
  local s=$(( $(date +%s) - START_TS ))
  if (( s >= 60 )); then printf '%dm%02ds' $((s/60)) $((s%60)); else printf '%ds' "$s"; fi
}

# ---------------------------------------------------------------- resource tree
# Fixed order, so lines never jump while the tree grows.
WORKLOADS=(
  "Deployment argocd-server"
  "Deployment argocd-repo-server"
  "StatefulSet argocd-application-controller"
  "Deployment argocd-redis"
  "Deployment argocd-applicationset-controller"
  "Deployment argocd-dex-server"
  "Deployment argocd-notifications-controller"
)
NOTES=(
  "repo-server turns Helm charts and Kustomize folders into plain YAML"
  "application-controller is the only pod that changes the cluster"
  "server is the front door for the UI and the argocd command line tool"
  "redis is a cache, so the other pods do not repeat work"
  "dex does single sign-on. This skill uses local accounts, so it stays idle"
  "notifications-controller sends a message when an app changes state"
  "Argo CD checks Git every three minutes. A refresh makes it check now"
)
TREE_LINES=0

# cluster_json: one JSON document with the workloads and pods of namespace argocd.
cluster_json() {
  if [[ "$DRY_RUN" == "1" ]]; then fake_json; return; fi
  kubectl get deploy,sts,pods -n argocd -o json 2>/dev/null || echo '{"items":[]}'
}

# tree_rows: TSV rows, one per workload then its pods.
#   W <kind> <name> <exists 0|1> <ready 0|1>
#   P <podname> <ready 0|1> <status text>
tree_rows() {
  local json="$1"
  local w kind name
  for w in "${WORKLOADS[@]}"; do
    kind="${w%% *}"; name="${w#* }"
    printf '%s' "$json" | jq -r --arg kind "$kind" --arg name "$name" '
      ([ .items[] | select(.kind == $kind and .metadata.name == $name) ] | .[0]) as $o
      | if $o == null then "W\t\($kind)\t\($name)\t0\t0"
        else
          "W\t\($kind)\t\($name)\t1\t\(if (($o.status.readyReplicas // 0) >= 1 and (($o.status.unavailableReplicas // 0) == 0)) then 1 else 0 end)",
          ( .items[]
            | select(.kind == "Pod" and (.metadata.labels["app.kubernetes.io/name"] // "") == $name and .metadata.deletionTimestamp == null)
            | (.status.containerStatuses // []) as $cs
            | "P\t\(.metadata.name)\t\(if ($cs | length) > 0 and ([$cs[].ready] | all) then 1 else 0 end)\t\(
                (($cs | map(.state.waiting.reason // empty) | .[0]) // .status.phase // "Pending"))"
          )
        end' 2>/dev/null || printf 'W\t%s\t%s\t0\t0\n' "$kind" "$name"
  done
}

# Block letters, one per workload, in the order of WORKLOADS: E S C B A S H.
# Solid green once the workload is healthy, hollow yellow while it starts,
# hollow dim until its object exists. 5 rows, 5 columns per letter.
# shellcheck disable=SC2034  # read through a nameref in glyph_row
GLYPH_E=("█████" "█    " "████ " "█    " "█████")
# shellcheck disable=SC2034
GLYPH_S=("█████" "█    " "█████" "    █" "█████")
# shellcheck disable=SC2034
GLYPH_C=("█████" "█    " "█    " "█    " "█████")
# shellcheck disable=SC2034
GLYPH_B=("████ " "█   █" "████ " "█   █" "████ ")
# shellcheck disable=SC2034
GLYPH_A=(" ███ " "█   █" "█████" "█   █" "█   █")
# shellcheck disable=SC2034
GLYPH_H=("█   █" "█   █" "█████" "█   █" "█   █")
LETTERS=(E S C B A S H)
LABELS=("srvr" "repo" "ctrl" "redis" "apset" "dex" "notif")
COLS="${ARGOCD_COLS:-$(tput cols 2>/dev/null || echo 80)}"
[[ "$COLS" -ge 48 ]] || TTY=0   # too narrow to redraw safely: plain lines instead

# glyph_row LETTER ROW STATE -> one 5-column slice (0 missing, 1 starting, 2 healthy)
glyph_row() {
  local -n g="GLYPH_$1"
  local row="${g[$2]}"
  case "$3" in
    2) printf '%s%s%s' "$C_OK" "$row" "$C_OFF" ;;
    1) printf '%s%s%s' "$C_WARN" "${row//█/░}" "$C_OFF" ;;
    *) printf '%s%s%s' "$C_DIM" "${row//█/░}" "$C_OFF" ;;
  esac
}

# fit TEXT -> TEXT cut to the terminal width, so a line never wraps
fit() { local t="$1"; printf '%s' "${t:0:$((COLS-2))}"; }

# render_tree: draw the ESCBASH banner in place from the live cluster state.
render_tree() {
  local json rows line t a b c d
  local -a state=(0 0 0 0 0 0 0) lines=()
  local total=0 widx=-1 busy=""
  json="$(cluster_json)"
  rows="$(tree_rows "$json")"

  while IFS=$'\t' read -r t a b c d; do
    if [[ "$t" == "W" ]]; then
      widx=$((widx+1))
      if [[ "$d" == "1" ]]; then state[$widx]=2; total=$((total+1))
      elif [[ "$c" == "1" ]]; then state[$widx]=1; fi
    elif [[ "$t" == "P" && "$b" != "1" && -z "$busy" ]]; then
      busy="${a%-*}"; busy="${busy%-*} (${c})"   # pod name without the hash suffixes
    fi
  done <<<"$rows"

  local r i
  for r in 0 1 2 3 4; do
    line="  "
    for i in 0 1 2 3 4 5 6; do line+="$(glyph_row "${LETTERS[$i]}" "$r" "${state[$i]}") "; done
    lines+=("$line")
  done
  line="  "
  for i in 0 1 2 3 4 5 6; do line+="$(printf '%-6s' "${LABELS[$i]}")"; done
  lines+=("${C_DIM}${line}${C_OFF}")
  lines+=("")
  local pct=$(( total * 100 / ${#WORKLOADS[@]} ))
  lines+=("$(fit "  ${total}/${#WORKLOADS[@]} components healthy . ${pct}% . $(elapsed)")")
  if [[ -n "$busy" ]]; then lines+=("$(fit "  starting: ${busy}")"); else lines+=("$(fit "  waiting for the cluster")"); fi
  local note_idx=$(( ( $(date +%s) - START_TS ) / 8 % ${#NOTES[@]} ))
  lines+=("${C_DIM}$(fit "  ${NOTES[$note_idx]}")${C_OFF}")

  if [[ "$TTY" == "1" && "$TREE_LINES" -gt 0 ]]; then
    printf '\e[%dA' "$TREE_LINES"
  fi
  for line in "${lines[@]}"; do
    if [[ "$TTY" == "1" ]]; then printf '\e[K%s\n' "$line"; else printf '%s\n' "$line"; fi
  done
  TREE_LINES=${#lines[@]}
  READY_COUNT=$total
}

# fake_json: a pretend cluster for DRY_RUN=1, more pods ready on every call.
fake_json() {
  local tick=$(( ( $(date +%s) - START_TS ) / 2 + 1 ))
  local n=$(( tick > 8 ? 8 : tick ))
  jq -n --argjson n "$n" --argjson ws "$(printf '%s\n' "${WORKLOADS[@]}" | jq -R 'split(" ") | {kind: .[0], name: .[1]}' | jq -s .)" '
    {items: ([range(0; $ws|length) as $i | $ws[$i] |
      (if $i < $n then
        [{kind: .kind, metadata: {name: .name}, status: {readyReplicas: (if $i < ($n-1) then 1 else 0 end), unavailableReplicas: (if $i < ($n-1) then 0 else 1 end)}},
         {kind: "Pod", metadata: {name: (.name + "-7d9f-k2xq"), labels: {"app.kubernetes.io/name": .name}},
          status: {phase: (if $i < ($n-1) then "Running" else "Pending" end),
                   containerStatuses: [{ready: ($i < ($n-1)), state: (if $i < ($n-1) then {running: {}} else {waiting: {reason: "ContainerCreating"}} end)}]}}]
       else [] end)] | add)}'
}

# ---------------------------------------------------------------- steps
printf '\n%sArgo CD setup for %s%s\n\n' "$C_DIM" "$TOPIC_BRANCH" "$C_OFF"
: >"$LOG"
log "Argo CD setup for $TOPIC_BRANCH"

# 1. token -------------------------------------------------------------------
STEP="GitHub token"
[[ "$DRY_RUN" == "1" ]] && GH_TOKEN="${GH_TOKEN:-dry-run}"
if [[ -z "${GH_TOKEN:-}" && -s "$TOKEN_FILE" ]]; then
  GH_TOKEN="$(cat "$TOKEN_FILE")"
fi
if [[ -z "${GH_TOKEN:-}" || "${GH_TOKEN}" == ghp_YOUR_TOKEN_HERE ]]; then
  die "Set your GitHub token first, then run the script again:  export GH_TOKEN=ghp_..."
fi
if [[ "$DRY_RUN" == "1" ]]; then
  LOGIN="dry-run"
else
  LOGIN="$(curl -fsS -H "Authorization: token ${GH_TOKEN}" https://api.github.com/user 2>>"$LOG" | jq -r '.login // empty')" || true
  [[ -n "$LOGIN" ]] || die "GitHub rejected the token. Create a classic token with the repo scope and set GH_TOKEN again."
  mkdir -p "$(dirname "$TOKEN_FILE")"
  printf '%s\n' "$GH_TOKEN" >"$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
fi
ok "GitHub token accepted for ${LOGIN}"

# 2. cluster -----------------------------------------------------------------
STEP="cluster node"
if [[ "$DRY_RUN" != "1" ]]; then
  for _ in $(seq 1 50); do
    kubectl wait --for=condition=Ready nodes --all --timeout=10s >>"$LOG" 2>&1 && break
    sleep 5
  done
  kubectl get nodes >>"$LOG" 2>&1 || die "the kind cluster is not reachable"
fi
ok "cluster node ready"

# 3. Argo CD -----------------------------------------------------------------
STEP="install Argo CD"
if [[ "$DRY_RUN" != "1" ]]; then
  kubectl get namespace argocd >>"$LOG" 2>&1 || run kubectl create namespace argocd
  run kubectl apply --server-side -n argocd -f "$INSTALL_URL"
  if [[ "$(kubectl -n argocd get cm argocd-cmd-params-cm -o jsonpath='{.data.server\.insecure}' 2>>"$LOG")" != "true" ]]; then
    run kubectl -n argocd patch cm argocd-cmd-params-cm --type merge -p '{"data":{"server.insecure":"true"}}'
    run kubectl -n argocd rollout restart deploy argocd-server
  fi
fi
info "installing Argo CD ${ARGOCD_VERSION}. Each letter is one Argo CD component, it lights up when that component is healthy"
printf '\n'
READY_COUNT=0
DEADLINE=$(( $(date +%s) + 600 ))
LAST_PLAIN=-1
while :; do
  if [[ "$TTY" == "1" ]]; then
    render_tree
  else
    render_tree >/tmp/argocd-banner.$$ 2>&1
    if (( READY_COUNT != LAST_PLAIN )); then cat /tmp/argocd-banner.$$; LAST_PLAIN=$READY_COUNT; fi
    rm -f /tmp/argocd-banner.$$
  fi
  (( READY_COUNT >= ${#WORKLOADS[@]} )) && break
  if (( $(date +%s) > DEADLINE )); then
    printf '\n'
    die "Argo CD pods did not become ready within 10 minutes. Check: kubectl get pods -n argocd"
  fi
  sleep 2
done
printf '\n'
NODE_IP=""
if [[ "$DRY_RUN" != "1" ]]; then
  run kubectl -n argocd rollout status deploy argocd-server --timeout=120s
  run kubectl -n argocd rollout status sts argocd-application-controller --timeout=120s
  # The CLI talks to the server through a NodePort on the kind node. Unlike a
  # port-forward, nothing has to stay running for it to work.
  run kubectl -n argocd patch svc argocd-server --type merge -p '{"spec":{"type":"NodePort","ports":[{"name":"http","port":80,"targetPort":8080,"nodePort":30080},{"name":"https","port":443,"targetPort":8080,"nodePort":30443}]}}'
  NODE_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>>"$LOG")"
  [[ -n "$NODE_IP" ]] || die "could not read the kind node address"
  SERVER_MODE=""
  for _ in $(seq 1 45); do
    if curl -s --max-time 2 "http://${NODE_IP}:30080/api/version" 2>/dev/null | grep -q Version; then SERVER_MODE="http"; break; fi
    if curl -sk --max-time 2 "https://${NODE_IP}:30080/api/version" 2>/dev/null | grep -q Version; then SERVER_MODE="tls"; break; fi
    sleep 2
  done
  if [[ "$SERVER_MODE" == "tls" ]]; then
    log "server still answers TLS, restarting argocd-server so it reads server.insecure"
    run kubectl -n argocd rollout restart deploy argocd-server
    run kubectl -n argocd rollout status deploy argocd-server --timeout=180s
    for _ in $(seq 1 45); do
      if curl -s --max-time 2 "http://${NODE_IP}:30080/api/version" 2>/dev/null | grep -q Version; then SERVER_MODE="http"; break; fi
      sleep 2
    done
  fi
  [[ "$SERVER_MODE" == "http" ]] || die "argocd-server does not answer plain HTTP on ${NODE_IP}:30080. Check: kubectl -n argocd logs deploy/argocd-server"
fi
ok "Argo CD ${ARGOCD_VERSION} running, all ${#WORKLOADS[@]} workloads healthy ($(elapsed))"

# 4. CLI ---------------------------------------------------------------------
STEP="argocd command line tool"
if [[ "$DRY_RUN" != "1" ]]; then
  if ! argocd version --client 2>/dev/null | grep -q "$ARGOCD_VERSION"; then
    run curl -fsSL -o /usr/local/bin/argocd "$CLI_URL"
    chmod +x /usr/local/bin/argocd
  fi
fi
ok "argocd command line tool ${ARGOCD_VERSION}"

# 5. port-forward ------------------------------------------------------------
STEP="port-forward on 8080"
if [[ "$DRY_RUN" != "1" ]]; then
  # The lab browser reaches the UI through port 8080 on this machine. A
  # port-forward dies when its pod goes away, so it runs in a restart loop.
  if ! systemctl is-active --quiet argocd-ui; then
    run systemd-run --collect --unit=argocd-ui --property=Restart=always --property=RestartSec=2 \
      --setenv=KUBECONFIG=/root/.kube/config \
      kubectl -n argocd port-forward svc/argocd-server --address 0.0.0.0 8080:80
  fi
  PF_OK=0
  for _ in $(seq 1 45); do
    if curl -s --max-time 2 http://127.0.0.1:8080/api/version 2>/dev/null | grep -q Version; then PF_OK=1; break; fi
    sleep 2
  done
  (( PF_OK == 1 )) || die "port 8080 does not answer. Check: systemctl status argocd-ui"
fi
ok "port-forward on 8080 for the lab browser (background service argocd-ui)"

# 6. login -------------------------------------------------------------------
STEP="argocd login"
if [[ "$DRY_RUN" != "1" ]]; then
  LOGGED_IN=0
  ADMIN_PW=""
  for _ in $(seq 1 20); do
    ADMIN_PW="$(argocd admin initial-password -n argocd 2>>"$LOG" | head -1 | tr -d '\r')"
    [[ -n "$ADMIN_PW" ]] && break
    sleep 3
  done
  [[ -n "$ADMIN_PW" ]] || die "the initial admin password is not available yet. Check: kubectl -n argocd get secret argocd-initial-admin-secret"
  ARGOCD_ADDR="${NODE_IP}:30080"
  for _ in $(seq 1 15); do
    for flags in "--plaintext" "--plaintext --grpc-web"; do
      log "argocd login ${ARGOCD_ADDR} $flags"
      # shellcheck disable=SC2086
      if argocd login "$ARGOCD_ADDR" $flags --username admin --password "$ADMIN_PW" >>"$LOG" 2>&1; then
        LOGGED_IN=1; break 2
      fi
    done
    sleep 3
  done
  (( LOGGED_IN == 1 )) || die "could not log in to Argo CD as admin at ${ARGOCD_ADDR}"
  # make later shells aware of the server even without a saved login context
  grep -q 'ARGOCD_SERVER=' /root/.bashrc 2>/dev/null || printf '\nexport ARGOCD_SERVER=%s\nexport ARGOCD_OPTS="--plaintext"\n' "$ARGOCD_ADDR" >>/root/.bashrc
fi
ok "logged in as admin (CLI talks to ${NODE_IP:-the kind node}:30080)"

# 7. git ---------------------------------------------------------------------
STEP="git and GitHub fork"
FORK_URL="https://github.com/${LOGIN}/argocd-example-apps"
if [[ "$DRY_RUN" != "1" ]]; then
  git config --global credential.helper store
  printf 'https://%s:%s@github.com\n' "$LOGIN" "$GH_TOKEN" >/root/.git-credentials
  chmod 600 /root/.git-credentials
  git config --global user.name "$LOGIN"
  git config --global user.email "${LOGIN}@users.noreply.github.com"
  curl -s -X POST -H "Authorization: token ${GH_TOKEN}" "https://api.github.com/repos/${UPSTREAM}/forks" >>"$LOG" 2>&1 || true
  FORK_OK=0
  for _ in $(seq 1 30); do
    if [[ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: token ${GH_TOKEN}" "https://api.github.com/repos/${LOGIN}/argocd-example-apps")" == "200" ]]; then
      FORK_OK=1; break
    fi
    sleep 2
  done
  (( FORK_OK == 1 )) || die "the fork ${LOGIN}/argocd-example-apps did not appear on GitHub"
  if [[ ! -d "${CLONE_DIR}/.git" ]]; then
    run git clone "$FORK_URL" "$CLONE_DIR"
  fi
  cd "$CLONE_DIR"
  run git fetch origin
  if git ls-remote --exit-code --heads origin "$TOPIC_BRANCH" >>"$LOG" 2>&1; then
    run git checkout -B "$TOPIC_BRANCH" "origin/${TOPIC_BRANCH}"
  else
    run git checkout -B "$TOPIC_BRANCH" origin/master
  fi
  run git push -u origin "$TOPIC_BRANCH"
fi
ok "fork ready, branch ${TOPIC_BRANCH} pushed, clone at ${CLONE_DIR}"

# 8. register the fork -------------------------------------------------------
STEP="register the fork with Argo CD"
if [[ "$DRY_RUN" != "1" ]]; then
  run argocd repo add "$FORK_URL" --upsert
fi
ok "fork registered with Argo CD"

# ---------------------------------------------------------------- summary
printf '\n%sEvery letter above is one Argo CD component. All seven are healthy.%s\n' "$C_DIM" "$C_OFF"
printf 'UI:      Browser tab at %s%s:8080%s\n' "$C_OK" "$(hostname)" "$C_OFF"
printf 'Login:   admin, password from:  argocd admin initial-password -n argocd\n'
printf 'Branch:  %s\nClone:   %s\nLog:     %s\n\n' "$TOPIC_BRANCH" "$CLONE_DIR" "$LOG"
printf '%sReady. Press Submit.%s\n' "$C_OK" "$C_OFF"
