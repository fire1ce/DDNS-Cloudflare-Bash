# DDNS Cloudflare Bash Script

[![contributions welcome](https://img.shields.io/badge/contributions-welcome-brightgreen.svg?style=flat)](https://github.com/fire1ce/3os.org/tree/master/src)
[![MIT license](https://img.shields.io/badge/License-MIT-blue.svg)](https://mit-license.org/)

## About

- DDNS Cloudflare Bash Script for most **Linux**, **Unix** distributions and **MacOS**.
- Choose any source IP address to update **external** or **internal** _(WAN/LAN)_.
- For multiply lan interfaces like Wifi, Docker Networks and Bridges the script will automatically detects the primary Interface by priority.
- Cloudflare's options proxy and TTL configurable via the config file.
- Optional Telegram Notifications

## Requirements

- curl
- Cloudflare [api-token](https://dash.cloudflare.com/profile/api-tokens) with ZONE-DNS-EDIT Permissions
- DNS Record must be pre created (api-token should only edit dns records)

## Installation

You can place the script at any location manually.

**MacOS**: Don't use the _/usr/local/bin/_ for the script location. Create a separate folder under your user path _/Users/${USER}_

The automatic install examples below will place the script at _/usr/local/bin/_

```shell
wget https://raw.githubusercontent.com/fire1ce/DDNS-Cloudflare-Bash/main/update-cloudflare-dns.sh
sudo chmod +x update-cloudflare-dns.sh
sudo mv update-cloudflare-dns.sh /usr/local/bin/update-cloudflare-dns
```

Config file download

```shell
wget https://raw.githubusercontent.com/fire1ce/DDNS-Cloudflare-Bash/main/update-cloudflare-dns.conf
```

Place the **config** file in the directory as the **update-cloudflare-dns** for above example at _/usr/local/bin/_

```shell
sudo mv update-cloudflare-dns.conf /usr/local/bin/update-cloudflare-dns.conf
```

## Config Parameters

| **Option**                | **Example**      | **Description**                                           |
| ------------------------- | ---------------- | --------------------------------------------------------- |
| what_ip                   | internal         | Which IP should be used for the record: internal/external |
| dns_record                | ddns.example.com | DNS **A** record which will be updated                    |
| cloudflare_zone_api_token | ChangeMe         | Cloudflare API Token **KEEP IT PRIVET!!!!**               |
| zoneid                    | ChangeMe         | Cloudflare's Zone ID                                      |
| proxied                   | false            | Use Cloudflare proxy on dns record true/false             |
| ttl                       | 120              | 120-7200 in seconds or 1 for Auto                         |

### Optional Notifications Parameters

| **Option**             | **Example** | **Description**                   |
| ---------------------- | ----------- | --------------------------------- |
| notify_me_telegram     | yes         | Use Telegram notifications yes/no |
| telegram_chat_id       | ChangeMe    | Chat ID of the bot                |
| telegtam_bot_API_Token | ChangeMe    | Telegtam's Bot API Token          |

## Running The Script

When placed in _/usr/local/bin/_

```shell
update-cloudflare-dns
```

Or manually

```shell
<path>/.update-cloudflare-dns.sh
```

## Automation With Crontab

You can run the script via crontab

```shell
crontab -e
```

### Examples

Run every minute

```shell
* * * * * /usr/local/bin/update-cloudflare-dns
```

Run every 2 minutes

```shell
*/2 * * * * /usr/local/bin/update-cloudflare-dns
```

Run at boot

```shell
@reboot /usr/local/bin/update-cloudflare-dns
```

Run 1 minute after boot

```shell
@reboot sleep 60 && /usr/local/bin/update-cloudflare-dns
```

Run at 08:00

```shell
0 8 * * * /usr/local/bin/update-cloudflare-dns
```

## Logs

This Script will create a log file with **only** the last run information
Log file will be located at the script's location.

Example:

```bash
/usr/local/bin/update-cloudflare-dns.log
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
