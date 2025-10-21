"""
S3 Upload Trigger Lambda Function - Simplified
"""

import json

def lambda_handler(event, context):
    """
    Simplified Lambda handler for S3 upload events
    """
    
    print("Hello World - S3 Trigger Lambda")
    print(f"Received event: {json.dumps(event)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Hello World from S3 Trigger Lambda',
            'event_processed': True
        })
    }