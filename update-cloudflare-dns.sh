#!/usr/bin/env bash
# update-cloudflare-dns.sh
#
# Purpose: Update Cloudflare DNS and optionally send a Telegram notification.

# -----------------------------------------------------------------------------
# Strict mode
# -----------------------------------------------------------------------------
set -euo pipefail

# -----------------------------------------------------------------------------
# Lockfile to prevent overlapping runs
# -----------------------------------------------------------------------------
LOCKFILE="/tmp/update-cloudflare-dns.lock"
exec 200>"$LOCKFILE"
if ! flock -n 200; then
  echo "Another instance is running. Exiting."
  exit 1
fi

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

# 1) Check for required dependencies
check_dependencies() {
  local -a deps=("curl" "awk" "sed" "grep" "cut")
  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "Error: Required command '$cmd' is not installed or not in PATH."
      exit 1
    fi
  done

  # Optional commands for DNS resolution (prefer dig > nslookup > host)
  if ! command -v dig &>/dev/null && \
     ! command -v nslookup &>/dev/null && \
     ! command -v host &>/dev/null; then
    echo "Warning: 'dig', 'nslookup', nor 'host' found. DNS resolution may fail if proxied=false."
  fi

  # Optional commands for internal IP detection (ip / ifconfig+route)
  if ! command -v ip &>/dev/null; then
    if ! command -v ifconfig &>/dev/null || ! command -v route &>/dev/null; then
      echo "Warning: 'ip' not found, and either 'ifconfig' or 'route' is missing."
      echo "Cannot reliably fetch internal IP on some systems without these."
    fi
  fi
}

# 2) Determine config & log paths based on root vs non-root
init_paths() {
  if [ "$EUID" -eq 0 ]; then
    CONFIG_DIR="/etc/update-cloudflare-dns"
    LOG_FILE="/var/log/update-cloudflare-dns.log"
  else
    CONFIG_DIR="$HOME/.update-cloudflare-dns"
    LOG_FILE="$CONFIG_DIR/update-cloudflare-dns.log"
  fi
  export CONFIG_DIR LOG_FILE
}

# 3) Initialize logging
init_logging() {
  # Create config/log dirs if needed
  if [ "$EUID" -ne 0 ] && [ ! -d "$CONFIG_DIR" ]; then
    mkdir -p "$CONFIG_DIR"
  fi

  if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
  fi

  # Redirect stdout/stderr to both screen and the log file (append mode)
  exec > >(tee -a "$LOG_FILE") 2>&1
  echo "==> $(date +'%Y-%m-%d %H:%M:%S')"
}

# 4) Load config file
load_config() {
  if [[ -z "${1:-}" ]]; then
    CONFIG_FILE="$CONFIG_DIR/update-cloudflare-dns.conf"
  else
    # If you want to force configs into CONFIG_DIR, uncomment:
    # CONFIG_FILE="$CONFIG_DIR/$1"
    CONFIG_FILE="$1"
  fi

  if ! source "$CONFIG_FILE" 2>/dev/null; then
    echo "Error! Missing or invalid config file: $CONFIG_FILE"
    exit 1
  fi
}

# 5) Validate config parameters (ttl, proxied, what_ip, etc.)
validate_config() {
  # Check TTL
  if [ "$ttl" -lt 120 ] || [ "$ttl" -gt 7200 ] && [ "$ttl" -ne 1 ]; then
    echo "Error! ttl out of range (120-7200) or not set to 1"
    exit 1
  fi

  # Check proxied
  if [ "$proxied" != "false" ] && [ "$proxied" != "true" ]; then
    echo 'Error! "proxied" must be "true" or "false"'
    exit 1
  fi

  # Check what_ip
  if [ "$what_ip" != "external" ] && [ "$what_ip" != "internal" ]; then
    echo 'Error! "what_ip" must be "external" or "internal"'
    exit 1
  fi

  # If internal IP, cannot be proxied
  if [ "$what_ip" == "internal" ] && [ "$proxied" == "true" ]; then
    echo 'Error! Internal IP cannot be proxied'
    exit 1
  fi
}

