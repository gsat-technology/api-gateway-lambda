from __future__ import print_function
import json

def lambda_handler(event, context):
    print("lambda received event: " + json.dumps(event, indent=2))

    #adds attribute 
    event['lambda'] = "attribute added by lambda function"

    return event
