"""
Simple tests for AWS Infrastructure Project
"""

import unittest
import sys
import os

# Add src to path for imports
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'src'))

from src.utils.common import hello_world, create_lambda_response

class TestSimpleUtils(unittest.TestCase):
    """Test simple utility functions"""
    
    def test_hello_world(self):
        """Test hello world function"""
        result = hello_world()
        self.assertEqual(result, "Hello World from Common Utils!")
    
    def test_create_lambda_response(self):
        """Test lambda response creation"""
        result = create_lambda_response(200, {"message": "success"})
        self.assertEqual(result['statusCode'], 200)
        self.assertIn('body', result)

if __name__ == '__main__':
    unittest.main()