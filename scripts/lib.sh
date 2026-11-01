#!/usr/bin/env bash
# Common helpers - sourced by every script
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/00-config.env"
STATE="$ROOT/state.env"
touch "$STATE"; source "$STATE"
mkdir -p "$ROOT/evidence" "$ROOT/ssh"
SSHCFG="$ROOT/ssh/config.generated"

save() { echo "$1=\"$2\"" >> "$STATE"; export "$1=$2"; echo "  saved $1 = $2"; }
tags() { echo "ResourceType=$1,Tags=[{Key=Name,Value=$2},{Key=Project,Value=$PROJECT_TAG},{Key=Student,Value=$STUDENT_NAME}]"; }
need_name() {
  if [ "$STUDENT_NAME" = "YOUR_NAME" ]; then
    echo "ERROR: open scripts/00-config.env and set STUDENT_NAME first"; exit 1
  fi
}
