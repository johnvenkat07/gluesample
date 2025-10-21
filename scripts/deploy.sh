#!/bin/bash

# ====================================================
# DEPRECATED: Please use infrastructure/scripts/deploy.sh
# ====================================================
# This script redirects to the new unified deployment

echo "🔄 Redirecting to unified deployment script..."
echo "📁 New location: infrastructure/scripts/deploy.sh"
echo ""

# Check if the new script exists
if [ -f "infrastructure/scripts/deploy.sh" ]; then
    echo "✅ Executing unified deployment script..."
    exec infrastructure/scripts/deploy.sh "$@"
else
    echo "❌ Unified deployment script not found!"
    echo "Please ensure infrastructure/scripts/deploy.sh exists"
    exit 1
fi