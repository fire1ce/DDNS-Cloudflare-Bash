#!/usr/bin/env bash
export PATH=/sbin:/opt/bin:/usr/local/bin:/usr/contrib/bin:/bin:/usr/bin:/usr/sbin:/usr/bin/X11
proxied="false"
dns_record="oscar.3os.re"

### Get IP address of DNS record from 1.1.1.1 DNS server when proxied is "false"
if [ "${proxied}" == "false" ]; then
  ### Check if "nsloopup" command is present
  if which nslookup >/dev/null; then
    dns_record_ip=$(nslookup ${dns_record} 1.1.1.1 | awk '/Address/ { print $2 }' | sed -n '2p')
  else
    ### if no "nslookup" command use "host" command
    dns_record_ip=$(host -t A ${dns_record} 1.1.1.1 | awk '/has address/ { print $4 }' | sed -n '1p')
  fi

  if [ -z "$dns_record_ip" ]; then
    echo "Error! Can't resolve the ${dns_record} via 1.1.1.1 DNS server"
    exit 0
  fi
  is_proxed="${proxied}"
fi

echo $dns_record_ip
