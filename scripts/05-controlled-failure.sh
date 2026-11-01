#!/usr/bin/env bash
# Page 11: remove ONLY the ICMP rule on App-B SG, ping fails, restore, ping works. SSH rule stays.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
S="ssh -F $SSHCFG"
RULE="IpProtocol=icmp,FromPort=8,ToPort=0,IpRanges=[{CidrIp=10.10.2.10/32}]"
{
  echo "# CONTROLLED FAILURE $(date -Is)"
  echo "## 1) Remove ICMP Echo rule (10.10.2.10/32) from ewb-sg-app-b"
  aws ec2 revoke-security-group-ingress --group-id "$SG_APP_B" --ip-permissions "$RULE" >/dev/null && echo "rule removed"
  sleep 5
  echo "## 2) App-A -> App-B ping (EXPECT FAILURE)"
  $S ewb-app-a 'ping -c 4 -W 2 10.20.1.10'
  echo; echo "## 3) Restore the exact rule"
  aws ec2 authorize-security-group-ingress --group-id "$SG_APP_B" --ip-permissions "$RULE" >/dev/null && echo "rule restored"
  sleep 5
  echo "## 4) App-A -> App-B ping again (EXPECT RECOVERY)"
  $S ewb-app-a 'ping -c 4 10.20.1.10'
} 2>&1 | tee "$ROOT/evidence/05-controlled-failure-and-recovery.txt"
echo; echo "Evidence is in ./evidence. Take console screenshots now (see docs/REPORT_TEMPLATE.md), THEN run ./scripts/99-cleanup.sh"
