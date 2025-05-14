#!/bin/bash

# --- Configuration: Replace with your actual URLs for the template files ---
# These template files should contain the placeholders as expected by this script.
TEMPLATE_INDEX_JS_URL="https://raw.githubusercontent.com/carlyle12138/node-ws/main/index.js"
TEMPLATE_CRON_SH_URL="https://raw.githubusercontent.com/carlyle12138/node-ws/main/cron.sh"

# --- Output Mode ---
PREVIEW_MODE=false
if [ "$1" == "--stdout-only" ]; then
  PREVIEW_MODE=true
  shift # Remove --stdout-only from arguments, $1 is now the domain
fi

# --- Helper Functions ---
print_error() { echo -e "\033[0;31mError: $1\033[0m" >&2; } # Ensure this prints to stderr
print_success() { echo -e "\033[0;32m$1\033[0m"; }
print_info() { echo -e "\033[0;34m$1\033[0m"; }

# --- Main Script ---
if [ "$PREVIEW_MODE" = false ]; then
  clear
  print_info "Node.js VLESS WebSocket Server Setup (Simplified)"
  print_info "================================================"
else
  # In preview mode, ensure helper messages also go to stderr if they are not part of the "content"
  echo -e "\033[0;34m--- PREVIEW MODE: Generating file contents to stdout ---\033[0m" >&2
fi

if [ -z "$1" ]; then
  print_error "Domain name is required!"
  echo "Usage: $0 [--stdout-only] yourdomain.com" >&2
  exit 1
fi

TARGET_DOMAIN=$1
USERNAME=$(whoami)
APP_PORT=$((RANDOM % 40001 + 20000))

# Define paths (used in normal mode)
APP_BASE_DIR="/home/$USERNAME/domains/$TARGET_DOMAIN"
APP_PUBLIC_HTML_DIR="$APP_BASE_DIR/public_html"
CRON_SCRIPT_INSTALL_PATH="/home/$USERNAME/app_vless_cron.sh"

# --- Collect Configuration Details (always needed) ---
if [ "$PREVIEW_MODE" = false ]; then print_info "Collecting configuration details..."; fi

