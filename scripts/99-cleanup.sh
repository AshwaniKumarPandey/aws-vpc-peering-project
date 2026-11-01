#!/usr/bin/env bash
# Page 14: delete everything this project created. Run ONLY after saving evidence/screenshots.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
[ -z "${VPC_A:-}" ] && { echo "Nothing in state.env"; exit 0; }
try() { "$@" >/dev/null 2>&1 && echo "  ok: $1 $2 $3" || echo "  WARN (may already be gone): $*"; }

echo ">> Terminate instances"
aws ec2 terminate-instances --instance-ids ${BASTION_ID:-} ${APP_A_ID:-} ${APP_B_ID:-} >/dev/null
aws ec2 wait instance-terminated --instance-ids ${BASTION_ID:-} ${APP_A_ID:-} ${APP_B_ID:-}

echo ">> Peer routes + peering"
if [ -n "${PCX:-}" ]; then
  try aws ec2 delete-route --route-table-id "$RT_A_PRIV" --destination-cidr-block 10.20.0.0/16
  try aws ec2 delete-route --route-table-id "$RT_B_PRIV" --destination-cidr-block 10.10.0.0/16
  try aws ec2 delete-route --route-table-id "$RT_A_PUB"  --destination-cidr-block 10.20.0.0/16
  try aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id "$PCX"
  sleep 5
fi

echo ">> Security groups (retry until ENIs are released)"
for SG in "$SG_BASTION" "$SG_APP_A" "$SG_APP_B"; do
  for i in 1 2 3 4 5 6; do
    if aws ec2 delete-security-group --group-id "$SG" >/dev/null 2>&1; then echo "  deleted $SG"; break; else sleep 10; fi
  done
done

echo ">> Route tables / subnets / IGW / VPCs"
for A in "$ASSOC_A_PUB" "$ASSOC_A_PRIV" "$ASSOC_B_PRIV"; do try aws ec2 disassociate-route-table --association-id "$A"; done
for R in "$RT_A_PUB" "$RT_A_PRIV" "$RT_B_PRIV"; do try aws ec2 delete-route-table --route-table-id "$R"; done
for S in "$SUB_A_PUB" "$SUB_A_PRIV" "$SUB_B_PRIV"; do try aws ec2 delete-subnet --subnet-id "$S"; done
try aws ec2 detach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC_A"
try aws ec2 delete-internet-gateway --internet-gateway-id "$IGW"
try aws ec2 delete-vpc --vpc-id "$VPC_A"
try aws ec2 delete-vpc --vpc-id "$VPC_B"

echo ">> Key pair"
try aws ec2 delete-key-pair --key-name "$KEY_NAME"
rm -f "$KEY_PATH"

{
  echo "# CLEANUP VERIFICATION $(date -Is)"
  echo "VPCs with project tag (expect empty):"
  aws ec2 describe-vpcs --filters "Name=tag:Project,Values=$PROJECT_TAG" --query 'Vpcs[].VpcId' --output text
  echo "Non-terminated instances with project tag (expect empty):"
  aws ec2 describe-instances --filters "Name=tag:Project,Values=$PROJECT_TAG" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'Reservations[].Instances[].InstanceId' --output text
  echo "Volumes with project tag (expect empty):"
  aws ec2 describe-volumes --filters "Name=tag:Project,Values=$PROJECT_TAG" --query 'Volumes[].VolumeId' --output text
  echo "Elastic IPs in region (expect none from this project):"
  aws ec2 describe-addresses --query 'Addresses[].PublicIp' --output text
} | tee "$ROOT/evidence/06-cleanup-verification.txt"
mv "$STATE" "$STATE.cleaned.$(date +%s)"
echo "Cleanup done. Also check Billing/Cost Explorer later (usage reports lag)."
