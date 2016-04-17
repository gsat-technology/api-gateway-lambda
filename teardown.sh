#!/bin/bash

source ./teardown_conf.sh

#Check if s3 bucket exists
aws s3 ls --region $REGION $S3_BUCKET_NAME 2>> error.log 1>> output.log

if [ $? -eq 0 ];
then 
  echo -n [`date`] "S3 bucket '$S3_BUCKET_NAME' exists. Removing..."
  aws s3 rb s3://$S3_BUCKET_NAME --force --region $REGION 2>> error.log 1>> output.log

  if [ $? -eq 0 ];
  then
    echo "SUCCESS"
  else
    echo "there was an error removing bucket (check logs for error)"
  fi
else
  echo [`date`] "S3 bucket $S3_BUCKET_NAME doesn't exist. No need to remove it"
fi


#Check if lambda role-policy exists
aws iam get-role-policy --role-name $LAMBDA_ROLE_NAME \
                 --policy-name $LAMBDA_ROLE_NAME_POLICY 2>> error.log 1>> output.log

if [ $? -eq 0 ];
then
  echo -n [`date`] "IAM role-policy '$LAMBDA_ROLE_NAME_POLICY' exists. Removing..."
  aws iam delete-role-policy --role-name $LAMBDA_ROLE_NAME \
                             --policy-name $LAMBDA_ROLE_NAME_POLICY 2>> error.log 1>> output.log

  if [ $? -eq 0 ];
  then
    echo "SUCCESS"
  else
    echo "there was an error removing role-policy (check logs for error)"
  fi
else
  echo [`date`] "IAM role-policy '$LAMBDA_ROLE_NAME_POLICY' doesn't exist. No need to remove it"
fi


#Check if lambda role exists
aws iam get-role --role-name $LAMBDA_ROLE_NAME 2>> error.log 1>> output.log

if [ $? -eq 0 ];
then
  echo -n [`date`] "IAM role '$LAMBDA_ROLE_NAME' exists. Removing..."
  aws iam delete-role --role-name $LAMBDA_ROLE_NAME 2>> error.log 1>> output.log
  if [ $? -eq 0 ];
  then
    echo "SUCCESS"
  else
    echo "there was an error removing role (check logs for error)"
  fi
else
  echo [`date`] "IAM role '$LAMBDA_ROLE_NAME' doesn't exist. No need to remove it"
fi

#Check if lambda function exists
aws lambda get-function --region $REGION \
                        --function-name $LAMBDA_FUNCTION_NAME  2>> error.log 1>> output.log

if [ $? -eq 0 ];
then
  echo -n [`date`] "Lambda function '$LAMBDA_FUNCTION_NAME' exists. Removing..."
    aws lambda delete-function --region $REGION \
                               --function-name $LAMBDA_FUNCTION_NAME 2>> error.log 1>> output.log
  
  if [ $? -eq 0 ];
  then
    echo "SUCCESS"
  else
    echo "there was an error removing function (check logs for error)"
  fi
else
  echo [`date`] "lambda function '$LAMBDA_FUNCTION_NAME' doesn't exist. No need to remove it"
fi


#Check if rest api  exists
aws apigateway get-rest-api --region $REGION \
                            --rest-api-id $REST_API_ID  2>> error.log 1>> output.log 2>> error.log 1>> output.log

if [ $? -eq 0 ];
then
  echo -n [`date`] "API Gateway api '$REST_API_ID' exists. Removing..."
    aws apigateway delete-rest-api --region $REGION \
                                   --rest-api-id $REST_API_ID 2>> error.log 1>> output.log
  if [ $? -eq 0 ];
  then
    echo "SUCCESS"
  else
    echo "there was an error removing rest api (check logs for error)"
  fi
else
  echo [`date`] "API Gateway '$REST_API_ID' doesn't exist. No need to remove it"
fi

echo [`date`] "completed teardown"
echo [`date`] ""



