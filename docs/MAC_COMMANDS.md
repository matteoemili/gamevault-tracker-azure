# Mac-Specific Commands for GameVault Tracker

## Quick Setup (macOS)

### Install Prerequisites

```bash
# Install Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Node.js (if not installed)
brew install node

# Install Azure CLI
brew install azure-cli

# Install GitHub CLI (optional)
brew install gh
```

### Clone and Setup Project

```bash
# Clone repository
git clone https://github.com/matteoemili/gamevault-tracker-azure.git
cd gamevault-tracker-azure

# Make setup script executable
chmod +x setup.sh

# Run setup
./setup.sh

# Or manually:
cp .env.example .env
nano .env  # Or use your preferred editor (code .env, vim .env, etc.)
npm install
```

### Local Development

```bash
# Start development server
npm run dev

# Open in default browser
open http://localhost:5173

# Build for production (test)
npm run build

# Preview production build
npm run preview
open http://localhost:4173
```

## Azure CLI Commands (macOS)

### Login and Setup

```bash
# Login to Azure
az login
# Opens browser for authentication

# Set default subscription (if you have multiple)
az account set --subscription "Your Subscription Name"

# List your storage accounts
az storage account list --output table
```

### Generate SAS Token (macOS Date Syntax)

```bash
# Set variables
STORAGE_ACCOUNT="stvgcollection"
RESOURCE_GROUP="your-resource-group"

# Generate SAS token valid for 1 year (macOS date command)
EXPIRY_DATE=$(date -u -v+1y '+%Y-%m-%dT%H:%MZ')
echo "Expiry date: $EXPIRY_DATE"

az storage account generate-sas \
  --account-name $STORAGE_ACCOUNT \
  --services t \
  --resource-types sco \
  --permissions rwdlacu \
  --expiry $EXPIRY_DATE \
  --https-only \
  --output tsv

# Copy the output and save it
```

### macOS Date Examples

```bash
# 1 year from now
date -u -v+1y '+%Y-%m-%dT%H:%MZ'

# 6 months from now
date -u -v+6m '+%Y-%m-%dT%H:%MZ'

# 90 days from now
date -u -v+90d '+%Y-%m-%dT%H:%MZ'

# Specific date (December 31, 2025)
date -j -f "%Y-%m-%d %H:%M:%S" "2025-12-31 23:59:59" "+%Y-%m-%dT%H:%MZ"
```

### CORS Configuration

```bash
# Add CORS for localhost (development)
az storage cors add \
  --account-name stvgcollection \
  --services t \
  --methods GET POST PUT DELETE OPTIONS \
  --origins "http://localhost:5173" \
  --allowed-headers "*" \
  --exposed-headers "*" \
  --max-age 3600

# Add CORS for production
az storage cors add \
  --account-name stvgcollection \
  --services t \
  --methods GET POST PUT DELETE OPTIONS \
  --origins "https://ambitious-glacier-063139803.azurestaticapps.net" \
  --allowed-headers "*" \
  --exposed-headers "*" \
  --max-age 3600

# List CORS rules
az storage cors list \
  --account-name stvgcollection \
  --services t \
  --output table

# Clear all CORS rules (if needed)
az storage cors clear \
  --account-name stvgcollection \
  --services t
```

## GitHub CLI Commands (macOS)

### Setup GitHub CLI

```bash
# Install
brew install gh

# Login
gh auth login
# Follow prompts to authenticate

# Check authentication
gh auth status
```

### Manage Secrets

```bash
# List repository secrets
gh secret list

# Add secrets
gh secret set VITE_AZURE_STORAGE_ACCOUNT_NAME --body "stvgcollection"
gh secret set VITE_AZURE_STORAGE_SAS_TOKEN --body "sv=2024-11-04&ss=t..."

# Or add from file
echo "stvgcollection" > /tmp/account_name.txt
gh secret set VITE_AZURE_STORAGE_ACCOUNT_NAME < /tmp/account_name.txt
rm /tmp/account_name.txt

# Remove a secret
gh secret remove VITE_AZURE_STORAGE_ACCOUNT_KEY
```

### Trigger Workflow

```bash
# View workflows
gh workflow list

# Trigger a workflow run
gh workflow run "Azure Static Web Apps CI/CD"

# Watch workflow runs
gh run watch

# List recent runs
gh run list

# View logs of latest run
gh run view --log
```

## Git Commands (macOS)

### Branch Management

```bash
# Check current branch
git branch
# * storage  ← You're on this branch

# Switch to main
git checkout main

# Merge storage into main
git merge storage

# Push to GitHub
git push origin main

# Create and switch to new branch
git checkout -b feature/new-feature

# Delete local branch
git branch -d storage
```

### Common Workflows

```bash
# Quick commit and push
git add .
git commit -m "Your commit message"
git push

# Undo last commit (keep changes)
git reset --soft HEAD^

# View commit history
git log --oneline --graph --all

# View changes
git diff

# Discard local changes
git checkout -- .
```

