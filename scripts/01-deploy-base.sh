#!/usr/bin/env bash
# Pages 5-7 of the workbook: VPC A, VPC B, subnets, IGW, route tables, security groups, 3 EC2 instances.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
need_name
[ -n "${VPC_A:-}" ] && { echo "state.env already has resources. Run 99-cleanup.sh first."; exit 1; }

echo ">> Who am I?"; aws sts get-caller-identity --query Arn --output text
AZ="${REGION}a"
MYIP=$(curl -s https://checkip.amazonaws.com | tr -d '[:space:]')
echo ">> Region=$REGION AZ=$AZ MyIP=$MYIP"

echo ">> Key pair"
if [ ! -f "$KEY_PATH" ]; then
  mkdir -p "$HOME/.ssh"
  if ! aws ec2 create-key-pair --key-name "$KEY_NAME" --key-type rsa --query KeyMaterial --output text > "$KEY_PATH.tmp"; then
    rm -f "$KEY_PATH.tmp"
    echo "Key '$KEY_NAME' already exists in AWS but .pem is not on this machine. Delete it in EC2 > Key pairs or change KEY_NAME."; exit 1
  fi
  mv "$KEY_PATH.tmp" "$KEY_PATH"; chmod 400 "$KEY_PATH"
fi

echo ">> VPC A (10.10.0.0/16)"
save VPC_A "$(aws ec2 create-vpc --cidr-block 10.10.0.0/16 --tag-specifications "$(tags vpc ewb-vpc-a)" --query Vpc.VpcId --output text)"
save SUB_A_PUB "$(aws ec2 create-subnet --vpc-id "$VPC_A" --cidr-block 10.10.1.0/24 --availability-zone "$AZ" --tag-specifications "$(tags subnet ewb-a-public)" --query Subnet.SubnetId --output text)"
save SUB_A_PRIV "$(aws ec2 create-subnet --vpc-id "$VPC_A" --cidr-block 10.10.2.0/24 --availability-zone "$AZ" --tag-specifications "$(tags subnet ewb-a-private)" --query Subnet.SubnetId --output text)"

echo ">> Internet gateway (attached to VPC A only)"
save IGW "$(aws ec2 create-internet-gateway --tag-specifications "$(tags internet-gateway ewb-igw-a)" --query InternetGateway.InternetGatewayId --output text)"
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC_A"

echo ">> Route tables VPC A"
save RT_A_PUB "$(aws ec2 create-route-table --vpc-id "$VPC_A" --tag-specifications "$(tags route-table ewb-rt-a-public)" --query RouteTable.RouteTableId --output text)"
save ASSOC_A_PUB "$(aws ec2 associate-route-table --route-table-id "$RT_A_PUB" --subnet-id "$SUB_A_PUB" --query AssociationId --output text)"
aws ec2 create-route --route-table-id "$RT_A_PUB" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW" >/dev/null
save RT_A_PRIV "$(aws ec2 create-route-table --vpc-id "$VPC_A" --tag-specifications "$(tags route-table ewb-rt-a-private)" --query RouteTable.RouteTableId --output text)"
save ASSOC_A_PRIV "$(aws ec2 associate-route-table --route-table-id "$RT_A_PRIV" --subnet-id "$SUB_A_PRIV" --query AssociationId --output text)"

echo ">> VPC B (10.20.0.0/16) - no IGW"
save VPC_B "$(aws ec2 create-vpc --cidr-block 10.20.0.0/16 --tag-specifications "$(tags vpc ewb-vpc-b)" --query Vpc.VpcId --output text)"
save SUB_B_PRIV "$(aws ec2 create-subnet --vpc-id "$VPC_B" --cidr-block 10.20.1.0/24 --availability-zone "$AZ" --tag-specifications "$(tags subnet ewb-b-private)" --query Subnet.SubnetId --output text)"
save RT_B_PRIV "$(aws ec2 create-route-table --vpc-id "$VPC_B" --tag-specifications "$(tags route-table ewb-rt-b-private)" --query RouteTable.RouteTableId --output text)"
save ASSOC_B_PRIV "$(aws ec2 associate-route-table --route-table-id "$RT_B_PRIV" --subnet-id "$SUB_B_PRIV" --query AssociationId --output text)"

echo ">> Security groups"
mksg() { aws ec2 create-security-group --group-name "$1" --description "$2" --vpc-id "$3" --tag-specifications "$(tags security-group "$1")" --query GroupId --output text; }
save SG_BASTION "$(mksg ewb-sg-bastion "EWB bastion SSH from my IP" "$VPC_A")"
save SG_APP_A   "$(mksg ewb-sg-app-a "EWB App-A rules" "$VPC_A")"
save SG_APP_B   "$(mksg ewb-sg-app-b "EWB App-B rules" "$VPC_B")"
ssh_rule()  { aws ec2 authorize-security-group-ingress --group-id "$1" --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=$2}]" >/dev/null; }
icmp_rule() { aws ec2 authorize-security-group-ingress --group-id "$1" --ip-permissions "IpProtocol=icmp,FromPort=8,ToPort=0,IpRanges=[{CidrIp=$2}]" >/dev/null; }
ssh_rule  "$SG_BASTION" "${MYIP}/32"
ssh_rule  "$SG_APP_A"   10.10.1.10/32
icmp_rule "$SG_APP_A"   10.20.1.10/32
ssh_rule  "$SG_APP_B"   10.10.1.10/32
icmp_rule "$SG_APP_B"   10.10.2.10/32

