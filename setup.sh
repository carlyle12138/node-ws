#!/bin/bash

# --- Configuration: Replace with your actual URLs for the files above ---
NEW_INDEX_JS_URL="https://raw.githubusercontent.com/carlyle12138/node-ws/main/index.js"
NEW_CRON_SH_URL="https://raw.githubusercontent.com/carlyle12138/node-ws/main/cron.sh"

# --- Helper Functions ---
print_error() { echo -e "\033[0;31mError: $1\033[0m" >&2; }
print_success() { echo -e "\033[0;32m$1\033[0m"; }
print_info() { echo -e "\033[0;34m$1\033[0m"; }

# --- Main Script ---
clear
print_info "Node.js VLESS WebSocket Server Setup (Simplified)"
print_info "================================================"

if [ -z "$1" ]; then
  print_error "Domain name is required!"
  echo "Usage: $0 yourdomain.com"
  exit 1
fi

TARGET_DOMAIN=$1
USERNAME=$(whoami)
APP_PORT=$((RANDOM % 40001 + 20000)) # Random port for the application

APP_BASE_DIR="/home/$USERNAME/domains/$TARGET_DOMAIN" # Adjust if structure differs
APP_PUBLIC_HTML_DIR="$APP_BASE_DIR/public_html"
CRON_SCRIPT_INSTALL_PATH="/home/$USERNAME/app_vless_cron.sh" # Renamed for clarity

mkdir -p "$APP_PUBLIC_HTML_DIR"
if [ $? -ne 0 ]; then print_error "Failed to create directory: $APP_PUBLIC_HTML_DIR"; exit 1; fi
cd "$APP_PUBLIC_HTML_DIR" || exit 1

print_info "Downloading necessary files..."
curl -s -L -o "$APP_PUBLIC_HTML_DIR/index.js" "$NEW_INDEX_JS_URL"
if [ $? -ne 0 ] || [ ! -s "$APP_PUBLIC_HTML_DIR/index.js" ]; then
  print_error "Failed to download index.js from $NEW_INDEX_JS_URL"; exit 1;
fi

curl -s -L -o "$CRON_SCRIPT_INSTALL_PATH" "$NEW_CRON_SH_URL"
if [ $? -ne 0 ] || [ ! -s "$CRON_SCRIPT_INSTALL_PATH" ]; then
  print_error "Failed to download cron.sh from $NEW_CRON_SH_URL"; exit 1;
fi
chmod +x "$CRON_SCRIPT_INSTALL_PATH"

print_info "Collecting configuration details..."
DEFAULT_UUID=$(uuidgen 2>/dev/null || echo "de04add9-5c68-4bab-950c-08cd5320df33") # Fallback if uuidgen fails
read -rp "Enter VLESS UUID (default: $DEFAULT_UUID): " USER_UUID
USER_UUID=${USER_UUID:-$DEFAULT_UUID}
if ! [[ "$USER_UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  print_error "Invalid UUID format."; exit 1;
fi

read -rp "Enter subscription path (default: sub): " USER_SUB_PATH
USER_SUB_PATH=${USER_SUB_PATH:-sub}

read -rp "Enter node name prefix (default: MyVlessNode): " USER_NODE_NAME
USER_NODE_NAME=${USER_NODE_NAME:-MyVlessNode}

print_info "Configuring index.js..."
# Use a different sed delimiter if paths/domains might contain the default '/'
sed -i "s/'YOUR_UUID_PLACEHOLDER'/'$USER_UUID'/g" "$APP_PUBLIC_HTML_DIR/index.js"
sed -i "s/'YOUR_SUB_PATH_PLACEHOLDER'/'$USER_SUB_PATH'/g" "$APP_PUBLIC_HTML_DIR/index.js"
sed -i "s/'YOUR_NAME_PLACEHOLDER'/'$USER_NODE_NAME'/g" "$APP_PUBLIC_HTML_DIR/index.js"
sed -i "s/process.env.PORT || 0/process.env.PORT || $APP_PORT/g" "$APP_PUBLIC_HTML_DIR/index.js" # Replace default port 0
sed -i "s/'YOUR_DOMAIN_PLACEHOLDER'/'$TARGET_DOMAIN'/g" "$APP_PUBLIC_HTML_DIR/index.js"

print_info "Creating package.json..."
cat > "$APP_PUBLIC_HTML_DIR/package.json" << EOF
{
  "name": "node-vless-ws-server",
  "version": "1.0.0",
  "description": "Node.js VLESS WebSocket Server for ${TARGET_DOMAIN}",
  "main": "index.js",
  "author": "${USERNAME}",
  "license": "MIT",
  "private": true,
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "ws": "^8.14.2"
  },
  "engines": {
    "node": ">=14"
  }
}
EOF

print_info "Setting up cron job..."
CRON_JOB_LINE="*/2 * * * * $CRON_SCRIPT_INSTALL_PATH" # Runs every 2 minutes
(crontab -l 2>/dev/null | grep -v -F "$CRON_SCRIPT_INSTALL_PATH" ; echo "$CRON_JOB_LINE") | crontab -
if [ $? -eq 0 ]; then
  print_success "Cron job set up successfully."
  print_info "Cron script log: $APP_PUBLIC_HTML_DIR/cron_run.log (created by cron.sh)"
else
  print_error "Failed to set up cron job. Please set it up manually:"
  print_error "$CRON_JOB_LINE"
fi

print_success "Setup complete!"
print_info "Application installed in: $APP_PUBLIC_HTML_DIR"
print_info "Service will run on port: $APP_PORT"
print_info "Ensure Node.js dependencies are installed: cd $APP_PUBLIC_HTML_DIR && npm install"
print_info "Start manually: nohup node index.js > out.log 2>&1 & (or wait for cron)"
echo
print_info "To start immediately, run:"
print_info "cd \"$APP_PUBLIC_HTML_DIR\" && npm install && nohup node index.js > out.log 2>&1 &"
