#!/usr/bin/env bash
# esc bash - Observability Fundamentals topic setup (shared library)
#
# Run through a topic wrapper, never directly:
#   curl -fsSL https://raw.githubusercontent.com/Esc-Bash/project-init-scripts/main/observability/topic-08-prometheus/init.sh | bash
#
# The wrapper exports OBS_TOPIC (two digits, for example 08) and pipes this file to bash.
# What it does:
#   1. waits for the kind node
#   2. clones the lab repository to /root/observability-shop (kept if it is already there)
#   2a. unpacks the setup image of this topic (OBS_SETUP_IMAGE:topic-NN) to /root/.observability-init/setup:
#       stages/, setup-state.sh and files/ (the files the earlier topics produced). Each topic's
#       image holds only what the earlier topics need.
#   2b. from topic 08: setup-state.sh <topic-1> sets up namespace monitoring
#   3. runs the stage files stages/NN.sh of the setup image for every NN below OBS_TOPIC, in order.
#      Stage NN rebuilds the state at the END of topic NN. A missing stage file is skipped.
#   4. runs stages/prep-<OBS_TOPIC>.sh if it exists (extra setup for this topic only,
#      for example a fault the learner has to find)
#   5. restarts every port-forward unit a stage started that is not running
# Safe to run again: a stage that finished is not run again (markers in /root/.observability-init/),
# and every helper checks before it acts. Output goes to the screen as short status lines;
# every command's output goes to /root/observability-init.log.
#
# Environment:
#   OBS_TOPIC       required, two digits
#   OBS_SHOP_REPO   repository to clone      (default https://github.com/Esc-Bash/observability-lab.git)
#   OBS_SHOP_REF    branch, tag or commit    (default main)
#   OBS_SETUP_IMAGE setup image without tag  (default ghcr.io/esc-bash/observability-setup);
#                   a local image with that name and tag is used without a pull
#   INIT_RAW        where the topic wrappers fetch lib.sh from
#                   (default https://raw.githubusercontent.com/Esc-Bash/project-init-scripts/main)
#
# Helpers for stage files (stages are sourced into this shell, run in $SHOP_DIR, with set -e):
#   step "text"                       start a step: sets the error message, logs the title
#   ok "text" / info "text"           short status line on the screen
#   run cmd...                        run a command, all output to the log
#   apply_manifests path...           kubectl apply -f each path (relative to $SHOP_DIR)
#   wait_rollout ns deploy...         wait until each Deployment has rolled out (OBS_ROLLOUT_TIMEOUT, 300s)
#   start_pf unit ns svc port [addr]  port-forward svc/<svc> as transient unit <unit> (addr 0.0.0.0)
#   wait_http url [tries]             wait until url answers with a 2xx/3xx status
#   build_image tag dir               docker build -t tag dir and kind load the image
#                                     (dir relative to $SHOP_DIR, or absolute)
#   use_topic_files NN svc               copy $OBS_FILES/topic-NN/<svc>/ into app/<svc>/ (once per machine)
#   deploy_topic_files NN svc            use_topic_files + build shop-<svc>:dev from $OBS_FILES/topic-NN/<svc>,
#                                     set it on deploy/<svc> in namespace shop, restart, wait
#   ensure_pfs                        start again any recorded port-forward unit that is not running
#   send_checkouts N                  bash scripts/shop-load.sh N (after ensure_pfs)
set -Eeuo pipefail

