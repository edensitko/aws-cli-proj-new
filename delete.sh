#!/bin/bash
set -x
set -e

AMI_ID="ami-08b5b3a93ed654d19"
RED_SUBNET_ID="subnet-07daf692c09286bb3" 
BLUE_SUBNET_ID="subnet-0d687f0d29ad6415a"
VPC_ID="vpc-07edc3e691f6f6d50"
REGION="us-east-1"              # Make sure it's set correctly
SG_NAME="alb-security-group-1"  # unique name to avoid duplicates
ALB_NAME="alb-name"
TG_RED="tg-red"
TG_BLUE="tg-blue"

#######################
# 1) מציאת ה-Instances
#######################
echo "Looking for Red instance..."
RED_INSTANCE_ID=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters "Name=tag:Name,Values=Red" "Name=instance-state-name,Values=running,stopped" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text 2>/dev/null)

echo "Looking for Blue instance..."
BLUE_INSTANCE_ID=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters "Name=tag:Name,Values=Blue" "Name=instance-state-name,Values=running,stopped" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text 2>/dev/null)

############################
# 2) מחיקת (Terminate) מכונות
############################
if [ "$RED_INSTANCE_ID" != "None" ] && [ "$RED_INSTANCE_ID" != "" ]; then
  echo "Terminating Red instance: $RED_INSTANCE_ID"
  aws ec2 terminate-instances --region "$REGION" --instance-ids "$RED_INSTANCE_ID"
else
  echo "No Red instance found."
fi

if [ "$BLUE_INSTANCE_ID" != "None" ] && [ "$BLUE_INSTANCE_ID" != "" ]; then
  echo "Terminating Blue instance: $BLUE_INSTANCE_ID"
  aws ec2 terminate-instances --region "$REGION" --instance-ids "$BLUE_INSTANCE_ID"
else
  echo "No Blue instance found."
fi

echo "Waiting 15 seconds for termination command to register..."
sleep 15

############################
# 3) מחיקת Target Groups
############################
echo "Deleting target group: $TG_RED"
aws elbv2 delete-target-group --region "$REGION" --target-group-arn \
  $(aws elbv2 describe-target-groups \
     --region "$REGION" \
     --names "$TG_RED" \
     --query "TargetGroups[0].TargetGroupArn" \
     --output text 2>/dev/null) \
  2>/dev/null || echo "TG $TG_RED not found or already deleted."

echo "Deleting target group: $TG_BLUE"
aws elbv2 delete-target-group --region "$REGION" --target-group-arn \
  $(aws elbv2 describe-target-groups \
     --region "$REGION" \
     --names "$TG_BLUE" \
     --query "TargetGroups[0].TargetGroupArn" \
     --output text 2>/dev/null) \
  2>/dev/null || echo "TG $TG_BLUE not found or already deleted."

############################
# 4) מחיקת Security Group
############################
# צריך לוודא שהמכונות שיצרנו לא משתמשות בו יותר (לכן חיכינו עד termination).
# אם עדיין לא ניתן למחוק, יכול להיות שה-Instances לא נמחקו לגמרי.
# אפשר להמתין עוד קצת או לבצע מחיקה ידנית בקונסול.
echo "Attempting to delete security group: $SG_NAME"

# נמצא את ה-SG ID לפי שם:
SG_ID=$(aws ec2 describe-security-groups \
  --region "$REGION" \
  --filters Name=group-name,Values="$SG_NAME" \
  --query "SecurityGroups[0].GroupId" \
  --output text 2>/dev/null)

if [ "$SG_ID" != "None" ] && [ "$SG_ID" != "" ]; then
  echo "Deleting SG: $SG_ID"
  aws ec2 delete-security-group --region "$REGION" --group-id "$SG_ID" \
    2>/dev/null || echo "Could not delete SG. Maybe it's still in use."
else
  echo "SG $SG_NAME not found or already deleted."
fi

echo "Cleanup script completed."
