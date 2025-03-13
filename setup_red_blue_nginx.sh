#!/bin/bash
set -euo pipefail 

############################################
#            VARIABLES                     #
AMI_ID="ami-08b5b3a93ed654d19"
RED_SUBNET_ID="subnet-07daf692c09286bb3" 
BLUE_SUBNET_ID="subnet-0d687f0d29ad6415a"
VPC_ID="vpc-07edc3e691f6f6d50"
REGION="us-east-1"           
SG_NAME="alb-security-group-1" 
ALB_NAME="alb-name"
TG_RED="tg-red"
TG_BLUE="tg-blue"
###########################################

# Get default VPC ID
VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true \
          --query "Vpcs[0].VpcId" --output text)
if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
    echo "Error: No default VPC found. Exiting." >&2
    exit 1
fi

# Get two subnets in default VPC
SUBNETS=($(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID \
          --query 'Subnets[0:2].SubnetId' --output text))
if [[ ${#SUBNETS[@]} -ne 2 ]]; then
    echo "Error: Less than two subnets found in VPC $VPC_ID. Cannot create ALB." >&2
    exit 1
fi
SUBNET_1=${SUBNETS[0]}
SUBNET_2=${SUBNETS[1]}

# Get latest Amazon Linux 2 AMI
AMI_ID=$(aws ssm get-parameters --names "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2" \
          --query "Parameters[0].Value" --output text)

INSTANCE_TYPE="t2.micro"
ALB_NAME="my-alb"
TG_RED_NAME="tg-red"
TG_BLUE_NAME="tg-blue"
SG_NAME="alb-sg"

############################################
#        1. CREATE/REUSE SECURITY GROUP    #
############################################
SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values="$SG_NAME" \
          --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "")

if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
    SG_ID=$(aws ec2 create-security-group --group-name "$SG_NAME" \
        --description "Allow HTTP traffic" --vpc-id "$VPC_ID" \
        --query 'GroupId' --output text)
    echo "✅ Security Group Created: $SG_ID"
else
    echo "✅ Security Group Exists: $SG_ID"
fi

# Open port 80 if not already open
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
    --protocol tcp --port 80 --cidr 0.0.0.0/0 || echo "Port 80 rule already exists."

############################################
#   2. DELETE EXISTING TARGET GROUPS       #
############################################
for TG_NAME in "$TG_RED_NAME" "$TG_BLUE_NAME"; do
    EXISTING_TG_ARN=$(aws elbv2 describe-target-groups --names "$TG_NAME" \
                      --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")

    if [[ -n "$EXISTING_TG_ARN" && "$EXISTING_TG_ARN" != "None" ]]; then
        echo "⚠️  Deleting existing Target Group: $TG_NAME..."
        aws elbv2 delete-target-group --target-group-arn "$EXISTING_TG_ARN"
        sleep 5  # Wait for deletion to complete
    fi
done

############################################
#   3. CREATE TARGET GROUPS                #
############################################
TG_RED_ARN=$(aws elbv2 create-target-group --name "$TG_RED_NAME" --protocol HTTP --port 80 \
              --vpc-id "$VPC_ID" --target-type instance \
              --health-check-path "/red/index.html" \
              --query 'TargetGroups[0].TargetGroupArn' --output text)

TG_BLUE_ARN=$(aws elbv2 create-target-group --name "$TG_BLUE_NAME" --protocol HTTP --port 80 \
              --vpc-id "$VPC_ID" --target-type instance \
              --health-check-path "/blue/index.html" \
              --query 'TargetGroups[0].TargetGroupArn' --output text)

############################################
#   4. CREATE USER DATA FOR EC2 INSTANCES  #
############################################
cat > user-data-red.sh << 'EOF'
#!/bin/bash
yum install -y httpd
systemctl enable httpd
systemctl start httpd

mkdir -p /var/www/html/red
echo "<h1 style='color:red;'>Welcome to the RED service</h1>" > /var/www/html/red/index.html
EOF

cat > user-data-blue.sh << 'EOF'
#!/bin/bash
yum install -y httpd
systemctl enable httpd
systemctl start httpd

mkdir -p /var/www/html/blue
echo "<h1 style='color:blue;'>Welcome to the BLUE service</h1>" > /var/www/html/blue/index.html
EOF

############################################
#       5. LAUNCH EC2 INSTANCES            #
############################################
INSTANCE1_ID=$(aws ec2 run-instances --image-id $AMI_ID --instance-type $INSTANCE_TYPE \
                 --security-group-ids $SG_ID --subnet-id $SUBNET_1 \
                 --user-data file://user-data-red.sh \
                 --query 'Instances[0].InstanceId' --output text)
echo "✅ Launched RED instance: $INSTANCE1_ID"

INSTANCE2_ID=$(aws ec2 run-instances --image-id $AMI_ID --instance-type $INSTANCE_TYPE \
                 --security-group-ids $SG_ID --subnet-id $SUBNET_2 \
                 --user-data file://user-data-blue.sh \
                 --query 'Instances[0].InstanceId' --output text)
echo "✅ Launched BLUE instance: $INSTANCE2_ID"

aws ec2 wait instance-status-ok --instance-ids $INSTANCE1_ID $INSTANCE2_ID
echo "✅ Both EC2 instances are running and healthy"

############################################
#   6. CREATE LOAD BALANCER                #
############################################
ALB_ARN=$(aws elbv2 create-load-balancer --name "$ALB_NAME" \
              --scheme internet-facing --security-groups $SG_ID \
              --subnets "$SUBNET_1" "$SUBNET_2" \
              --query 'LoadBalancers[0].LoadBalancerArn' --output text)

aws elbv2 wait load-balancer-available --load-balancer-arns $ALB_ARN
echo "✅ ALB is now available"

############################################
#   7. CREATE LISTENER & ROUTING RULES     #
############################################
LISTENER_ARN=$(aws elbv2 create-listener --load-balancer-arn $ALB_ARN \
                   --protocol HTTP --port 80 \
                   --default-actions Type=forward,TargetGroupArn=$TG_RED_ARN \
                   --query 'Listeners[0].ListenerArn' --output text)

aws elbv2 create-rule --listener-arn $LISTENER_ARN --priority 10 \
    --conditions Field=path-pattern,Values='/blue*' \
    --actions Type=forward,TargetGroupArn=$TG_BLUE_ARN > /dev/null
echo "✅ Added rule: if path is /blue* -> forward to tg-blue"

############################################
#   8. REGISTER INSTANCES TO TARGET GROUPS #
############################################
aws elbv2 register-targets --target-group-arn $TG_RED_ARN --targets Id=$INSTANCE1_ID
aws elbv2 register-targets --target-group-arn $TG_BLUE_ARN --targets Id=$INSTANCE2_ID

aws elbv2 wait target-in-service --target-group-arn $TG_RED_ARN
aws elbv2 wait target-in-service --target-group-arn $TG_BLUE_ARN

############################################
#   9. FINAL OUTPUT                        #
############################################
ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN --query 'LoadBalancers[0].DNSName' --output text)
echo "✅ Deployment Complete!"
echo "Red:  http://$ALB_DNS/red"
echo "Blue: http://$ALB_DNS/blue"
