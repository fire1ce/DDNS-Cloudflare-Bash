#!/usr/bin/env bash
export PATH=/sbin:/opt/bin:/usr/local/bin:/usr/contrib/bin:/bin:/usr/bin:/usr/sbin:/usr/bin/X11

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

### Validate if config file exists
if ! source ${parent_path}/update-cloudflare-dns.conf; then
  echo 'Error! Missing "update-cloudflare-dns.conf or invalid syntax"!'
  exit 0
fi

### Check validity of "ttl" parameter
if [ "${ttl}" -lt 120 ] || [ "${ttl}" -gt 7200 ] && [ "${ttl}" -ne 1 ]; then
  echo "Error! ttl out of range (120-7200) or not set to 1"
  exit
fi

### Check validity of "proxied" parameter
if [ "${proxied}" != "false" ] && [ "${proxied}" != "true" ]; then
  echo 'Error! Incorrect "proxied" parameter choose "true" or "false"'
  exit 0
fi

### Check validity of "what_ip" parameter
if [ "${what_ip}" != "external" ] && [ "${what_ip}" != "internal" ]; then
  echo 'Error! Incorrect "what_ip" parameter choose "external" or "internal"'
  exit 0
fi

### Check if set to internal ip and proxy
if [ "${what_ip}" == "internal" ] && [ "${proxied}" == "true" ]; then
  echo 'Error! Internal IP cannot be Proxied'
  exit 0
fi

### Get External ip from https://checkip.amazonaws.com
if [ "${what_ip}" == "external" ]; then
  ip=$(curl -s -X GET https://checkip.amazonaws.com --max-time 10)
  if [ -z "$ip" ]; then
    echo "Error! Can't get external ip from https://checkip.amazonaws.com"
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
  ### if no "IP" command use "ifconfig", get the ip from interface
  else
    ### "route get" (macOS, Freebsd)
    interface=$(route get 1.1.1.1 | awk '/interface:/ { print $2 }')
    ip=$(ifconfig ${interface} | grep 'inet ' | awk '{print $2}')
  fi
  if [ -z "$ip" ]; then
    echo "Error! Can't read ip from ${interface}"
    exit 0
  fi
  echo "==> Internal ${interface} IP is: $ip"
fi

### Get IP address of DNS record from 1.1.1.1 DNS server when proxied is "false"
if [ "${proxied}" == "false" ]; then
  dns_record_ip=$(host -t A ${dns_record} 1.1.1.1 | awk '/has address/ { print $4 }' | sed -n '1p')
  if [ -z "$dns_record_ip" ]; then
    echo "Error! Can't resolve the ${dns_record} via 1.1.1.1 DNS server"
    exit 0
  fi
  is_proxed="${proxied}"
fi

### Get the dns record id and current proxy status from cloudflare's api when proxied is "true"
if [ "${proxied}" == "true" ]; then
  dns_record_info=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?name=$dns_record" \
    -H "Authorization: Bearer $cloudflare_zone_api_token" \
    -H "Content-Type: application/json")
  if [[ ${dns_record_info} == *"\"success\":false"* ]]; then
    echo ${dns_record_info}
    echo "Error! Can't get dns record info from cloudflare's api"
    exit 0
  fi
  is_proxed=$(echo ${dns_record_info} | grep -o '"proxied":[^,]*' | grep -o '[^:]*$')
  dns_record_ip=$(echo ${dns_record_info} | grep -o '"content":"[^"]*' | cut -d'"' -f 4)
fi

### Check if ip or proxy have changed

if [ ${dns_record_ip} == ${ip} ] && [ ${is_proxed} == ${proxied} ]; then
  echo "==> DNS record IP of ${dns_record} is ${dns_record_ip}", no changes needed. Exiting...
  exit
fi

echo "==> DNS record of ${dns_record} is: ${dns_record_ip}. Trying to update..."

### Get the dns record information from cloudflare's api
cloudflare_record_info=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?name=$dns_record" \
  -H "Authorization: Bearer $cloudflare_zone_api_token" \
  -H "Content-Type: application/json")
if [[ ${cloudflare_record_info} == *"\"success\":false"* ]]; then
  echo ${cloudflare_record_info}
  echo "Error! Can't get ${dns_record} record inforamiton from cloudflare API"
  exit 0
fi

### Get the dns record id from response
cloudflare_dns_record_id=$(echo ${cloudflare_record_info} | grep -o '"id":"[^"]*' | cut -d'"' -f4)

### Push new dns record information to cloudflare's api
update_dns_record=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records/$cloudflare_dns_record_id" \
  -H "Authorization: Bearer $cloudflare_zone_api_token" \
  -H "Content-Type: application/json" \
  --data "{\"type\":\"A\",\"name\":\"$dns_record\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxied}")
if [[ ${update_dns_record} == *"\"success\":false"* ]]; then
  echo ${update_dns_record}
  echo "Error! Update Failed"
  exit 0
fi

echo "==> Success!"
echo "==> $dns_record DNS Record Updated To: $ip, ttl: $ttl, proxied: $proxied"

### Telegram notification
if [ ${notify_me_telegram} == "no" ]; then
  exit 0
fi

if [ ${notify_me_telegram} == "yes" ]; then
  telegram_notification=$(
    curl -s -X GET "https://api.telegram.org/bot${telegram_bot_API_Token}/sendMessage?chat_id=${telegram_chat_id}" --data-urlencode "text=${dns_record} DNS record updated to: ${ip}"
  )
  if [[ ${telegram_notification=} == *"\"ok\":false"* ]]; then
    echo ${telegram_notification=}
    echo "Error! Telegram notification failed"
    exit 0
  fi
fi
