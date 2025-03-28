#!/bin/bash
# /root/src/frankenwp/examples/setup-db.sh
# Host script to set up a database and user in the running MySQL container.
# Requires 'mysql' client installed on the host.

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
# Default values if arguments are not provided
DEFAULT_MYSQL_HOST="127.0.0.1"
DEFAULT_MYSQL_PORT="3306" # Should match the host port mapped in docker-compose.yml
DEFAULT_ROOT_USER="root"
# Read root password from environment variable DB_ROOT_PASSWORD or use a default
DEFAULT_ROOT_PASS="${DB_ROOT_PASSWORD:-rootpassword}"

# --- Argument Parsing ---
TARGET_DB_USER=""
TARGET_DB_PASS=""
TARGET_DB_NAME=""

usage() {
  echo "Usage: $0 -u <username> -p <password> [-d <dbname>] [-h <host>] [-P <port>] [-r <root_user>] [-rp <root_password>]"
  echo "  -u: Username for the new database user (required)."
  echo "  -p: Password for the new database user (required)."
  echo "  -d: Database name. If omitted, defaults to the username."
  echo "  -h: MySQL host (default: $DEFAULT_MYSQL_HOST)."
  echo "  -P: MySQL port (default: $DEFAULT_MYSQL_PORT)."
  echo "  -r: MySQL root user (default: $DEFAULT_ROOT_USER)."
  echo "  -rp: MySQL root password (reads from DB_ROOT_PASSWORD env var or uses default: '$DEFAULT_ROOT_PASS')."
  exit 1
}

MYSQL_HOST="$DEFAULT_MYSQL_HOST"
MYSQL_PORT="$DEFAULT_MYSQL_PORT"
ROOT_USER="$DEFAULT_ROOT_USER"
ROOT_PASS="$DEFAULT_ROOT_PASS" # Use default from env var first

while getopts "u:p:d:h:P:r:rp:" opt; do
  case $opt in
    u) TARGET_DB_USER="$OPTARG" ;;
    p) TARGET_DB_PASS="$OPTARG" ;;
    d) TARGET_DB_NAME="$OPTARG" ;;
    h) MYSQL_HOST="$OPTARG" ;;
    P) MYSQL_PORT="$OPTARG" ;;
    r) ROOT_USER="$OPTARG" ;;
    rp) ROOT_PASS="$OPTARG" ;; # Allow overriding root password via argument
    \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
  esac
done

# Validate required arguments
if [ -z "$TARGET_DB_USER" ] || [ -z "$TARGET_DB_PASS" ]; then
  echo "Error: Username (-u) and password (-p) are required."
  usage
fi

# Default database name to username if not provided
if [ -z "$TARGET_DB_NAME" ]; then
  TARGET_DB_NAME="$TARGET_DB_USER"
  echo "Database name not provided (-d), defaulting to username: '$TARGET_DB_NAME'"
else
  echo "Using provided database name: '$TARGET_DB_NAME'"
fi

echo "Connecting to MySQL at $MYSQL_HOST:$MYSQL_PORT as root user '$ROOT_USER'..."
echo "Attempting to create database '$TARGET_DB_NAME' and user '$TARGET_DB_USER'..."

# Construct the SQL commands
SQL_COMMANDS=$(cat <<-EOSQL
    -- Create the database if it doesn't exist
    CREATE DATABASE IF NOT EXISTS \`$TARGET_DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

    -- Create the user if it doesn't exist, identified by the password
    CREATE USER IF NOT EXISTS '$TARGET_DB_USER'@'%' IDENTIFIED BY '$TARGET_DB_PASS';

    -- Grant all privileges on the created database to the new user
    GRANT ALL PRIVILEGES ON \`$TARGET_DB_NAME\`.* TO '$TARGET_DB_USER'@'%';

    -- Apply the privilege changes
    FLUSH PRIVILEGES;
EOSQL
)

# Execute the SQL commands using the mysql client on the host
# Note: The '-p' flag for mysql client expects the password immediately after it, no space.
if mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u"$ROOT_USER" -p"$ROOT_PASS" -e "$SQL_COMMANDS"; then
  echo "Database '$TARGET_DB_NAME' and user '$TARGET_DB_USER' setup process completed successfully."
else
  echo "Error during database setup. Please check connection details, permissions, and MySQL server logs."
  exit 1
fi