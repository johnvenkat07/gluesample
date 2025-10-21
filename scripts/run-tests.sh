#!/bin/bash

# ====================================================
# DEPRECATED: Please use infrastructure/scripts/status.sh
# ====================================================
# This script redirects to the new unified monitoring

echo "🔄 Redirecting to unified monitoring script..."
echo "📁 New location: infrastructure/scripts/status.sh"
echo ""

# Check if the new script exists
if [ -f "infrastructure/scripts/status.sh" ]; then
    echo "✅ Executing unified monitoring script..."
    exec infrastructure/scripts/status.sh "$@"
else
    echo "❌ Unified monitoring script not found!"
    echo "Please ensure infrastructure/scripts/status.sh exists"
    exit 1
fi