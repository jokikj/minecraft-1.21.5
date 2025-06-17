#!/bin/bash

# --- Core Paths and Variables Configuration ---
# SERVER_ROOT_DIR is the directory where the 'minecraft-server' repository is cloned,
# and where the bash scripts (install, start, stop) are located.
SERVER_ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

# MINECRAFT_SERVER_DIR is the specific directory where the Minecraft server files
# (server.jar, eula.txt, server.properties, world, etc.) will be stored.
MINECRAFT_SERVER_DIR="${SERVER_ROOT_DIR}/server"

# Configuration file (.env) for this script (must be in SERVER_ROOT_DIR)
CONFIG_ENV_FILE="${SERVER_ROOT_DIR}/.env"

# Absolute paths for executables (VERIFY THESE PATHS ON YOUR SERVER!)
JAVA_BIN="/usr/bin/java"
SCREEN_BIN="/usr/bin/screen"
WGET_BIN="/usr/bin/wget"
RM_BIN="/usr/bin/rm"
CHOWN_BIN="/usr/bin/chown"
MKDIR_BIN="/usr/bin/mkdir"
UFW_BIN="/usr/sbin/ufw"
IPTABLES_BIN="/usr/sbin/iptables"
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
    set -a
    . "$CONFIG_ENV_FILE"
    set +a
else
    echo "ERROR Install: Minecraft configuration file '$CONFIG_ENV_FILE' not found in $SERVER_ROOT_DIR!"
    exit 1
fi

# Determine MINECRAFT_USER here for consistency throughout the script
# If not set in .env, default to the current user
if [ -z "$MINECRAFT_USER" ]; then
    MINECRAFT_USER="$(whoami)"
    echo "MINECRAFT_USER not defined in .env, using current user: $MINECRAFT_USER"
fi

# Verify RAM and PORT are defined
if [ -z "$RAM" ] || [ -z "$PORT" ]; then
    echo "ERROR Install: RAM or PORT variables missing in configuration file '$CONFIG_ENV_FILE'!"
    exit 1
fi

echo "--- Minecraft Server Installation ---"
echo "Starting installation for user $MINECRAFT_USER on port $PORT with $RAM RAM."

# --- Update packages ---
echo "Updating and upgrading packages..."
sudo apt update -y && sudo apt upgrade -y

# --- Install Java 21 and screen ---
echo "Installing openjdk-21-jre-headless and screen..."
sudo apt-get install openjdk-21-jre-headless screen -y

# --- Open the selected port with UFW and iptables ---
echo "Opening port $PORT with UFW and iptables..."
sudo "$UFW_BIN" allow "$PORT"
sudo "$IPTABLES_BIN" -I INPUT -p tcp --dport "$PORT" -j ACCEPT

# --- Create Minecraft server directory ---
echo "Creating directory $MINECRAFT_SERVER_DIR and assigning permissions..."
sudo "$MKDIR_BIN" -p "$MINECRAFT_SERVER_DIR"
sudo "$CHOWN_BIN" "$MINECRAFT_USER:$MINECRAFT_USER" "$MINECRAFT_SERVER_DIR"

# --- Download Minecraft server and accept EULA ---
echo "Downloading Minecraft server and accepting EULA..."
# Execute the entire block as MINECRAFT_USER to handle permissions correctly
sudo -u "$MINECRAFT_USER" bash << EOF_MINECRAFT_SETUP
cd "$MINECRAFT_SERVER_DIR" || { echo "ERROR: Could not navigate to $MINECRAFT_SERVER_DIR for installation."; exit 1; }

"$RM_BIN" -f server.jar # Remove server.jar if it exists without error

"$WGET_BIN" https://piston-data.mojang.com/v1/objects/e6ec2f64e6080b9b5d9b471b291c33cc7f509733/server.jar

# Accept the EULA
echo -e "#By changing the setting below to TRUE you are indicating your agreement to our EULA (https://aka.ms/MinecraftEULA).\n#$(date -u)\neula=true" > eula.txt
EOF_MINECRAFT_SETUP

echo "Minecraft server files installed! Verifying server.jar..."
if [ ! -f "${MINECRAFT_SERVER_DIR}/server.jar" ]; then
    echo "ERROR Install: server.jar file not found after download in $MINECRAFT_SERVER_DIR!"
    echo "Check if 'cd \"$MINECRAFT_SERVER_DIR\"' in the EOF_MINECRAFT_SETUP block worked."
    exit 1
fi
echo "server.jar found in $MINECRAFT_SERVER_DIR."


# --- Configure server.properties (no temporary launch needed) ---
SERVER_PROPERTIES_PATH="${MINECRAFT_SERVER_DIR}/server.properties"

echo "Configuring server.properties..."
sudo -u "$MINECRAFT_USER" bash << EOF_PROPERTIES_CONFIG
cd "$MINECRAFT_SERVER_DIR" || { echo "ERROR: Could not navigate to $MINECRAFT_SERVER_DIR for properties config."; exit 1; }

# Create server.properties if it doesn't exist or is empty
if [ ! -f "$SERVER_PROPERTIES_PATH" ] || [ ! -s "$SERVER_PROPERTIES_PATH" ]; then
    echo "server.properties not found or is empty. Creating a basic one."
    # Create a minimal server.properties. The server will add defaults on first run.
    echo "enable-query=false" > "$SERVER_PROPERTIES_PATH"
    echo "enable-rcon=false" >> "$SERVER_PROPERTIES_PATH"
    echo "query.port=25565" >> "$SERVER_PROPERTIES_PATH"
    echo "server-port=25565" >> "$SERVER_PROPERTIES_PATH" # Default for now
    echo "online-mode=true" >> "$SERVER_PROPERTIES_PATH"
    echo "motd=A Minecraft Server" >> "$SERVER_PROPERTIES_PATH"
fi

# Update or add server-port in server.properties
if "$GREP_BIN" -q "^server-port=" "$SERVER_PROPERTIES_PATH"; then
    # If server-port exists, update it
    "$SED_BIN" -i "s/^server-port=.*/server-port=${PORT}/" "$SERVER_PROPERTIES_PATH"
    echo "Port updated in $SERVER_PROPERTIES_PATH: server-port=${PORT}"
else
    # If server-port does not exist, add it
    echo "server-port=${PORT}" >> "$SERVER_PROPERTIES_PATH"
    echo "Port added to $SERVER_PROPERTIES_PATH: server-port=${PORT}"
fi

EOF_PROPERTIES_CONFIG

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to configure server.properties."
    exit 1
fi

# --- Final Installation Message ---
echo ""
echo -e "\033[1;34m-------------------------------------------------\033[0m"
echo -e "\033[1;32m Minecraft server installation completed!\033[0m"
echo -e "\033[1;34m-------------------------------------------------\033[0m"
echo -e "\033[0;36mYou can now start your server by running:\033[0m"
echo -e "\033[1;33m  ./start_minecraft.sh\033[0m"
echo -e "\033[0;36mTo stop the server, use:\033[0m"
echo -e "\033[1;33m  ./stop_minecraft.sh\033[0m"
echo -e "\033[1;34m-------------------------------------------------\033[0m"
echo ""

exit 0
