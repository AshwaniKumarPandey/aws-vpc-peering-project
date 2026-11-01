#!/usr/bin/env bash
# Pages 9-10: create + accept peering, add routes on both sides.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
[ -z "${VPC_A:-}" ] && { echo "Run 01-deploy-base.sh first"; exit 1; }
[ -n "${PCX:-}" ] && { echo "Peering already created: $PCX"; exit 1; }

echo ">> Create peering request (A = requester, B = accepter)"
save PCX "$(aws ec2 create-vpc-peering-connection --vpc-id "$VPC_A" --peer-vpc-id "$VPC_B" --tag-specifications "$(tags vpc-peering-connection ewb-a-b-peer)" --query VpcPeeringConnection.VpcPeeringConnectionId --output text)"
aws ec2 wait vpc-peering-connection-exists --vpc-peering-connection-ids "$PCX"
echo ">> Accept request"
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id "$PCX" >/dev/null
ST=""
for i in $(seq 1 24); do
  ST=$(aws ec2 describe-vpc-peering-connections --vpc-peering-connection-ids "$PCX" --query 'VpcPeeringConnections[0].Status.Code' --output text)
  echo "  status: $ST"; [ "$ST" = "active" ] && break; sleep 5
done
[ "$ST" = "active" ] || { echo "Peering not active"; exit 1; }

echo ">> Routes (both directions + bastion subnet)"
aws ec2 create-route --route-table-id "$RT_A_PRIV" --destination-cidr-block 10.20.0.0/16 --vpc-peering-connection-id "$PCX" >/dev/null
aws ec2 create-route --route-table-id "$RT_B_PRIV" --destination-cidr-block 10.10.0.0/16 --vpc-peering-connection-id "$PCX" >/dev/null
aws ec2 create-route --route-table-id "$RT_A_PUB"  --destination-cidr-block 10.20.0.0/16 --vpc-peering-connection-id "$PCX" >/dev/null

{
  echo "# PEERING + ROUTES $(date -Is)"
  aws ec2 describe-vpc-peering-connections --vpc-peering-connection-ids "$PCX" \
    --query 'VpcPeeringConnections[].[Tags[?Key==`Name`]|[0].Value,VpcPeeringConnectionId,Status.Code,RequesterVpcInfo.VpcId,RequesterVpcInfo.CidrBlock,AccepterVpcInfo.VpcId,AccepterVpcInfo.CidrBlock]' --output table
  for RT in "$RT_A_PRIV" "$RT_B_PRIV" "$RT_A_PUB"; do
    aws ec2 describe-route-tables --route-table-ids "$RT" \
      --query 'RouteTables[0].[Tags[?Key==`Name`]|[0].Value,Associations[0].SubnetId,Routes[].[DestinationCidrBlock,GatewayId,VpcPeeringConnectionId,State]]' --output json
  done
  echo "## Security group inbound rules"
  aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$SG_BASTION,$SG_APP_A,$SG_APP_B" \
    --query 'SecurityGroupRules[?IsEgress==`false`].[GroupId,IpProtocol,FromPort,ToPort,CidrIpv4]' --output table
} | tee "$ROOT/evidence/03-peering-and-routes.txt"

echo; echo "Next: ./scripts/04-run-tests.sh"
