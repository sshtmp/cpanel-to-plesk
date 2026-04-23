> [!CAUTION]
> This script was built with the help of DeepSeek and manually tested by me.
> While it has been tested in controlled environments, **do not run it in production servers unless you are fully sure of what you are doing**.
> It may modify or migrate server data, so use it responsibly and always keep backups.
# CPanel to Plesk
Script to migrate AWStats statistics from cPanel to Plesk.
Forked from plesk/kb-scripts, Edited by sshtmp.

## Usage
```
./prepare-awstats.sh -P domain.com [-s source-domain.com]
```

## Arguments
```
-P   Destination domain in Plesk (required)
-s   Domain where tmp files are located (optional, if different from destination)
-h   Show help
```

## How to use
### 1. Prepare the files
Copy the AWStats files from cPanel backup to this location on the Plesk server:
```
/var/www/vhosts/[SOURCE-DOMAIN]/tmp/awstats/
/var/www/vhosts/[SOURCE-DOMAIN]/tmp/awstats/ssl/
```
Example:
```bash
mkdir -p /var/www/vhosts/maindomain.com/tmp/awstats/ssl
cp /backup/awstats/*.txt /var/www/vhosts/maindomain.com/tmp/awstats/
cp /backup/awstats/ssl/*.txt /var/www/vhosts/maindomain.com/tmp/awstats/ssl/
```

### 2. Run the script
Case 1: Files are on the same destination domain
```bash
./prepare-awstats.sh -P mydomain.com
```
Case 2: Files are on a different domain (e.g., a main account that contained addons)
```bash
./prepare-awstats.sh -P mydomain.com -s mainaccount.com
```
### 3. Repeat for each domain
```bash
./prepare-awstats.sh -P domain1.com -s mainaccount.com
./prepare-awstats.sh -P domain2.net -s mainaccount.com
./prepare-awstats.sh -P domain3.org -s mainaccount.com
```
### 4. Rebuild statistics
When finished, the script will ask if you want to run rebuild-awstats.sh. Answer 'y' so Plesk processes the files.

## Important paths
```
Source files (HTTP):   /var/www/vhosts/[source-domain]/tmp/awstats/*.txt
Source files (HTTPS):  /var/www/vhosts/[source-domain]/tmp/awstats/ssl/*.txt
Destination (HTTP):    /var/www/vhosts/system/[destination-domain]/statistics/webstat/
Destination (HTTPS):   /var/www/vhosts/system/[destination-domain]/statistics/webstat-ssl/
```

## Notes

- The script only moves files that match the destination domain name
- Files are renamed adding -http.txt or -https.txt suffix
- Original files are removed from the source directory after moving