main() {
  : "${OBS_TOPIC:?OBS_TOPIC is not set. Run the init.sh for your topic, not lib.sh directly.}"
  OBS_TOPIC="$(printf '%02d' "$((10#$OBS_TOPIC))")"
  OBS_SHOP_REPO="${OBS_SHOP_REPO:-https://github.com/Esc-Bash/observability-lab.git}"
  OBS_SETUP_IMAGE="${OBS_SETUP_IMAGE:-ghcr.io/esc-bash/observability-setup}"
  OBS_SHOP_REF="${OBS_SHOP_REF:-main}"
  INIT_RAW="${INIT_RAW:-https://raw.githubusercontent.com/Esc-Bash/project-init-scripts/main}"
  CANONICAL_REPO="https://github.com/Esc-Bash/observability-lab.git"
  SHOP_DIR="/root/observability-shop"
  LOG="${OBS_INIT_LOG:-/root/observability-init.log}"
  STATE_DIR="/root/.observability-init"
  SETUP_DIR="$STATE_DIR/setup"
  OBS_FILES="$SETUP_DIR/files"
  OBS_ROLLOUT_TIMEOUT="${OBS_ROLLOUT_TIMEOUT:-300}"
  export KUBECONFIG="${KUBECONFIG:-/root/.kube/config}"

  if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_OK=$'\e[32m'; C_ERR=$'\e[31m'; C_DIM=$'\e[2m'; C_OFF=$'\e[0m'
  else
    C_OK=""; C_ERR=""; C_DIM=""; C_OFF=""
  fi
  STEP="starting"
  START_TS=$(date +%s)
  trap 'die "step failed: ${STEP}"' ERR

  mkdir -p "$STATE_DIR/pf" /root/observability
  touch "$LOG"
  printf '\n%sObservability Fundamentals setup for topic %s%s\n\n' "$C_DIM" "$OBS_TOPIC" "$C_OFF"
  log "setup for topic ${OBS_TOPIC} (repo ${OBS_SHOP_REPO} @ ${OBS_SHOP_REF}, setup ${OBS_SETUP_IMAGE}:topic-${OBS_TOPIC})"

  # 1. cluster ---------------------------------------------------------------
  step "cluster node"
  local ready=0
  for _ in $(seq 1 50); do
    if kubectl wait --for=condition=Ready nodes --all --timeout=10s >>"$LOG" 2>&1; then ready=1; break; fi
    sleep 5
  done
  (( ready == 1 )) || die "the kind cluster is not ready. Check: kubectl get nodes"
  ok "cluster node ready"

  # 2. repository -------------------------------------------------------------
  step "clone the repository"
  if [[ -f "$SHOP_DIR/app/orders/app.py" && -d "$SHOP_DIR/.git" ]]; then
    ok "repository already at ${SHOP_DIR} (kept as it is)"
  else
    rm -rf "$SHOP_DIR"
    run git clone --quiet "$OBS_SHOP_REPO" "$SHOP_DIR"
    if [[ "$OBS_SHOP_REF" != "main" ]]; then
      run git -C "$SHOP_DIR" checkout --quiet "$OBS_SHOP_REF"
    fi
    # A clone from a local folder (tests) still names the real repository as origin.
    case "$OBS_SHOP_REPO" in
      /*|file://*) run git -C "$SHOP_DIR" remote set-url origin "$CANONICAL_REPO" ;;
    esac
    ok "repository cloned to ${SHOP_DIR}"
  fi
  cd "$SHOP_DIR"

  # 2a. setup files of this topic ---------------------------------------------------
  step "setup files"
  if [[ ! -f "$STATE_DIR/setup-${OBS_TOPIC}.done" ]]; then
    local img="${OBS_SETUP_IMAGE}:topic-${OBS_TOPIC}" cid
    if ! docker image inspect "$img" >/dev/null 2>&1; then
      run docker pull "$img" || die "could not download ${img}"
    fi
    cid="$(docker create "$img" none 2>>"$LOG")" || die "could not unpack ${img}"
    rm -rf "$SETUP_DIR"
    mkdir -p "$SETUP_DIR"
    if ! run docker cp "$cid:/setup/." "$SETUP_DIR/"; then
      docker rm "$cid" >/dev/null 2>&1 || true
      die "could not unpack ${img}"
    fi
    run docker rm "$cid"
    chmod -R go-rwx "$SETUP_DIR"
    touch "$STATE_DIR/setup-${OBS_TOPIC}.done"
  fi
  export OBS_FILES
  ok "setup files ready"

  # 2b. monitoring stack as it is at the end of the previous topic ---------------
  # k8s/monitoring/setup-state.sh owns everything in namespace monitoring (safe to run again).
  if (( 10#$OBS_TOPIC >= 8 )) && [[ ! -f "$STATE_DIR/monitoring-${OBS_TOPIC}.done" ]]; then
    step "monitoring stack"
    info "setting up the monitoring stack as it is at the end of topic $(printf '%02d' $((10#$OBS_TOPIC - 1)))"
    run env OBS_REPO_DIR="$SHOP_DIR" OBS_FILES="$OBS_FILES" bash "$SETUP_DIR/setup-state.sh" "$((10#$OBS_TOPIC - 1))"
    touch "$STATE_DIR/monitoring-${OBS_TOPIC}.done"
    ok "monitoring stack ready"
  fi

  # 3. stages of the earlier topics ---------------------------------------------
  local nn f
  for nn in $(seq -w 1 $((10#$OBS_TOPIC - 1))); do
    nn="$(printf '%02d' "$((10#$nn))")"
    if [[ -f "$STATE_DIR/stage-${nn}.done" ]]; then
      ok "state of topic ${nn} already set up"
      continue
    fi
    f="$SETUP_DIR/stages/${nn}.sh"
    [[ -f "$f" ]] || continue
    info "setting up the state at the end of topic ${nn}"
    run_stage "$f"
    touch "$STATE_DIR/stage-${nn}.done"
  done

  # 4. extra setup for this topic -----------------------------------------------
  if [[ ! -f "$STATE_DIR/prep-${OBS_TOPIC}.done" ]]; then
    f="$SETUP_DIR/stages/prep-${OBS_TOPIC}.sh"
    if [[ -f "$f" ]]; then
      info "extra setup for topic ${OBS_TOPIC}"
      run_stage "$f"
      touch "$STATE_DIR/prep-${OBS_TOPIC}.done"
    fi
  fi

  # 5. port-forwards ----------------------------------------------------------
  step "port-forwards"
  ensure_pfs

  printf '\n'
  ok "topic ${OBS_TOPIC} is ready ($(elapsed)). Log: ${LOG}"
  printf '%sReady. Press Submit.%s\n' "$C_OK" "$C_OFF"
}

# ---------------------------------------------------------------- output
ok()   { printf '%s✔%s %s\n' "$C_OK" "$C_OFF" "$*"; log "OK $*"; }
info() { printf '%s…%s %s\n' "$C_DIM" "$C_OFF" "$*"; }
log()  { printf '\n## %s  (%s)\n' "$*" "$(date +%H:%M:%S)" >>"$LOG"; }
step() { STEP="$*"; log "STEP $*"; }
die()  {
  trap - ERR
  printf '%s✖%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2
  if [[ -s "$LOG" ]]; then
    printf '  last lines of the log:\n' >&2
    tail -n 8 "$LOG" | sed 's/^/    /' >&2
  fi
  printf '  full output: %s\n  It is safe to run the same command again.\n' "$LOG" >&2
  exit 1
}
# run: log the command line, send all output to the log, keep the exit code. stdin is /dev/null,
# because this script itself arrives on stdin (curl | bash).
run() { log "$*"; "$@" >>"$LOG" 2>&1 </dev/null; }
elapsed() {
  local s=$(( $(date +%s) - START_TS ))
  if (( s >= 60 )); then printf '%dm%02ds' $((s/60)) $((s%60)); else printf '%ds' "$s"; fi
}

run_stage() {
  local f="$1"
  log "stage $f"
  cd "$SHOP_DIR"
  # shellcheck disable=SC1090
  source "$f"
  cd "$SHOP_DIR"
}

# ---------------------------------------------------------------- helpers for stages
apply_manifests() {
  local p
  for p in "$@"; do run kubectl apply -f "$SHOP_DIR/$p"; done
}

wait_rollout() {
  local ns="$1" d; shift
  for d in "$@"; do
    run kubectl -n "$ns" rollout status "deploy/$d" --timeout="${OBS_ROLLOUT_TIMEOUT}s" \
      || die "deploy/$d in namespace $ns did not become ready. Check: kubectl -n $ns get pods"
  done
}

# start_pf UNIT NAMESPACE SERVICE PORT [ADDRESS]
start_pf() {
  local unit="$1" ns="$2" svc="$3" port="$4" addr="${5:-0.0.0.0}"
  printf '%s %s %s %s %s\n' "$unit" "$ns" "$svc" "$port" "$addr" >"$STATE_DIR/pf/$unit"
  systemctl stop "$unit" >>"$LOG" 2>&1 || true
  systemctl reset-failed "$unit" >>"$LOG" 2>&1 || true
  run systemd-run --unit "$unit" -p Restart=always -p RestartSec=3 --setenv=KUBECONFIG="$KUBECONFIG" \
    kubectl -n "$ns" port-forward "svc/$svc" --address "$addr" "$port:$port"
  local host="$addr"; [[ "$host" == "0.0.0.0" ]] && host="127.0.0.1"
  local i
  for i in $(seq 1 30); do
    if curl -s --max-time 2 -o /dev/null "http://${host}:${port}/"; then
      ok "port ${port} forwarded to ${svc} (background service ${unit})"
      return 0
    fi
    sleep 2
  done
  die "port ${port} does not answer. Check: systemctl status ${unit}"
}

wait_http() {
  local url="$1" tries="${2:-60}" code i
  for i in $(seq 1 "$tries"); do
    code="$(curl -s --max-time 3 -o /dev/null -w '%{http_code}' "$url" || true)"
    [[ "$code" =~ ^[23] ]] && return 0
    sleep 2
  done
  die "${url} does not answer"
}

# build_image TAG DIR: docker build and load into the kind cluster
build_image() {
  local tag="$1" dir="$2"
  [[ "$dir" == /* ]] || dir="$SHOP_DIR/$dir"
  run docker build -t "$tag" "$dir" || die "docker build of ${tag} from ${dir} failed"
  run kind load docker-image "$tag" || die "kind load of ${tag} failed"
}

use_topic_files() {
  local nn="$1" svc="$2" marker="$STATE_DIR/files-$1-$2.done"
  [[ -f "$marker" ]] && return 0
  [[ -d "$OBS_FILES/topic-${nn}/${svc}" ]] || die "topic-${nn}/${svc} is missing in the setup files"
  cp -r "$OBS_FILES/topic-${nn}/${svc}/." "$SHOP_DIR/app/${svc}/"
  touch "$marker"
}

deploy_topic_files() {
  local nn="$1" svc="$2"
  use_topic_files "$nn" "$svc"
  build_image "shop-${svc}:dev" "$OBS_FILES/topic-${nn}/${svc}"
  run kubectl -n shop set image "deploy/${svc}" "${svc}=shop-${svc}:dev"
  run kubectl -n shop rollout restart "deploy/${svc}"
  wait_rollout shop "$svc"
  ok "${svc} runs your code from topic ${nn} (image shop-${svc}:dev)"
}

# ensure_pfs: start again every port-forward unit started by start_pf that is not running now
ensure_pfs() {
  local f unit
  for f in "$STATE_DIR"/pf/*; do
    [[ -f "$f" ]] || continue
    unit="$(basename "$f")"
    if ! systemctl is-active --quiet "$unit"; then
      # shellcheck disable=SC2046
      start_pf $(cat "$f")
    fi
  done
}

send_checkouts() {
  ensure_pfs
  run bash "$SHOP_DIR/scripts/shop-load.sh" "$1"
}

main "$@"
