#!/usr/bin/env bash
# esc bash - Shell Scripting Project #3 setup
set -euo pipefail
mkdir -p /root/mission/junk
for n in 1 2 3; do
  echo "temporary junk $n" > "/root/mission/junk/tmp-$n.tmp"
done
echo "keep me" > /root/mission/junk/keep.log
echo "Project 3 ready. /root/mission/junk contains:"
ls -1 /root/mission/junk
echo "Build /root/scripts/esctool with status, clean, and disk subcommands."
