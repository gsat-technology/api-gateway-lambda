#!/bin/bash

echo [`date`] "Building Lambda/API Gateway"

REGION=us-east-1

#API Gateway
REST_API_NAME=demo-api-gateway-lambda
RESOURCE_NAME=testresource
QUERY_STRING_PARAM=name
STAGE_NAME=test

#Lambda
LAMBDA_FUNCTION_NAME=$REST_API_NAME
LAMBDA_URI_PREFIX="arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/arn"
LAMBDA_ROLE_NAME=$LAMBDA_FUNCTION_NAME-role-with-inline-policy
LAMBDA_ROLE_NAME_POLICY=$LAMBDA_ROLE_NAME-policy

#S3 Bucket - This needs to be unique (change as desired)
S3_BUCKET_NAME=$LAMBDA_FUNCTION_NAME.someuniquenamexyz


#output some variables to teardown config
echo > ./teardown_conf.sh
echo "S3_BUCKET_NAME=$S3_BUCKET_NAME" >> ./teardown_conf.sh
echo "LAMBDA_FUNCTION_NAME=$LAMBDA_FUNCTION_NAME" >> ./teardown_conf.sh
echo "REGION=$REGION" >> ./teardown_conf.sh
echo "LAMBDA_ROLE_NAME=$LAMBDA_ROLE_NAME" >> ./teardown_conf.sh
echo "LAMBDA_ROLE_NAME_POLICY=$LAMBDA_ROLE_NAME_POLICY" >> ./teardown_conf.sh


### S3 ###

#Lambda expects a zip file to be uploaded to S3
zip  ./lambda-function.zip ./lambda-function.py 2>> error.log 1>> output.log


#Upload Lambda code to S3 bucket
echo -n [`date`] "creating S3 bucket..."
aws s3 mb --region $REGION s3://$S3_BUCKET_NAME 2>> error.log 1>> output.log

if [ $? -ne 0 ];
then
    echo [`date`]"an error occurred while creating bucket (check error.log)"
  exit
else
  echo "SUCCESS"
fi


aws s3 cp --region $REGION ./lambda-function.zip s3://$S3_BUCKET_NAME/$LAMBDA_FUNCTION_NAME 2>> error.log 1>> output.log



### IAM ###

#Creates the role Lambda uses for writing logs to CloudWatch Logs
echo -n [`date`] "creating Lambda role..."
aws iam create-role --region $REGION \
                    --role-name $LAMBDA_ROLE_NAME \
                    --assume-role-policy-document file://./assume-role-policy-doc.json 2>> error.log 1>> output.log

if [ $? -ne 0 ];
then
  echo "an error occurred while creating role (check error.log)" 
  exit
else
  echo "SUCCESS"
fi


#Creates an inline policy for the role
echo -n [`date`] "creating Lambda role-policy..."
aws iam put-role-policy --region $REGION \
                        --role-name $LAMBDA_ROLE_NAME \
                        --policy-name $LAMBDA_ROLE_NAME-policy \
                        --policy-document file://./policy-doc.json 2>> error.log 1> output.log

if [ $? -ne 0 ];
then
  echo "an error occurred while creating role-policy (check error.log)" 
  exit
else
  echo "SUCCESS"
fi


### Lambda ###


#Create lambda function
echo -n [`date`] "creating Lambda function..."
aws lambda create-function --region $REGION \
                           --function-name $LAMBDA_FUNCTION_NAME \
                           --runtime python2.7 \
                           --role arn:aws:iam::919974172442:role/lambda_basic_execution \
                           --handler lambda-function.lambda_handler \
                           --code S3Bucket=$S3_BUCKET_NAME,S3Key=$LAMBDA_FUNCTION_NAME 2>> error.log 1>> output.log

if [ $? -ne 0 ];
then
  echo "an error occurred while creating lambda function (check error.log)"
  exit
else
  echo "SUCCESS"
fi


#add permission to the lambda function so that API Gateway can invoke it
echo -n [`date`] "creating Lambda function permission..."
aws lambda add-permission --region $REGION \
                          --function-name $LAMBDA_FUNCTION_NAME \
                          --statement-id 'gs' \
                          --principal "apigateway.amazonaws.com" \
                          --action "lambda:InvokeFunction" 2>> error.log 1>> output.log

if [ $? -ne 0 ];
then
  echo "an error occurred while creating lambda function permission (check error.log)"
  exit
else
  echo "SUCCESS"
fi


LAMBDA_FUNCTION_ARN=$(aws lambda get-function --region $REGION \
                        --function-name $LAMBDA_FUNCTION_NAME \
                        --query Configuration.FunctionArn)

#strip quotation marks
LAMBDA_FUNCTION_ARN="${LAMBDA_FUNCTION_ARN%\"}"
LAMBDA_FUNCTION_ARN="${LAMBDA_FUNCTION_ARN#\"}"


### API Gateway ###

#Create rest api and store ID
echo -n [`date`] "creating API Gateway rest api..."
REST_API_ID=$(aws apigateway --region $REGION \
               create-rest-api \
               --name $REST_API_NAME | jq --raw-output .id)

if [ $? -ne 0 ];
then
  echo "an error occurred while creating rest api (check error.log)"
  exit
else
  echo "SUCCESS"
fi

#output rest api ID to the teardown config
echo "REST_API_ID=$REST_API_ID" >> ./teardown_conf.sh


PARENT_ID=$(aws apigateway get-resources --region $REGION \
                                         --rest-api-id $REST_API_ID \
                                         --query items[0].id)

#strip quotation marks
PARENT_ID="${PARENT_ID%\"}"
PARENT_ID="${PARENT_ID#\"}"


