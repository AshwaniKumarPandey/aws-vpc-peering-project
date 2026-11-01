#!/usr/bin/env bash
# Page 8: baseline BEFORE peering. Ping App-A -> App-B must FAIL.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
S="ssh -F $SSHCFG"
{
  echo "# BASELINE (before peering) $(date -Is)"
  echo "## ssh ewb-bastion"; $S ewb-bastion 'hostname; hostname -I'
  echo "## ssh ewb-app-a";   $S ewb-app-a   'hostname; hostname -I'
  echo "## App-A -> App-B ping (EXPECTED: no replies / 100% packet loss)"
  $S ewb-app-a 'ping -c 4 -W 2 10.20.1.10'
  echo "(a non-zero result above is expected)"
} 2>&1 | tee "$ROOT/evidence/02-baseline-before-peering.txt"
echo; echo "Next: ./scripts/03-peering.sh"
