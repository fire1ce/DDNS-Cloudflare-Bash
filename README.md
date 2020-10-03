# Cloudflare DDNS - Simple Bash Script

[![contributions welcome](https://img.shields.io/badge/contributions-welcome-brightgreen.svg?style=flat)](https://github.com/fire1ce/3os.org/tree/master/src)
[![MIT license](https://img.shields.io/badge/License-MIT-blue.svg)](https://mit-license.org/)

Cloudflare DDNS bash Script for most __Linux__ distributions and __MacOS__.  
Choose any source IP address to update  __external__ or __internal__  _(WAN/LAN)_.  
Cloudflare's options proxy and TTL configurable via the parameters.

## Requirements

*   curl
*   [api-token](https://dash.cloudflare.com/profile/api-tokens) with ZONE-DNS-EDIT Permissions
*   DNS Record must be pre created (api-token should only edit dns records)

## Installation

```bash
wget https://raw.githubusercontent.com/fire1ce/cloudflareDDNS-Bash/main/updateDNS.sh
sudo chmod +x updateDNS.sh
sudo mv updateDNS.sh /usr/local/bin/updateDNS
```

## Parameters

Update the config parameters at

```bash
/usr/local/bin/updateDNS
```

| __Option__           | __Example__                              | __Description__                                           |
|----------------------|------------------------------------------|-----------------------------------------------------------|
| what_ip              | internal                                 | Which IP should be used for the record: internal/external |
| what_interface       | eth0                                     | For internal IP, provide interface name                   |
| dns_record           | ddns.example.com                         | DNS __A__ record which will be updated                    |
| zoneid               | 8f340afd4f64f88d55fbe0b3a8813deb         | Cloudflare's Zone ID                                      |
| proxied              | false                                    | Use Cloudflare proxy on dns record true/false             |
| ttl                  | 120                                      | 120-7200 in seconds or 1 for Auto                         |
| cloudflare_api_token | x8AJcit7YtAhUQ8EzPoDE_UkLoPR3XsoafAE3zZ4 | Cloudflare API Token __KEEP IT PRIVET!!!!__               |

## Running The Script

```bash
updateDNS
```

## Automation With Crontab

You can run the script via crontab

```bash
crontab -e
```

Here are some Example

Run every minute

```bash
* * * * * /usr/local/bin/updateDNS
```

Run at boot

```bash
@reboot /usr/local/bin/updateDNS
```

Run 1 minute fater boot

```bash
@reboot sleep 60 && /usr/local/bin/updateDNS
```

Run at 08:00

```bash
0 8 * * * /usr/local/bin/updateDNS
```

## Logs

This Script will create a log file with __only__ the last run information
Log file will be located at

```bash
/usr/local/bin/.updateDNS.log
```

## License

### MIT License

Copyright© 3os.org @2020

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to
deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
IN THE SOFTWARE.
