> [!CAUTION]
> This script was built with the help of DeepSeek and manually tested by me.
> While it has been tested in controlled environments, **do not run it in production servers unless you are fully sure of what you are doing**.
> It may modify or migrate server data, so use it responsibly and always keep backups.

# CPanel to Plesk
Script to migrate AWStats statistics from cPanel to Plesk.
Forked from plesk/kb-scripts, Edited by sshtmp.

## Usage
```
./prepare-awstats.sh destination_domain [-s source_domain] [-p search_pattern] [-h]
```

## Arguments
```
  destination_domain    Domain in Plesk (required)
  -s source_domain      Source domain where to search tmp files (optional)
  -p search_pattern     Manually override the search pattern (e.g., old domain name in files)
  -h                    Show this help
```

## How to use

### 1. Prepare the files
Export the tmp directory from cPanel (usually a zip file). Upload and extract it on the Plesk server so that the AWStats .txt files are placed at:

```
/var/www/vhosts/[SOURCE-DOMAIN]/tmp/awstats/
/var/www/vhosts/[SOURCE-DOMAIN]/tmp/awstats/ssl/
```

Example (after extracting the zip):
```
mkdir -p /var/www/vhosts/maindomain.com/tmp/awstats/ssl
cp /path/to/extracted/awstats/*.txt /var/www/vhosts/maindomain.com/tmp/awstats/
cp /path/to/extracted/awstats/ssl/*.txt /var/www/vhosts/maindomain.com/tmp/awstats/ssl/
```

### 2. Run the script

Case 1: Files are on the same destination domain
```
./prepare-awstats.sh mydomain.com
``` 

Case 2: Files are on a different domain (e.g., a main account that contained addons)
```
./prepare-awstats.sh mydomain.com -s mainaccount.com
```

### 3. Repeat for each domain
```
./prepare-awstats.sh domain1.com -s mainaccount.com
./prepare-awstats.sh domain2.net -s mainaccount.com
./prepare-awstats.sh domain3.org -s mainaccount.com
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