#!/usr/bin/env bash

### Initialize error catching variables
error_msg=""
had_error="false"

### Email notification
email_notify () {
  local email_notification=""

  if [ ${notify_me_email} == "yes" ]; then
    if [ ${had_error} == "true" ]; then
      email_notification=$(
        echo "$HOSTNAME error ${error_msg}" |mailx -s "ddns update ${record} failure" ${to_email_address}
      )
    else
      email_notification=$(
        echo "$HOSTNAME updated ${record} DNS record from ${dns_record_ip} to: ${ip}" |mailx -s "ddns update ${record}" ${to_email_address}
      )
    fi
    if [[ ${email_notification} == *"\"ok\":false"* ]]; then
      echo ${email_notification}
      echo "Error! Email notification failed"
    fi
  fi
}

### Telegram notification
telegram_notify () {
  local telegram_notification=""

  if [ ${notify_me_telegram} == "yes" ]; then
    telegram_notification=$(
      curl -s -X GET "https://api.telegram.org/bot${telegram_bot_API_Token}/sendMessage?chat_id=${telegram_chat_id}" --data-urlencode "text=${record} DNS record updated to: ${ip}"
    )
    if [[ ${telegram_notification=} == *"\"ok\":false"* ]]; then
      echo ${telegram_notification=}
      echo "Error! Telegram notification failed"
    fi
  fi
}

###  Create .update-cloudflare-dns.log file of the last run for debug
parent_path="$(dirname "${BASH_SOURCE[0]}")"
FILE=${parent_path}/update-cloudflare-dns.log
if ! [ -x "$FILE" ]; then
  touch "$FILE"
fi

LOG_FILE=${parent_path}'/update-cloudflare-dns.log'

### Write last run of STDOUT & STDERR as log file and prints to screen
exec > >(tee $LOG_FILE) 2>&1
echo "==> $(date "+%Y-%m-%d %H:%M:%S")"

### Validate if config-file exists
if [[ -z "$1" ]]; then
  if ! source ${parent_path}/update-cloudflare-dns.conf; then
    echo 'Error! Missing configuration file update-cloudflare-dns.conf or invalid syntax!'
    exit 0
  fi
else
  if ! source ${parent_path}/"$1"; then
    echo 'Error! Missing configuration file '$1' or invalid syntax!'
    exit 0
  fi
fi

### Check validity of "ttl" parameter
if [ "${ttl}" -lt 120 ] || [ "${ttl}" -gt 7200 ] && [ "${ttl}" -ne 1 ]; then
  had_error="true"
  error_msg="Error! ttl out of range (120-7200) or not set to 1"
  echo $error_msg
  email_notify
  telegram_notify
  exit 0
fi

### Check validity of "proxied" parameter
if [ "${proxied}" != "false" ] && [ "${proxied}" != "true" ]; then
  had_error="true"
  error_msg='Error! Incorrect "proxied" parameter, choose "true" or "false"'
  echo $error_msg
  email_notify
  telegram_notify
  exit 0
fi

### Check validity of "what_ip" parameter
if [ "${what_ip}" != "external" ] && [ "${what_ip}" != "internal" ]; then
  had_error="true"
  error_msg='Error! Incorrect "what_ip" parameter, choose "external" or "internal"'
  echo $error_msg
  email_notify
  telegram_notify
  exit 0
fi

### Check if set to internal ip and proxy
if [ "${what_ip}" == "internal" ] && [ "${proxied}" == "true" ]; then
  had_error="true"
  error_msg='Error! Internal IP cannot be proxied'
  echo $error_msg
  email_notify
  telegram_notify
  exit 0
fi