## File Management (macOS)

### Viewing Files

```bash
# View .env file
cat .env

# Edit with nano
nano .env
# Ctrl+X to exit, Y to save

# Edit with VS Code
code .env

# Edit with vim
vim .env
# Press 'i' to insert, 'Esc' then ':wq' to save and quit

# View file with line numbers
cat -n src/App.tsx
```

### Search and Replace

```bash
# Find files containing text
grep -r "useKV" src/

# Find files by name
find . -name "*.tsx" -type f

# Search in dist folder
grep -r "stvgcollection" dist/assets/

# Count lines of code
find src -name "*.tsx" -o -name "*.ts" | xargs wc -l
```

## Development Tools (macOS)

### Browser Commands

```bash
# Open in default browser
open http://localhost:5173

# Open in specific browser
open -a "Google Chrome" http://localhost:5173
open -a "Firefox" http://localhost:5173
open -a "Safari" http://localhost:5173

# Open GitHub repo
open https://github.com/matteoemili/gamevault-tracker-azure

# Open Azure Portal
open https://portal.azure.com
```

### Process Management

```bash
# Find process using port 5173
lsof -i :5173

# Kill process on port 5173
lsof -ti :5173 | xargs kill -9

# Or use npm script
npm run kill  # If defined in package.json
```

### Keyboard Shortcuts in Terminal

```
⌘ + T          New tab
⌘ + N          New window
⌘ + K          Clear screen
⌘ + C          Cancel current command
Ctrl + C       Stop running process
Ctrl + D       Exit terminal
⌘ + +          Increase font size
⌘ + -          Decrease font size
```

## Troubleshooting (macOS)

### Check Versions

```bash
# Node.js version
node --version

# npm version
npm --version

# Azure CLI version
az --version

# GitHub CLI version
gh --version

# Git version
git --version
```

### Clear Caches

```bash
# Clear npm cache
npm cache clean --force

# Clear node_modules and reinstall
rm -rf node_modules package-lock.json
npm install

# Clear Vite cache
rm -rf node_modules/.vite
npm run dev
```

### View Logs

```bash
# View build output
npm run build 2>&1 | tee build.log

# View dev server logs
npm run dev 2>&1 | tee dev.log

# Follow logs in real-time
tail -f build.log
```

## Quick Reference Card

```bash
# Daily workflow
git pull origin main          # Get latest changes
npm run dev                   # Start dev server
# ... make changes ...
git add .                     # Stage changes
git commit -m "Description"   # Commit
git push origin main          # Deploy

# Production deployment
git checkout main             # Switch to main
git merge storage             # Merge your branch
git push origin main          # Trigger deployment
open https://github.com/.../actions  # Watch deployment

# Check environment
cat .env                      # Local config
gh secret list                # GitHub secrets
az storage cors list ...      # CORS rules

# Emergency fixes
git reset --hard HEAD         # Discard all changes
npm cache clean --force       # Clear npm cache
rm -rf node_modules && npm i  # Reinstall deps
```

## Environment Variables Priority (macOS)

```bash
# 1. Command line (highest priority)
VITE_AZURE_STORAGE_ACCOUNT_NAME=test npm run dev

# 2. .env.local (local overrides, gitignored)
# 3. .env (your main config)
# 4. .env.production (production builds)

# View all environment variables
printenv | grep VITE

# Check if variable is set
echo $VITE_AZURE_STORAGE_ACCOUNT_NAME
```

## Useful Aliases (Add to ~/.zshrc)

```bash
# Open ~/.zshrc
nano ~/.zshrc

# Add these aliases:
alias dev="npm run dev"
alias build="npm run build"
alias gp="git push"
alias gs="git status"
alias gc="git commit -m"
alias ga="git add ."
alias azlogin="az login"
alias ghsecrets="gh secret list"

# Save and reload
source ~/.zshrc
```

## System Preferences (macOS)

### Show Hidden Files in Finder

```bash
# Show hidden files (like .env)
defaults write com.apple.finder AppleShowAllFiles YES
killall Finder

# Hide hidden files again
defaults write com.apple.finder AppleShowAllFiles NO
killall Finder
```

### Set Default Terminal

```bash
# Use iTerm2 (if installed)
# Open iTerm2 > Preferences > General > Startup
# Select "Use default"

# Or use Warp, Hyper, or other modern terminals
```

---

**Keyboard Shortcuts Reference**:
- `⌘` = Command key
- `⌥` = Option/Alt key
- `⌃` = Control key
- `⇧` = Shift key

**Common Terminal Commands**:
- `ls` = List files
- `cd` = Change directory
- `pwd` = Print working directory
- `mkdir` = Make directory
- `rm` = Remove file
- `cp` = Copy file
- `mv` = Move/rename file
