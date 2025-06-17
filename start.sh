#!/bin/bash

# --- Core Paths and Variables Configuration ---
# SERVER_ROOT_DIR is the directory where the 'minecraft-server' repository is cloned,
# and where the bash scripts (install, start, stop) are located.
SERVER_ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

# MINECRAFT_SERVER_DIR is the specific directory where the Minecraft server files
# (server.jar, eula.txt, server.properties, world, etc.) are stored.
MINECRAFT_SERVER_DIR="${SERVER_ROOT_DIR}/server"

# Configuration file (.env) for this script (must be in SERVER_ROOT_DIR)
CONFIG_ENV_FILE="${SERVER_ROOT_DIR}/.env"

# Absolute paths for executables (VERIFY THESE PATHS ON YOUR SERVER!)
JAVA_BIN="/usr/bin/java"
SCREEN_BIN="/usr/bin/screen"
WGET_BIN="/usr/bin/wget" # Kept for consistency if other scripts use it, but not used here.
RM_BIN="/usr/bin/rm"     # Kept for consistency
CHOWN_BIN="/usr/bin/chown" # Kept for consistency
MKDIR_BIN="/usr/bin/mkdir" # Kept for consistency
UFW_BIN="/usr/sbin/ufw" # Kept for consistency
IPTABLES_BIN="/usr/sbin/iptables" # Kept for consistency
GREP_BIN="/usr/bin/grep"
CUT_BIN="/usr/bin/cut"
SED_BIN="/usr/bin/sed"
HOSTNAME_BIN="/usr/bin/hostname"
TR_BIN="/usr/bin/tr"
CURL_BIN="/usr/bin/curl"
PS_BIN="/usr/bin/ps"
KILL_BIN="/usr/bin/kill"
SLEEP_BIN="/usr/bin/sleep"
SS_BIN="/usr/sbin/ss"

# --- Load variables from the .env file ---
if [ -f "$CONFIG_ENV_FILE" ]; then
    set -a # Automatically export all variables that are set or modified
    . "$CONFIG_ENV_FILE" # Source the .env file
    set +a # Turn off automatic export
else
    echo "ERROR Start: Minecraft configuration file '$CONFIG_ENV_FILE' not found in $SERVER_ROOT_DIR!"
    exit 1
fi

# Load Minecraft user if not defined
if [ -z "$MINECRAFT_USER" ]; then
    MINECRAFT_USER="$(whoami)"
    echo "MINECRAFT_USER not defined, using current user: $MINECRAFT_USER"
fi

# Verify RAM and PORT are defined from the .env file
if [ -z "$RAM" ] || [ -z "$PORT" ]; then
    echo "ERROR Start: RAM or PORT variables missing in configuration file '$CONFIG_ENV_FILE'!"
    exit 1
fi

echo "--- Minecraft Server Start ---"
echo "Attempting to start Minecraft server for user $MINECRAFT_USER on port $PORT with $RAM RAM."

# --- Pre-flight checks for executables ---
if [ ! -x "$JAVA_BIN" ]; then
    echo "ERROR Start: Java executable not found or not executable at '$JAVA_BIN'."
    echo "Please ensure Java is installed and the JAVA_BIN path is correct."
    exit 1
fi

if [ ! -x "$SCREEN_BIN" ]; then
    echo "ERROR Start: Screen executable not found or not executable at '$SCREEN_BIN'."
    echo "Please ensure 'screen' is installed and the SCREEN_BIN path is correct."
    exit 1
fi

# --- Verify server.jar exists (assuming installation is already done by another script) ---
if [ ! -f "${MINECRAFT_SERVER_DIR}/server.jar" ]; then
    echo "ERROR Start: server.jar not found in $MINECRAFT_SERVER_DIR!"
    echo "Please ensure the Minecraft server is installed. Run the installation script first if needed."
    exit 1
fi
echo "server.jar found in $MINECRAFT_SERVER_DIR."


# --- Start Minecraft Server in a screen session ---
echo "Starting Minecraft server with configured port..."
SCREEN_SESSION_NAME="mc"

echo "Ensuring no previous Minecraft server processes are running for user $MINECRAFT_USER..."
# Check if a screen session for 'mc' is already running for the MINECRAFT_USER
if sudo -u "$MINECRAFT_USER" "$SCREEN_BIN" -ls | "$GREP_BIN" -q "\.${SCREEN_SESSION_NAME}"; then
    echo -e "A screen session named '$SCREEN_SESSION_NAME' is already running for user $MINECRAFT_USER. To access it: \033[1;33mscreen -r $SCREEN_SESSION_NAME\033[0m"
    echo "If you need to restart, please stop the existing server first using the stop script or by detaching and using /stop in the console."
    exit 1
fi

# Attempt to kill any Java processes related to the Minecraft server for the MINECRAFT_USER
echo "Ensuring port $PORT is free before launch..."
# Find PIDS of Java processes owned by MINECRAFT_USER that are running from MINECRAFT_SERVER_DIR
PIDS_TO_KILL=$(sudo -u "$MINECRAFT_USER" "$PS_BIN" -eo pid,user,cmd | \
                "$GREP_BIN" "$MINECRAFT_SERVER_DIR" | \
                "$GREP_BIN" "java" | \
                "$GREP_BIN" -v "grep" | \
                "$TR_BIN" -s ' ' | "$CUT_BIN" -d' ' -f1) # Clean up multiple spaces before cutting PID

