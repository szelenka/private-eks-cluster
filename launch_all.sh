#!/usr/bin/env bash
set -e

source variables.sh 

# aws cloudformation deploy <-- create a network in which to put the EKS cluster
# set SUBNETS, SECURITY_GROUPS, WORKER_SECURITY_GROUPS, VPC_ID appropriately
STACK_NAME=${CLUSTER_NAME}-vpc
aws cloudformation package \
    --s3-bucket ${S3_STAGING_LOCATION} \
    --output-template-file /tmp/packaged.yaml \
    --region ${REGION} \
    --template-file cloudformation/environment.yaml

aws cloudformation deploy \
    --template-file /tmp/packaged.yaml \
    --region ${REGION} \
    --stack-name ${STACK_NAME} \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides HttpProxyServiceName=${HTTP_PROXY_ENDPOINT_SERVICE_NAME} StackPrefix=${CLUSTER_NAME}

VPC_ID=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='VPCId'].OutputValue" --output text`
SUBNETS=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='Subnets'].OutputValue" --output text`
ROLE_ARN=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='MasterRoleArn'].OutputValue" --output text`
MASTER_SECURITY_GROUPS=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='MasterSecurityGroup'].OutputValue" --output text`
WORKER_SECURITY_GROUPS=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='EndpointClientSecurityGroup'].OutputValue" --output text`
PROXY_URL=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='HttpProxyUrl'].OutputValue" --output text`

aws eks create-cluster \
    --name ${CLUSTER_NAME} \
    --role-arn ${ROLE_ARN} \
    --resources-vpc subnetIds=${SUBNETS},securityGroupIds=${MASTER_SECURITY_GROUPS},endpointPublicAccess=false,endpointPrivateAccess=true \
    --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}' \
    --kubernetes-version ${VERSION} \
    --region ${REGION}

# wait for the cluster to create
while [ $(aws eks describe-cluster --name ${CLUSTER_NAME} --query 'cluster.status' --output text --region ${REGION}) == "CREATING" ]
do
    echo Cluster ${CLUSTER_NAME} status: CREATING...
    sleep 60
done
echo Cluster ${CLUSTER_NAME} is ACTIVE

source launch_workers.sh