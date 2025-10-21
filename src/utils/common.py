"""
Shared utilities - Simplified
"""

def create_lambda_response(status_code, body):
    """Create Lambda response"""
    return {
        'statusCode': status_code,
        'body': body if isinstance(body, str) else str(body)
    }

def get_environment_variable(name, default=None):
    """Get environment variable"""
    import os
    return os.environ.get(name, default)

def hello_world():
    """Simple hello world function"""
    return "Hello World from Common Utils!"