#create a resource on the API Gateway
echo -n [`date`] "creating API Gateway resource..."
RESOURCE_ID=$(aws apigateway create-resource --region $REGION \
                               --rest-api-id $REST_API_ID \
                               --parent-id $PARENT_ID \
                               --path-part $RESOURCE_NAME \
                               --query id)

#strip quotation marks
RESOURCE_ID="${RESOURCE_ID%\"}"
RESOURCE_ID="${RESOURCE_ID#\"}"


if [ $? -ne 0 ];
then
  echo "an error occurred while creating api gateway resource (check error.log)"
  exit
else
  echo "SUCCESS"
fi


#Put the method on the API Gateway
echo -n [`date`] "putting API Gateway method..."
aws apigateway put-method --region $REGION \
                          --rest-api-id $REST_API_ID \
                          --resource-id $RESOURCE_ID \
                          --http-method "GET" \
                          --authorization-type "None" \
                          --request-parameters "{\"method.request.querystring.$QUERY_STRING_PARAM\": false}" 2>> error.log 1>> output.log

if [ $? -ne 0 ];
then
  echo "an error occurred while putting api gateway method (check error.log)"
  exit
else
  echo "SUCCESS"
fi


#Put the integration
echo -n [`date`] "putting rest api integration..."
aws apigateway put-integration --region $REGION \
                               --rest-api-id $REST_API_ID \
                               --resource-id $RESOURCE_ID \
                               --http-method GET \
                               --type AWS \
                               --integration-http-method POST \
                               --uri arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/$LAMBDA_FUNCTION_ARN/invocations \
                               --request-templates '{"application/json": "{\n  \"queryParams\": {\n    #foreach($param in $input.params().querystring.keySet())\n    \"$param\": \"$util.escapeJavaScript($input.params().querystring.get($param))\" #if($foreach.hasNext),#end\n\n    #end\n  }\n}"}' 2>> error.log 1>> output.log

if [ $? -ne 0 ];
then
  echo "an error occurred while putting rest api integration (check error.log)"
  exit
else
  echo "SUCCESS"
fi


                   
echo -n [`date`] "putting integration response..."
aws apigateway put-integration-response --region $REGION \
                                        --rest-api-id $REST_API_ID \
                                        --resource-id $RESOURCE_ID \
                                        --http-method GET \
                                        --status-code 200 \
                                        --response-templates '{"application/json":""}' 2>> error.log 1>> output.log

if [ $? -ne 0 ];
then
  echo "an error occurred while putting integration response(check error.log)"
  exit
else
  echo "SUCCESS"
fi


echo -n [`date`] "putting method response..."
aws apigateway put-method-response --region $REGION \
                                   --rest-api-id $REST_API_ID \
                                   --resource-id $RESOURCE_ID \
                                   --http-method GET \
                                   --status-code 200 \
                                   --response-models '{"application/json": "Empty"}' 2>> error.log 1>> output.log

if [ $? -ne 0 ];
then
  echo "an error occurred while putting method-response (check error.log)"
  exit
else
  echo "SUCCESS"
fi


#TESTS
echo [`date`] "Completed configuration"
echo [`date`] ""
echo [`date`] "Running tests pre- API Gateway deployment"
echo [`date`] ""

#invoke the Lambda function
echo -n [`date`] "Invoking lambda function '$LAMBDA_FUNCTION_NAME'..."
aws lambda invoke --region $REGION \
                  --function-name $LAMBDA_FUNCTION_NAME \
                  --payload {} \
                  ./lambda.log 2>> error.log 1>> output.log

if [ $? -eq 0 ];
then
  echo "OKAY"
  echo -n [`date`] "testing lambda function output..."
  #check the json returned from the result contains the expected content
  cat ./lambda.log | jq --raw-output .lambda | grep "attribute added by lambda" 2>> error.log 1>> output.log
  
  if [ $? -eq 0 ];
  then
    echo "OKAY"
  else
    echo "ERROR"
  fi
  else "ERROR"
fi


#invoke the API Gateway function
#test that the given query string gets echoed back as part of the response
echo -n [`date`] "testing API Gateway output..." 
aws apigateway test-invoke-method --region $REGION \
                                  --rest-api-id $REST_API_ID \
                                  --resource-id $RESOURCE_ID \
                                  --http-method GET \
                                  --path-with-query-string /$RESOURCE_NAME?$QUERY_STRING_PARAM=abcdefg | grep abcdefg 2>> error.log 1>> output.log

if [ $? -ne 0 ];
then
  echo "ERROR" 
  exit
else
  echo "SUCCESS"
fi

#Deploy the API Gateway
echo -n [`date`] "deploying rest api..."
aws apigateway create-deployment --region $REGION \
                              --rest-api-id $REST_API_ID \
                              --stage-name $STAGE_NAME 2>> error.log 1>> output.log

if [ $? -ne 0 ];
then
  echo "an error occurred while creating rest api deployment (check error.log)"
  exit
else
  echo "SUCCESS"
fi

echo [`date`] "Running tests post- API Gateway deployment"

#test curling the public rest api
echo -n [`date`] "testing public rest api endpoint..."
curl -s https://$REST_API_ID.execute-api.$REGION.amazonaws.com/$STAGE_NAME/$RESOURCE_NAME?$QUERY_STRING_PARAM=abcdefg \
                   | jq --raw-output .queryParams.name | grep abcdefg 2>> error.log 1>> output.log

if [ $? -ne 0 ];
then
  echo "ERROR" 
  exit
else
  echo "SUCCESS"
fi

echo [`date`] "testing complete"


