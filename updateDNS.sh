#!/usr/bin/env bash
export PATH=/sbin:/opt/bin:/usr/local/bin:/usr/contrib/bin:/bin:/usr/bin:/usr/sbin:/usr/bin/X11

## A bash script to update a Cloudflare DNS A record with the External or Internal IP of the source machine ##
## DNS record MUST pre-creating on Cloudflare

##### Config Params
what_ip="internal"                   ##### Which IP should be used for the record: internal/external
what_interface="eth0"                ##### For internal IP, provide interface name
dns_record="ddns.example.com"        ##### DNS A record which will be updated
zoneid="ChangeMe"                    ##### Cloudflare's Zone ID
proxied="false"                      ##### Use Cloudflare proxy on dns record true/false
ttl=120                              ##### 120-7200 in seconds or 1 for Auto
cloudflare_zone_api_token="ChangeMe" ##### Cloudflare API Token keep it private!!!!

#### Telegram Notifications (Optional)
notify_me_telegram="no"           ##### yes/no
telegram_chat_id="ChangeMe"       ##### Telegram Chat ID
telegram_bot_API_Token="ChangeMe" ##### Telegram Bot API Key

#### Email Notifications (Optional)
notify_me_email="no"            ##### yes/no (yes requires mailutils package installed/configured)
notify_email="ddns@example.com" ##### enter your email address (email is only sent if DNS is updated)

##### .updateDNS.log file of the last run for debug
parent_path="$(dirname "${BASH_SOURCE[0]}")"
FILE=${parent_path}/.updateDNS.log
if ! [ -x "$FILE" ]; then
  touch "$FILE"
fi

LOG_FILE=${parent_path}'/.updateDNS.log' #log file name
exec > >(tee $LOG_FILE) 2>&1             # Writes STDOUT & STDERR as log file and prints to screen
echo "==> $(date "+%Y-%m-%d %H:%M:%S")"

##### Get the current IP addresss of the interface
if [ "${what_ip}" == "external" ]; then
  ip=$(curl -s -X GET https://checkip.amazonaws.com)
else
  if [ "${what_ip}" == "internal" ]; then
    if which ip >/dev/null; then
      ip=$(ip -o -4 addr show ${what_interface} scope global | awk '{print $4;}' | cut -d/ -f 1)
    else
      ip=$(ifconfig ${what_interface} | grep 'inet ' | awk '{print $2}')
    fi
  else
    echo "missing or incorrect what_ip/what_interface parameter"
  fi
fi

echo "==> Current IP is: $ip"

#### function to get IP address from DNS server
function get_ipaddr {
  # use host command for DNS lookup operations
  queryhost="host -t A ${dns_record} 1.1.1.1"
  ${queryhost} &>/dev/null
  if [ "$?" -eq "0" ]; then
    # get ip address from dns server
    ip_address="$(${queryhost} | awk '/has.*address/{print $NF; exit}')"
    echo $ip_address
  else
    echo "Error resolving the domain!!!"
    exit 1
  fi
}
dns_record_ip="$(get_ipaddr)"

if [[ ${dns_record_ip} == ${ip} ]] || [[ -z "${ip}" ]]; then
  echo "==> No changes! DNS record of ${dns_record} is: $dns_record_ip"
  exit
else
  echo "==> DNS record of ${dns_record} is: $dns_record_ip". Updating!!!
fi

##### updates the dns record
dns_record_info=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records?name=$dns_record" \
  -H "Authorization: Bearer $cloudflare_zone_api_token" \
  -H "Content-Type: application/json")

dns_record_id=$(echo ${dns_record_info} | grep -o '"id":"[^"]*' | cut -d'"' -f4)

update=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zoneid/dns_records/$dns_record_id" \
  -H "Authorization: Bearer $cloudflare_zone_api_token" \
  -H "Content-Type: application/json" \
  --data "{\"type\":\"A\",\"name\":\"$dns_record\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxied}")

if [[ ${update} == *"\"success\":false"* ]]; then
  echo -e "==> FAILED:\n$update"
  exit 1
else
  echo "==> $dns_record DNS Record Updated To: $ip"
  if [ ${notify_me_email} != "no" ]; then
    mail -s "ip address changed & DNS updated" ${notify_email} </usr/local/bin/.updateDNS.log
  fi
  if [ ${notify_me_telegram} != "no" ]; then
    curl -G "https://api.telegram.org/bot${telegram_bot_API_Token}/sendMessage?chat_id=${telegram_chat_id}" --data-urlencode "text=${dns_record} DNS Record Updated To: ${ip}"
  fi
fi
