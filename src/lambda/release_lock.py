"""
Lock Release Lambda Function - Simplified
"""

import json

def lambda_handler(event, context):
    """
    Simplified lock release handler
    """
    
    print("Hello World - Release Lock Lambda")
    print(f"Received event: {json.dumps(event)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Hello World from Release Lock Lambda',
            'lock_released': True
        })
    }