echo ">> Amazon Linux 2023 AMI"
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text 2>/dev/null || \
  aws ec2 describe-images --owners amazon --filters "Name=name,Values=al2023-ami-2023*-x86_64" "Name=architecture,Values=x86_64" --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)
echo "  AMI=$AMI"

launch() { # name subnet sg private-ip assign-public
  aws ec2 run-instances --image-id "$AMI" --instance-type "$INSTANCE_TYPE" --key-name "$KEY_NAME" \
    --network-interfaces "DeviceIndex=0,SubnetId=$2,Groups=$3,PrivateIpAddress=$4,AssociatePublicIpAddress=$5" \
    --block-device-mappings "DeviceName=/dev/xvda,Ebs={VolumeSize=8,VolumeType=gp3,DeleteOnTermination=true}" \
    --metadata-options HttpTokens=required \
    --tag-specifications "$(tags instance "$1")" "$(tags volume "$1")" \
    --query "Instances[0].InstanceId" --output text
}
echo ">> Launching instances"
save BASTION_ID "$(launch ewb-bastion "$SUB_A_PUB"  "$SG_BASTION" 10.10.1.10 true)"
save APP_A_ID   "$(launch ewb-app-a   "$SUB_A_PRIV" "$SG_APP_A"   10.10.2.10 false)"
save APP_B_ID   "$(launch ewb-app-b   "$SUB_B_PRIV" "$SG_APP_B"   10.20.1.10 false)"

echo ">> Waiting for status checks (2-3 min)..."
aws ec2 wait instance-status-ok --instance-ids "$BASTION_ID" "$APP_A_ID" "$APP_B_ID"
save BASTION_IP "$(aws ec2 describe-instances --instance-ids "$BASTION_ID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"

cat > "$SSHCFG" <<CFG
Host *
    StrictHostKeyChecking accept-new
    ServerAliveInterval 30

Host ewb-bastion
    HostName $BASTION_IP
    User ec2-user
    IdentityFile $KEY_PATH
    IdentitiesOnly yes

Host ewb-app-a
    HostName 10.10.2.10
    User ec2-user
    IdentityFile $KEY_PATH
    IdentitiesOnly yes
    ProxyJump ewb-bastion

Host ewb-app-b
    HostName 10.20.1.10
    User ec2-user
    IdentityFile $KEY_PATH
    IdentitiesOnly yes
    ProxyJump ewb-bastion
CFG
echo ">> Wrote $SSHCFG"

echo ">> Evidence: inventory (Checkpoint 01 + 02)"
{
  echo "# Inventory $(date -Is)"
  aws ec2 describe-vpcs --filters "Name=tag:Project,Values=$PROJECT_TAG" --query 'Vpcs[].[Tags[?Key==`Name`]|[0].Value,VpcId,CidrBlock]' --output table
  aws ec2 describe-subnets --filters "Name=tag:Project,Values=$PROJECT_TAG" --query 'Subnets[].[Tags[?Key==`Name`]|[0].Value,SubnetId,CidrBlock,MapPublicIpOnLaunch]' --output table
  aws ec2 describe-instances --filters "Name=tag:Project,Values=$PROJECT_TAG" "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,InstanceId,PrivateIpAddress,PublicIpAddress]' --output table
  aws ec2 describe-route-tables --route-table-ids "$RT_A_PUB" "$RT_A_PRIV" "$RT_B_PRIV" --query 'RouteTables[].[Tags[?Key==`Name`]|[0].Value,RouteTableId,Associations[0].SubnetId,Routes[].[DestinationCidrBlock,GatewayId]]' --output json
} | tee "$ROOT/evidence/01-inventory-before-peering.txt"

echo; echo "DONE. Next: ./scripts/02-baseline-test.sh"
