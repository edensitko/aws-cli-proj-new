
#!/bin/bash
set -x
set -e

# Variables - Change these values!
AMI_ID=""
RED_SUBNET_ID="" 
BLUE_SUBNET_ID=""
VPC_ID=""
REGION=""              
SG_NAME="" 
ALB_NAME=""
TG_RED="tg-red"
TG_BLUE="tg-blue"

####################################################
# 1) Check if Security Group with SG_NAME already exists
####################################################

EXISTING_SG_ID=$(aws ec2 describe-security-groups \
  --region $REGION \
  --filters Name=group-name,Values=$SG_NAME Name=vpc-id,Values=$VPC_ID \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null)

if [ "$EXISTING_SG_ID" = "None" ] || [ "$EXISTING_SG_ID" = "" ]; then
  echo "Creating new Security Group: $SG_NAME"
  SG_ID=$(aws ec2 create-security-group \
    --region $REGION \
    --group-name $SG_NAME \
    --description "Allow HTTP" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text)
  echo "Security Group Created: $SG_ID"
else
  echo "Security Group $SG_NAME already exists. Reusing it..."
  SG_ID=$EXISTING_SG_ID
fi

echo "Security Group ID: $SG_ID"

######################################################
# 2) Add ingress rule for HTTP if needed
######################################################
aws ec2 authorize-security-group-ingress \
  --region $REGION \
  --group-id $SG_ID \
  --protocol tcp --port 80 --cidr 0.0.0.0/0 \
  2>/dev/null || echo "Ingress rule for port 80 might already exist."  

# Create Target Groups
aws elbv2 create-target-group \
  --name $TG_RED \
  --protocol HTTP --port 80 \
  --vpc-id $VPC_ID \
  --region $REGION 2>/dev/null || echo "Target group $TG_RED might already exist."  

echo "Target Group created or exists: $TG_RED"

aws elbv2 create-target-group \
  --name $TG_BLUE \
  --protocol HTTP --port 80 \
  --vpc-id $VPC_ID \
  --region $REGION 2>/dev/null || echo "Target group $TG_BLUE might already exist."  

echo "Target Group created or exists: $TG_BLUE"

# UserData for Red Instance
cat > userdata_red.sh <<EOF
#!/bin/bash
# Commenting out yum update to avoid internet requirement
# yum update -y
yum install -y nginx
mkdir -p /usr/share/nginx/html/red
echo "<h1 style='color:red;'>Red Service</h1>" > /usr/share/nginx/html/red/index.html
cat > /etc/nginx/conf.d/red.conf <<EOC
server {
    listen 80;
    location /red/ {
        root /usr/share/nginx/html;
    }
}
EOC
systemctl enable nginx
systemctl start nginx
EOF

# Launch Red EC2
echo "Launching Red EC2..."
RED_INSTANCE_ID=$(aws ec2 run-instances \
  --region $REGION \
  --image-id $AMI_ID \
  --instance-type t2.micro \
  --security-group-ids $SG_ID \
  --user-data file://userdata_red.sh \
  --subnet-id $RED_SUBNET_ID \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Red}]' \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Launched Red instance: $RED_INSTANCE_ID"

# UserData for Blue Instance
cat > userdata_blue.sh <<EOF
#!/bin/bash
# Commenting out yum update to avoid internet requirement
# yum update -y
yum install -y nginx
# Removed EFS mount by default:
# yum install -y amazon-efs-utils
# mkdir -p /mnt/blue-efs
# mount -t efs fs-xxxxxxxx.efs.
# ${REGION}.amazonaws.com:/ /mnt/blue-efs

mkdir -p /usr/share/nginx/html/blue
echo "<h1 style='color:blue;'>Blue Service</h1>" > /usr/share/nginx/html/blue/index.html
cat > /etc/nginx/conf.d/blue.conf <<EOC
server {
    listen 80;
    location / {
        root /usr/share/nginx/html/blue;
    }
}
EOC
systemctl enable nginx
systemctl start nginx
EOF

echo "Launching Blue EC2..."
BLUE_INSTANCE_ID=$(aws ec2 run-instances \
  --region $REGION \
  --image-id $AMI_ID \
  --instance-type t2.micro \
  --security-group-ids $SG_ID \
  --user-data file://userdata_blue.sh \
  --subnet-id $BLUE_SUBNET_ID \
  --query 'Instances[0].InstanceId' \
  --output text \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Blue}]')

echo "Launched Blue instance: $BLUE_INSTANCE_ID"

sleep 20

echo "Getting Public IP of Red..."
RED_IP=$(aws ec2 describe-instances \
  --region $REGION \
  --instance-ids $RED_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "Getting Public IP of Blue..."
BLUE_IP=$(aws ec2 describe-instances \
  --region $REGION \
  --instance-ids $BLUE_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "========================================"
echo "Red Service URL:   http://$RED_IP/red"
echo "Blue Service URL:  http://$BLUE_IP/"
echo "========================================"