if [ -n "$PIDS_TO_KILL" ]; then
    echo "Found existing Java processes for Minecraft server (PIDS: $PIDS_TO_KILL). Attempting to terminate..."
    sudo "$KILL_BIN" $PIDS_TO_KILL 2>/dev/null || true # Try graceful kill first
    "$SLEEP_BIN" 2
    sudo "$KILL_BIN" -9 $PIDS_TO_KILL 2>/dev/null || true # Force kill if necessary
    echo "Existing Java processes terminated."
else
    echo "No existing Java processes for Minecraft server found for user $MINECRAFT_USER."
fi

"$SLEEP_BIN" 1 # Give a moment for ports to free up and processes to fully terminate

# --- Port verification and modification (NEW SECTION) ---
SERVER_PROPERTIES_PATH="${MINECRAFT_SERVER_DIR}/server.properties"

echo "Verifying server port in server.properties..."
if [ ! -f "$SERVER_PROPERTIES_PATH" ]; then
    echo "WARNING: server.properties not found at $SERVER_PROPERTIES_PATH. It will be generated on first server run."
    # The server will generate it and use default port, user might need to run install script again
else
    CURRENT_CONFIG_PORT=$(sudo -u "$MINECRAFT_USER" "$GREP_BIN" "^server-port=" "$SERVER_PROPERTIES_PATH" | "$CUT_BIN" -d'=' -f2)

    if [ -z "$CURRENT_CONFIG_PORT" ]; then
        echo "'server-port' entry not found in server.properties. Adding it."
        sudo -u "$MINECRAFT_USER" "$SED_BIN" -i "\$a\server-port=${PORT}" "$SERVER_PROPERTIES_PATH"
        echo "Port added to $SERVER_PROPERTIES_PATH: server-port=${PORT}"
    elif [[ "$CURRENT_CONFIG_PORT" != "$PORT" ]]; then
        echo "Current port in server.properties is $CURRENT_CONFIG_PORT, updating to $PORT..."
        sudo -u "$MINECRAFT_USER" "$SED_BIN" -i "s/^server-port=.*/server-port=${PORT}/" "$SERVER_PROPERTIES_PATH"
        echo "Port updated in $SERVER_PROPERTIES_PATH: server-port=${PORT}"
        # A server restart is implicitly handled because we kill previous processes before launch.
    else
        echo "Port $PORT is already correctly configured in server.properties."
    fi
fi
# --- End of Port verification and modification ---


echo "Launching Minecraft server in a screen named '$SCREEN_SESSION_NAME'..."

# Change to MINECRAFT_SERVER_DIR before launching screen,
# and launch Java directly into the screen without redirecting output to a file.
sudo -u "$MINECRAFT_USER" bash << EOF_FINAL_START
cd "$MINECRAFT_SERVER_DIR" || { echo "ERROR: Could not navigate to $MINECRAFT_SERVER_DIR for final startup."; exit 1; }
"$SCREEN_BIN" -dmS "$SCREEN_SESSION_NAME" "$JAVA_BIN" -Xmx${RAM} -Xms${RAM} -jar server.jar nogui
EOF_FINAL_START
LAUNCH_STATUS=$? # Capture the exit status of the previous command

# Now, we simply assume success if the 'screen' command itself exited successfully.
# Any actual Java errors will be visible when attaching to the screen.

if [ "$LAUNCH_STATUS" -eq 0 ]; then
    echo ""
    echo -e "\033[1;34m-------------------------------------------------\033[0m"
    echo -e "\033[1;34m Minecraft server launched successfully!\033[0m"
    echo -e "\033[1;34m-------------------------------------------------\033[0m"
    echo -e "\033[1;34mServer Information (for manual debugging) :\033[0m"
    echo -e "\033[1;34mLocal IP address:\033[0m \033[1;32m$(""$HOSTNAME_BIN"" -I | "$TR_BIN" ' ' '\n' | "$GREP_BIN" -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1):${PORT}\033[0m"
    echo -e "\033[1;34mPublic IP address:\033[0m \033[1;32m$(""$CURL_BIN"" -4 -s https://api64.ipify.org):${PORT}\033[0m \033[1;36m(if port is open on your router)\033[0m"
    echo -e "\033[1;34mServer folder location:\033[0m \033[1;33m$MINECRAFT_SERVER_DIR\033[0m"
    echo -e "\033[1;34mCommands to manage the server:\033[0m"
    echo -e "\033[1;33m  screen -r $SCREEN_SESSION_NAME \033[1;36m(to access the console)\033[0m"
    echo -e "\033[1;33m  /stop \033[1;36m(to stop the server from the console)\033[0m"
    echo -e "\033[1;33m  Ctrl + A, D \033[1;36m(to detach from the console)\033[0m"
    echo -e "\033[1;34m-------------------------------------------------\033[0m"
    echo ""
    exit 0
else
    echo ""
    echo -e "\033[1;31m--------------------------------------------------------\033[0m"
    echo -e "\033[1;31m ERROR: Minecraft server launch failed.\033[0m"
    echo -e "\033[1;31mScreen command exit code: $LAUNCH_STATUS\033[0m"
    echo -e "\033[1;31mEnsure user '$MINECRAFT_USER' has necessary permissions and 'screen' is functional.\033[0m"
    echo -e "\033[1;31m--------------------------------------------------------\033[0m"
    echo ""
    exit 1
fi
