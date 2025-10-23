#!/bin/bash

# Quick Start Script for GameVault Tracker
# This script helps you set up the project quickly

echo "🎮 GameVault Tracker - Azure Setup"
echo "===================================="
echo ""

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed. Please install Node.js 18 or higher."
    exit 1
fi

echo "✅ Node.js version: $(node --version)"
echo ""

# Check if .env file exists
if [ ! -f .env ]; then
    echo "📝 Creating .env file from template..."
    cp .env.example .env
    echo "✅ .env file created"
    echo ""
    echo "⚠️  IMPORTANT: Edit .env and add your Azure credentials:"
    echo "   - VITE_AZURE_STORAGE_ACCOUNT_NAME"
    echo "   - VITE_AZURE_STORAGE_SAS_TOKEN"
    echo ""
    echo "   See AZURE_SETUP.md for detailed instructions."
    echo ""
else
    echo "✅ .env file already exists"
    echo ""
fi

# Install dependencies
echo "📦 Installing dependencies..."
npm install

if [ $? -eq 0 ]; then
    echo "✅ Dependencies installed successfully"
else
    echo "❌ Failed to install dependencies"
    exit 1
fi

echo ""
echo "===================================="
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Edit .env file with your Azure credentials"
echo "2. Set up Azure Storage Account (see AZURE_SETUP.md)"
echo "3. Run: npm run dev"
echo ""
echo "For detailed setup instructions, see AZURE_SETUP.md"
echo ""
