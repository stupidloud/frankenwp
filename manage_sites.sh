#!/bin/bash

# Script to manage site configurations in Caddyfile.multisite

CADDYFILE="Caddyfile.multisite"
MARKER="# <<< SITE_CONFIGURATIONS_BELOW >>>"
SITES_BASE_PATH="/var/www/sites" # Base path inside the container

# --- Helper Functions ---

# Function to display usage instructions
usage() {
  echo "Usage: $0 <command> [options]"
  echo ""
  echo "Commands:"
  echo "  add <domain> <site_dir>   Add a new site configuration."
  echo "                            <domain>: The domain name (e.g., my-site.example.com)."
  echo "                            <site_dir>: The site's directory name under ${SITES_BASE_PATH} (e.g., my-site)."
  echo "  remove <domain>           Remove an existing site configuration by domain."
  echo ""
  echo "Example:"
  echo "  $0 add my-site.example.com my-site"
  echo "  $0 remove my-site.example.com"
  exit 1
}

# Function to add a site configuration
add_site() {
  local domain="$1"
  local site_dir="$2"
  local site_root="${SITES_BASE_PATH}/${site_dir}"

  # Validate input
  if [ -z "$domain" ] || [ -z "$site_dir" ]; then
    echo "Error: Domain and site directory are required for 'add' command."
    usage
  fi

  # Check if domain already exists (basic check)
  if grep -q "^${domain} {" "$CADDYFILE"; then
    echo "Error: Site configuration for domain '${domain}' already exists in ${CADDYFILE}."
    exit 1
  fi

  # Generate the new site configuration block
  # Using printf for better handling of newlines and indentation
  local new_config
  new_config=$(printf '\n# --- %s Configuration ---\n%s {\n    root * %s\n    encode br zstd gzip\n    php_server\n    try_files {path} {path}/index.php?{query}\n    file_server\n    # Add site-specific directives here if needed\n}\n' \
    "$domain" "$domain" "$site_root")

  # Insert the new configuration block before the marker using sed
  # Using a temporary file for safer editing with sed -i
  local tmp_file
  tmp_file=$(mktemp)
  # Escape backslashes, forward slashes, and ampersands for sed insertion
  local escaped_config
  escaped_config=$(echo "$new_config" | sed -e 's/[\/&]/\\&/g' -e 's/\\/\\\\/g')

  # Use awk for safer insertion before the marker line
  awk -v marker="$MARKER" -v config="$new_config" '
  $0 == marker {
    print config
  }
  { print }
  ' "$CADDYFILE" > "$tmp_file" && mv "$tmp_file" "$CADDYFILE"


  if [ $? -eq 0 ]; then
    echo "Successfully added site configuration for '${domain}' to ${CADDYFILE}."
  else
    echo "Error: Failed to add site configuration to ${CADDYFILE}."
    rm -f "$tmp_file" # Clean up temp file on error
    exit 1
  fi
}

# Function to remove a site configuration
remove_site() {
  local domain="$1"

  # Validate input
  if [ -z "$domain" ]; then
    echo "Error: Domain is required for 'remove' command."
    usage
  fi

  # Check if domain exists before attempting removal
  if ! grep -q "^${domain} {" "$CADDYFILE"; then
    echo "Error: Site configuration for domain '${domain}' not found in ${CADDYFILE}."
    exit 1
  fi

  # Remove the configuration block using sed
  # This attempts to find the block starting with the domain and ending with '}'
  # Note: This might be fragile if comments or nested blocks interfere.
  # Using awk for a potentially safer approach by tracking block depth or line numbers would be more robust.
  local tmp_file
  tmp_file=$(mktemp)

  # Use awk to delete the block more reliably
  awk -v domain="$domain" '
  BEGIN { in_block = 0; brace_level = 0 }
  # Match the start line (domain followed by space and {)
  $0 ~ "^" domain "[[:space:]]*\\{" {
      in_block = 1
      brace_level = 1
      next # Skip printing the start line
  }
  in_block {
      # Count braces to find the end of the block
      brace_level += gsub(/{/, "{")
      brace_level -= gsub(/}/, "}")
      if (brace_level == 0) {
          in_block = 0 # End of block found
          # Check if there was a comment line before the block start
          if (prev_line ~ /^#[[:space:]]*---.*Configuration ---/) {
              # Don't print the preceding comment line either
              prev_line = "" # Clear it so it's not printed later
          }
          next # Skip printing the closing brace line
      }
      next # Skip printing lines inside the block
  }
  # Print lines outside the target block
  {
      if (prev_line != "") { print prev_line } # Print the previous line if it wasn't skipped
      prev_line = $0 # Store current line as previous for next iteration
  }
  END { if (prev_line != "") { print prev_line } } # Print the last line
  ' "$CADDYFILE" > "$tmp_file" && mv "$tmp_file" "$CADDYFILE"


  if [ $? -eq 0 ]; then
    echo "Successfully removed site configuration for '${domain}' from ${CADDYFILE}."
  else
    echo "Error: Failed to remove site configuration from ${CADDYFILE}."
    rm -f "$tmp_file" # Clean up temp file on error
    exit 1
  fi
}

# --- Main Script Logic ---

COMMAND="$1"
shift # Remove command from arguments

case "$COMMAND" in
  add)
    add_site "$@"
    ;;
  remove)
    remove_site "$@"
    ;;
  *)
    echo "Error: Invalid command '$COMMAND'."
    usage
    ;;
esac

exit 0