# 6) Fetch IP address (external or internal)
fetch_ip() {
  local mode="$1"

  # IPv4 regex
  local REIP='^((25[0-5]|(2[0-4]|1[0-9]|[1-9]|)[0-9])\.){3}(25[0-5]|(2[0-4]|1[0-9]|[1-9]|)[0-9])$'

  if [ "$mode" == "external" ]; then
    # First try checkip.amazonaws.com
    ip=$(curl -4 -s -X GET https://checkip.amazonaws.com --max-time 10 || true)

    if [ -z "$ip" ]; then
      echo "Warning! Cannot get external IP from checkip.amazonaws.com, trying ifconfig.me..."
      # If that fails, try ifconfig.me
      ip=$(curl -4 -s -X GET https://ifconfig.me --max-time 10 || true)

      if [ -z "$ip" ]; then
        echo "Error! Failed to get external IP from both checkip.amazonaws.com and ifconfig.me"
        exit 1
      fi
    fi

    # Validate we got a proper IPv4 address
    if ! [[ "$ip" =~ $REIP ]]; then
      echo "Error! IP Address returned was invalid: $ip"
      exit 1
    fi
    echo "==> External IP is: $ip"
  else
    # Attempt to use 'ip' command
    if command -v ip &>/dev/null; then
      interface=$(ip route get 1.1.1.1 | awk '/dev/ { print $5 }')
      ip=$(ip -o -4 addr show "${interface}" scope global | awk '{print $4}' | cut -d/ -f1)
    else
      # Fallback to 'route get' + 'ifconfig' (macOS/FreeBSD)
      interface=$(route get 1.1.1.1 | awk '/interface:/ { print $2 }')
      ip=$(ifconfig "${interface}" | grep 'inet ' | awk '{print $2}')
    fi

    if [ -z "${ip:-}" ]; then
      echo "Error! Cannot read IP from interface $interface"
      exit 1
    fi
    echo "==> Internal $interface IP is: $ip"
  fi
}

# 7) Update DNS record
update_dns_record() {
  local record="$1"
  local dns_record_ip=""

  # If proxied=false, check current DNS record IP from 1.1.1.1
  if [ "$proxied" == "false" ]; then
    if command -v dig &>/dev/null; then
      # Use +short to get just the IP(s). We take the first line for safety.
      dns_record_ip=$(dig +short A "$record" @1.1.1.1 | grep -v '^;' | head -n1)
    elif command -v nslookup &>/dev/null; then
      dns_record_ip=$(nslookup "$record" 1.1.1.1 | awk '/Address/ { print $2 }' | sed -n '2p')
    else
      # Fallback to host
      dns_record_ip=$(host -t A "$record" 1.1.1.1 | awk '/has address/ { print $4 }' | sed -n '1p')
    fi

    if [ -z "$dns_record_ip" ]; then
      echo "Error! Can't resolve $record via 1.1.1.1"
      exit 1
    fi
    is_proxed="$proxied"
  else
    # If proxied=true, check current info from Cloudflare
    dns_record_info=$(curl -s -X GET \
      "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?type=A&name=$record" \
      -H "Authorization: Bearer $cloudflare_zone_api_token" \
      -H "Content-Type: application/json")

    if [[ "$dns_record_info" == *"\"success\":false"* ]]; then
      echo "$dns_record_info"
      echo "Error! Cannot get DNS record info from Cloudflare API for $record"
      exit 1
    fi

    is_proxed=$(echo "$dns_record_info" | grep -o '"proxied":[^,]*' | grep -o '[^:]*$')
    dns_record_ip=$(echo "$dns_record_info" | grep -o '"content":"[^"]*' | cut -d'"' -f4)
  fi

  # Check if we actually need to update
  if [ "$dns_record_ip" == "$ip" ] && [ "$is_proxed" == "$proxied" ]; then
    echo "==> DNS record $record is already [$dns_record_ip], proxied=$is_proxed. No changes needed."
    return 0
  fi

  echo "==> DNS record of $record is: $dns_record_ip. Trying to update..."

  # Fetch the record ID from Cloudflare
  cloudflare_record_info=$(curl -s -X GET \
    "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?type=A&name=$record" \
    -H "Authorization: Bearer $cloudflare_zone_api_token" \
    -H "Content-Type: application/json")

  if [[ "$cloudflare_record_info" == *"\"success\":false"* ]]; then
    echo "$cloudflare_record_info"
    echo "Error! Cannot get $record record information from Cloudflare API"
    exit 1
  fi

  cloudflare_dns_record_id=$(echo "$cloudflare_record_info" | grep -o '"id":"[^"]*' | cut -d'"' -f4)

  # Update DNS record
  update_dns_record_resp=$(curl -s -X PUT \
    "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records/$cloudflare_dns_record_id" \
    -H "Authorization: Bearer $cloudflare_zone_api_token" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"$record\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxied}")

  if [[ "$update_dns_record_resp" == *"\"success\":false"* ]]; then
    echo "$update_dns_record_resp"
    echo "Error! Update failed for $record"
    exit 1
  fi

  echo "==> Success!"
  echo "==> $record DNS Record updated to: $ip, ttl: $ttl, proxied: $proxied"

  # Telegram notification
  if [ "$notify_me_telegram" == "yes" ]; then
    # Build topic parameter if telegram_topic_id is set
    # (i.e., if the variable exists and is not empty).
    if [ -n "${telegram_topic_id:-}" ]; then
      TOPIC_PARAM="&message_thread_id=${telegram_topic_id}"
    else
      TOPIC_PARAM=""
    fi

    telegram_notification=$(
      curl -s -X GET \
        "https://api.telegram.org/bot${telegram_bot_API_Token}/sendMessage?chat_id=${telegram_chat_id}${TOPIC_PARAM}" \
        --data-urlencode "text=${record} DNS record updated to: ${ip}"
    )

    if [[ "$telegram_notification" == *"\"ok\":false"* ]]; then
      echo "$telegram_notification"
      echo "Error! Telegram notification failed"
      exit 1
    fi
  fi
}

# 8) Main logic
main() {
  check_dependencies
  init_paths
  init_logging
  load_config "${1:-}"     # pass $1 if present
  validate_config
  fetch_ip "$what_ip"

  # Split comma-separated DNS records into array
  IFS=',' read -r -a dns_records <<< "$dns_record"
  for record in "${dns_records[@]}"; do
    record="$(echo "$record" | xargs)"  # Trim whitespace
    update_dns_record "$record"
  done
}

# -----------------------------------------------------------------------------
# Execute main
# -----------------------------------------------------------------------------
main "$@"

exit 0