### Get external ip from https://checkip.amazonaws.com
if [ "${what_ip}" == "external" ]; then
  ip=$(curl -4 -s -X GET https://checkip.amazonaws.com --max-time 10)
  if [ -z "$ip" ]; then
    had_error="true"
    error_msg="Error! Can't get external ip from https://checkip.amazonaws.com"
    echo $error_msg
    email_notify
    telegram_notify
    exit 0
  fi
  echo "==> External IP is: $ip"
fi

### Get Internal ip from primary interface
if [ "${what_ip}" == "internal" ]; then
  ### Check if "IP" command is present, get the ip from interface
  if which ip >/dev/null; then
    ### "ip route get" (linux)
    interface=$(ip route get 1.1.1.1 | awk '/dev/ { print $5 }')
    ip=$(ip -o -4 addr show ${interface} scope global | awk '{print $4;}' | cut -d/ -f 1)
  ### If no "ip" command use "ifconfig" instead, to get the ip from interface
  else
    ### "route get" (macOS, Freebsd)
    interface=$(route get 1.1.1.1 | awk '/interface:/ { print $2 }')
    ip=$(ifconfig ${interface} | grep 'inet ' | awk '{print $2}')
  fi
  if [ -z "$ip" ]; then
    had_error="true"
    error_msg="Error! Can't read ip from ${interface}"
    echo $error_msg
    email_notify
    telegram_notify
    exit 0
  fi
  echo "==> Internal ${interface} IP is: $ip"
fi

### Build coma separated array fron dns_record parameter to update multiple A records
IFS=',' read -d '' -ra dns_records <<<"$dns_record,"
unset 'dns_records[${#dns_records[@]}-1]'
declare dns_records

for record in "${dns_records[@]}"; do
  ### Get IP address of DNS record from 1.1.1.1 DNS server when proxied is "false"
  if [ "${proxied}" == "false" ]; then
    ### Check if "nslookup" command is present
    if which nslookup >/dev/null; then
      dns_record_ip=$(nslookup ${record} 1.1.1.1 | awk '/Address/ { print $2 }' | sed -n '2p')
    else
      ### if no "nslookup" command use "host" command
      dns_record_ip=$(host -t A ${record} 1.1.1.1 | awk '/has address/ { print $4 }' | sed -n '1p')
    fi

    if [ -z "$dns_record_ip" ]; then
      had_error="true"
      error_msg="Error! Can't resolve the ${record} via 1.1.1.1 DNS server"
      echo $error_msg
      email_notify
      telegram_notify
      exit 0
    fi
    is_proxed="${proxied}"
  fi

  ### Get the dns record id and current proxy status from Cloudflare API when proxied is "true"
  if [ "${proxied}" == "true" ]; then
    dns_record_info=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?type=A&name=$record" \
      -H "Authorization: Bearer $cloudflare_zone_api_token" \
      -H "Content-Type: application/json")
    if [[ ${dns_record_info} == *"\"success\":false"* ]]; then
      echo ${dns_record_info}
      had_error="true"
      error_msg="Error! Can't get dns record info from Cloudflare API"
      echo $error_msg
      email_notify
      telegram_notify
      exit 0
    fi
    is_proxed=$(echo ${dns_record_info} | grep -o '"proxied":[^,]*' | grep -o '[^:]*$')
    dns_record_ip=$(echo ${dns_record_info} | grep -o '"content":"[^"]*' | cut -d'"' -f 4)
  fi

  ### Check if ip or proxy have changed
  if [ ${dns_record_ip} == ${ip} ] && [ ${is_proxed} == ${proxied} ]; then
    echo "==> DNS record IP of ${record} is ${dns_record_ip}", no changes needed.
    continue
  fi

  echo "==> DNS record of ${record} is: ${dns_record_ip}. Trying to update..."

  ### Get the dns record information from Cloudflare API
  cloudflare_record_info=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?type=A&name=$record" \
    -H "Authorization: Bearer $cloudflare_zone_api_token" \
    -H "Content-Type: application/json")
  if [[ ${cloudflare_record_info} == *"\"success\":false"* ]]; then
    echo ${cloudflare_record_info}
    had_error="true"
    error_msg="Error! Can't get ${record} record information from Cloudflare API"
    echo $error_msg
    email_notify
    telegram_notify
    exit 0
  fi

  ### Get the dns record id from response
  cloudflare_dns_record_id=$(echo ${cloudflare_record_info} | grep -o '"id":"[^"]*' | cut -d'"' -f4)

  ### Push new dns record information to Cloudflare API
  update_dns_record=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records/$cloudflare_dns_record_id" \
    -H "Authorization: Bearer $cloudflare_zone_api_token" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"$record\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxied}")
  if [[ ${update_dns_record} == *"\"success\":false"* ]]; then
    echo ${update_dns_record}
    had_error="true"
    error_msg="Error! Update failed"
    echo $error_msg
    email_notify
    telegram_notify
    exit 0
  fi

  echo "==> Success!"
  echo "==> $record DNS Record updated to: $ip, ttl: $ttl, proxied: $proxied"

  email_notify
  telegram_notify

done
