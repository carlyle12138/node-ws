#!/bin/bash

checkNodeScriptAlive() {
  local script_name=$1
  if pgrep -f "node.*${script_name}" >/dev/null; then
    return 0 # Alive
  else
    return 1 # Not alive
  fi
}

USERNAME=$(whoami)
APP_DIR="/home/$USERNAME/public_html" # Adjust if your app directory is different
INDEX_JS_PATH="$APP_DIR/index.js"
LOG_FILE="$APP_DIR/cron_run.log" # Consolidated log file

NODE_EXEC_PATH=$(command -v node)
if [ -z "$NODE_EXEC_PATH" ]; then
  NODE_EXEC_PATH="/opt/alt/alt-nodejs20/root/usr/bin/node" # Common fallback
fi

log_message() {
  echo "[$(date)] $1" >> "$LOG_FILE"
}

if ! checkNodeScriptAlive "index.js"; then
  log_message "Node.js script 'index.js' is not running. Attempting to start..."
  cd "$APP_DIR" || { log_message "Failed to cd to $APP_DIR. Exiting."; exit 1; }

  if [ -f "$INDEX_JS_PATH" ] && [ -d "node_modules" ]; then
    nohup "$NODE_EXEC_PATH" "$INDEX_JS_PATH" >> "$APP_DIR/out.log" 2>&1 &
    log_message "Node.js script 'index.js' start command issued."
  else
    log_message "Cannot start 'index.js': File or node_modules not found in $APP_DIR."
  fi
else
  # log_message "Node.js script 'index.js' is already running." # Optional: for verbosity
  :
fi
