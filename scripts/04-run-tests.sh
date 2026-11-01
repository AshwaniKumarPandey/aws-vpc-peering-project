#!/usr/bin/env bash
# Page 11: tests 02-05 after peering.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
S="ssh -F $SSHCFG"
{
  echo "# TESTS AFTER PEERING $(date -Is)"
  echo "## Test 02 - Forward path: App-A -> App-B (expect 4 replies, 0% loss)"
  $S ewb-app-a 'hostname; hostname -I; ping -c 4 10.20.1.10'
  echo; echo "## Test 03 - Reverse path: App-B -> App-A (expect 4 replies, 0% loss)"
  $S ewb-app-b 'hostname; hostname -I; ping -c 4 10.10.2.10'
  echo; echo "## Test 04 - Private SSH to App-B through bastion (ProxyJump)"
  $S ewb-app-b 'echo "Logged in to App-B via bastion"; hostname; hostname -I; whoami'
  echo; echo "## Test 05 - Isolation: no public IPv4 on App-A / App-B"
  aws ec2 describe-instances --instance-ids "$APP_A_ID" "$APP_B_ID" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,InstanceId,PrivateIpAddress,PublicIpAddress]' --output table
} 2>&1 | tee "$ROOT/evidence/04-tests-after-peering.txt"
echo; echo "Next: ./scripts/05-controlled-failure.sh"