DEFAULT_UUID=$(uuidgen 2>/dev/null || echo "a1b2c3d4-e5f6-7890-1234-567890abcdef") # Fallback UUID
read -rp "Enter VLESS UUID (default: $DEFAULT_UUID): " USER_UUID
USER_UUID=${USER_UUID:-$DEFAULT_UUID}
if ! [[ "$USER_UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  print_error "Invalid UUID format."; exit 1;
fi

read -rp "Enter subscription path (default: sub): " USER_SUB_PATH
USER_SUB_PATH=${USER_SUB_PATH:-sub}

read -rp "Enter node name prefix (default: MyVlessNode): " USER_NODE_NAME
USER_NODE_NAME=${USER_NODE_NAME:-MyVlessNode}

# --- Prepare index.js content ---
TEMP_INDEX_JS=$(mktemp)
# shellcheck disable=SC2154
INDEX_JS_CONTENT_GENERATOR() {
  curl -s -L -o "$TEMP_INDEX_JS" "$TEMPLATE_INDEX_JS_URL"
  if [ $? -ne 0 ] || [ ! -s "$TEMP_INDEX_JS" ]; then
    print_error "Failed to download index.js template. Check URL: $TEMPLATE_INDEX_JS_URL"
    echo "// Error: index.js template download failed. URL: $TEMPLATE_INDEX_JS_URL" > "$TEMP_INDEX_JS" # Write error into temp file for preview
    if [ "$PREVIEW_MODE" = false ]; then
        exit 1 # Critical failure in normal mode
    fi
    return 1 # Indicate failure in preview mode
  fi
  sed -i "s/'YOUR_UUID_PLACEHOLDER'/'$USER_UUID'/g" "$TEMP_INDEX_JS"
  sed -i "s/'YOUR_SUB_PATH_PLACEHOLDER'/'$USER_SUB_PATH'/g" "$TEMP_INDEX_JS"
  sed -i "s/'YOUR_NAME_PLACEHOLDER'/'$USER_NODE_NAME'/g" "$TEMP_INDEX_JS"
  sed -i "s/process.env.PORT || 0/process.env.PORT || $APP_PORT/g" "$TEMP_INDEX_JS"
  sed -i "s/'YOUR_DOMAIN_PLACEHOLDER'/'$TARGET_DOMAIN'/g" "$TEMP_INDEX_JS"
  return 0
}

# --- Prepare app_vless_cron.sh content ---
TEMP_CRON_SH=$(mktemp)
CRON_SH_CONTENT_GENERATOR() {
  curl -s -L -o "$TEMP_CRON_SH" "$TEMPLATE_CRON_SH_URL"
  if [ $? -ne 0 ] || [ ! -s "$TEMP_CRON_SH" ]; then
    print_error "Failed to download cron.sh template. Check URL: $TEMPLATE_CRON_SH_URL"
    echo "# Error: cron.sh template download failed. URL: $TEMPLATE_CRON_SH_URL" > "$TEMP_CRON_SH" # Write error into temp file
    if [ "$PREVIEW_MODE" = false ]; then
        exit 1 # Critical failure in normal mode
    fi
    return 1 # Indicate failure in preview mode
  fi
  # If cron.sh needed substitutions, they would go here.
  return 0
}

# --- Prepare package.json content ---
# shellcheck disable=SC2154
PACKAGE_JSON_CONTENT_GENERATOR() {
  cat << EOF
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
}

if [ "$PREVIEW_MODE" = true ]; then
  # Generate and output index.js
  INDEX_JS_CONTENT_GENERATOR # Call directly, errors go to stderr, content (or error) in TEMP_INDEX_JS
  echo "" # Newline separator for readability on terminal
  echo "--- BEGIN index.js ---"
  cat "$TEMP_INDEX_JS"
  echo "--- END index.js ---"
  
  # Generate and output app_vless_cron.sh
  CRON_SH_CONTENT_GENERATOR # Call directly
  echo ""
  echo "--- BEGIN app_vless_cron.sh ---"
  cat "$TEMP_CRON_SH"
  echo "--- END app_vless_cron.sh ---"

  # Generate and output package.json
  echo ""
  echo "--- BEGIN package.json ---"
  PACKAGE_JSON_CONTENT_GENERATOR
  echo "--- END package.json ---"

  # Preview cron job
  CRON_JOB_LINE_PREVIEW="*/2 * * * * /home/$USERNAME/app_vless_cron.sh # Actual path would be $CRON_SCRIPT_INSTALL_PATH"
  echo ""
  echo "--- Cron Job (Preview) ---"
  echo "Would add/update cron job line similar to: $CRON_JOB_LINE_PREVIEW"
  
  echo -e "\033[0;34mPreview generation complete. No files were written or system changes made.\033[0m" >&2

else # Normal execution mode
  if [ ! -d "$APP_PUBLIC_HTML_DIR" ]; then
      print_info "Creating directory: $APP_PUBLIC_HTML_DIR..."
      mkdir -p "$APP_PUBLIC_HTML_DIR"
      if [ $? -ne 0 ]; then print_error "Failed to create directory: $APP_PUBLIC_HTML_DIR"; rm -f "$TEMP_INDEX_JS" "$TEMP_CRON_SH"; exit 1; fi
  fi
  
  print_info "Configuring index.js..."
  INDEX_JS_CONTENT_GENERATOR
  if [ $? -ne 0 ]; then print_error "Failed to generate index.js content."; rm -f "$TEMP_INDEX_JS" "$TEMP_CRON_SH"; exit 1; fi
  cp "$TEMP_INDEX_JS" "$APP_PUBLIC_HTML_DIR/index.js"
  if [ $? -ne 0 ]; then print_error "Failed to write index.js"; rm -f "$TEMP_INDEX_JS" "$TEMP_CRON_SH"; exit 1; fi
  print_info "index.js configured and saved to $APP_PUBLIC_HTML_DIR/index.js"

  print_info "Configuring app_vless_cron.sh..."
  CRON_SH_CONTENT_GENERATOR
  if [ $? -ne 0 ]; then print_error "Failed to generate app_vless_cron.sh content."; rm -f "$TEMP_INDEX_JS" "$TEMP_CRON_SH"; exit 1; fi
  cp "$TEMP_CRON_SH" "$CRON_SCRIPT_INSTALL_PATH"
  if [ $? -ne 0 ]; then print_error "Failed to write $CRON_SCRIPT_INSTALL_PATH"; rm -f "$TEMP_INDEX_JS" "$TEMP_CRON_SH"; exit 1; fi
  chmod +x "$CRON_SCRIPT_INSTALL_PATH"
  print_info "app_vless_cron.sh configured and saved to $CRON_SCRIPT_INSTALL_PATH"

  print_info "Creating package.json..."
  PACKAGE_JSON_CONTENT_GENERATOR > "$APP_PUBLIC_HTML_DIR/package.json"
  if [ $? -ne 0 ]; then print_error "Failed to write package.json"; rm -f "$TEMP_INDEX_JS" "$TEMP_CRON_SH"; exit 1; fi
  print_info "package.json created in $APP_PUBLIC_HTML_DIR"

  print_info "Setting up cron job..."
  CRON_JOB_LINE="*/2 * * * * $CRON_SCRIPT_INSTALL_PATH"
  (crontab -l 2>/dev/null | grep -v -F "$CRON_SCRIPT_INSTALL_PATH" ; echo "$CRON_JOB_LINE") | crontab -
  if [ $? -eq 0 ]; then
    print_success "Cron job set up successfully."
    print_info "Cron script log: $APP_PUBLIC_HTML_DIR/cron_run.log (created by app_vless_cron.sh)"
  else
    print_error "Failed to set up cron job. Please set it up manually:"
    print_error "$CRON_JOB_LINE"
  fi

  print_success "Setup complete!"
  print_info "Application installed in: $APP_PUBLIC_HTML_DIR"
  print_info "Service will run on port: $APP_PORT"
  print_info "Ensure Node.js dependencies are installed: cd \"$APP_PUBLIC_HTML_DIR\" && npm install"
  print_info "Start manually: nohup node index.js > out.log 2>&1 & (or wait for cron)"
  echo
  print_info "To start immediately, run:"
  print_info "cd \"$APP_PUBLIC_HTML_DIR\" && npm install && nohup node index.js > out.log 2>&1 &"
fi

# Cleanup temporary files
rm -f "$TEMP_INDEX_JS" "$TEMP_CRON_SH" 2>/dev/null
