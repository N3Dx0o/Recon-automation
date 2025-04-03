#!/bin/bash

# Prompt for domain input
read -p "Enter the target domain: " DOMAIN

# Exit if empty
if [[ -z "$DOMAIN" ]]; then
    echo "[!] No domain provided. Exiting."
    exit 1
fi

# Output setup
OUTDIR="recon_$DOMAIN"
mkdir -p "$OUTDIR"

SUBLIST3R_FILE="$OUTDIR/sublist3r.txt"
CRT_FILE="$OUTDIR/crtsh.txt"
AMASS_FILE="$OUTDIR/amass.txt"
ASSETFINDER_FILE="$OUTDIR/assetfinder.txt"
SUBFINDER_FILE="$OUTDIR/subfinder.txt"
GITHUB_FILE="$OUTDIR/github-subdomains.txt"
COMBINED_FILE="$OUTDIR/all_unique_subdomains.txt"
LIVE_FILE="$OUTDIR/live_domains.txt"
CLEAN_LIVE_URLS="$OUTDIR/clean_live_urls.txt"
RESOLVED_FILE="$OUTDIR/resolved_ips.txt"
UNIQUE_IPS="$OUTDIR/unique_ips.txt"
GAU_FILE="$OUTDIR/gau_output.txt"
WAYBACK_FILE="$OUTDIR/waybackurls_output.txt"
PORT_SCAN_RESULTS="$OUTDIR/fast_scan_results.txt"

echo -e "\n[*] Enumerating subdomains for: $DOMAIN"
echo "------------------------------------------"

### Sublist3r ###
echo "[*] Running Sublist3r..."
sublist3r -d "$DOMAIN" -o "$SUBLIST3R_FILE"
[[ ! -s "$SUBLIST3R_FILE" ]] && echo "[!] Sublist3r found no results or failed."

### crt.sh ###
echo "[*] Fetching subdomains from crt.sh..."
curl -s "https://crt.sh/?q=%25.$DOMAIN&output=json" |
    jq -r '.[].name_value' 2>/dev/null |
    sed 's/\*\.//g' |
    sort -u > "$CRT_FILE"
[[ ! -s "$CRT_FILE" ]] && echo "[!] crt.sh found no results or failed."

### Assetfinder ###
echo "[*] Running Assetfinder..."
assetfinder --subs-only "$DOMAIN" > "$ASSETFINDER_FILE"
[[ ! -s "$ASSETFINDER_FILE" ]] && echo "[!] Assetfinder found no results or failed."

### Subfinder ###
echo "[*] Running Subfinder..."
subfinder -d "$DOMAIN" -silent -o "$SUBFINDER_FILE"
[[ ! -s "$SUBFINDER_FILE" ]] && echo "[!] Subfinder found no results or failed."

### GitHub Subdomains ###
echo "[*] Running github-subdomains..."
github-subdomains -d "$DOMAIN" -t YOUR_GITHUB_TOKEN_HERE 2>/dev/null |
    grep -oP "\b(?:[\w.-]+\.)?$DOMAIN\b" |
    grep -v "^$DOMAIN$" |
    sort -u > "$GITHUB_FILE"
[[ ! -s "$GITHUB_FILE" ]] && echo "[!] github-subdomains found no results or failed."

### Amass ###
echo "[*] Running Amass (passive)..."
amass enum -passive -d "$DOMAIN" -max-dns-queries 300 -timeout 5 -o "$AMASS_FILE"
[[ ! -s "$AMASS_FILE" ]] && echo "[!] Amass found no results or failed."

### Combine and deduplicate ###
echo "[*] Merging and deduplicating subdomains..."
cat "$SUBLIST3R_FILE" "$CRT_FILE" "$AMASS_FILE" "$ASSETFINDER_FILE" "$SUBFINDER_FILE" "$GITHUB_FILE" |
    sed -r 's/\x1B\[[0-9;]*[mK]//g' |
    grep -Eo "[a-zA-Z0-9._-]+\.$DOMAIN" |
    sort -u > "$COMBINED_FILE"

TOTAL_SUBS=$(wc -l < "$COMBINED_FILE")
echo "[+] Total unique subdomains: $TOTAL_SUBS"

[[ "$TOTAL_SUBS" -eq 0 ]] && echo "[!] No subdomains to process. Exiting." && exit 1

### httpx ###
echo -e "\n[*] Probing live subdomains with httpx (HTTP & HTTPS)..."
httpx -l "$COMBINED_FILE" \
      -silent \
      -status-code \
      -title \
      -tech-detect \
      -follow-redirects \
      -ports 80,443 \
      -s http,https \
      -timeout 10 | tee "$LIVE_FILE"

echo "[+] Live subdomains saved to: $LIVE_FILE"

### dnsx ###
echo -e "\n[*] Resolving ALL subdomains with dnsx (domain >> IP)..."
> "$RESOLVED_FILE"
while read -r DOMAIN_ENTRY; do
    IP=$(echo "$DOMAIN_ENTRY" | dnsx -silent -a -resp-only)
    if [[ -n "$IP" ]]; then
        echo "$DOMAIN_ENTRY >> $IP" | tee -a "$RESOLVED_FILE"
    fi
done < "$COMBINED_FILE"

echo -e "\n[+] DNS resolutions saved to: $RESOLVED_FILE"

### Extract unique IPs only ###
echo -e "\n[*] Extracting unique IPs from DNS results..."
awk -F '>>' '{gsub(/ /, "", $2); print $2}' "$RESOLVED_FILE" | sort -u > "$UNIQUE_IPS"
IP_COUNT=$(wc -l < "$UNIQUE_IPS")
echo "[+] Unique IPs saved to: $UNIQUE_IPS ($IP_COUNT IPs)"

### Extract clean URLs ###
echo -e "\n[*] Extracting clean URLs from httpx output..."
cut -d ' ' -f 1 "$LIVE_FILE" | sort -u > "$CLEAN_LIVE_URLS"
echo "[+] Clean URLs saved to: $CLEAN_LIVE_URLS"

### waybackurls ###
echo -e "\n[*] Running waybackurls on live URLs..."
cat "$CLEAN_LIVE_URLS" | waybackurls | sort -u > "$WAYBACK_FILE"
echo "[+] Wayback URLs saved to: $WAYBACK_FILE"

### gau ###
echo -e "\n[*] Running gau (GetAllUrls) on live URLs..."
cat "$CLEAN_LIVE_URLS" | gau --subs | sort -u > "$GAU_FILE"
echo "[+] gau output saved to: $GAU_FILE"

### Merge waybackurls and gau results ###
echo -e "\n[*] Merging waybackurls and gau results, removing duplicates..."
cat "$WAYBACK_FILE" "$GAU_FILE" | sort -u > "$OUTDIR/all_urls_combined.txt"
echo "[+] Combined unique URLs saved to: $OUTDIR/all_urls_combined.txt"

echo -e "\n[*] Filtering combined URLs with urless for interesting endpoints..."
urless -i "$OUTDIR/all_urls_combined.txt" \
       -o "$OUTDIR/interesting_urls_from_gau_and_Waybackurls.txt" \
       -fe jpg,jpeg,png,gif,svg,webp,css,woff,woff2,ttf,ico,eot,otf,map,html,htm,swf,gif,bmp \
       -fk login,logout,signup,register
echo "[+] Filtered interesting URLs saved to: $OUTDIR/interesting_urls.txt"


### Port Scan with RustScan ###
if [[ "$IP_COUNT" -eq 0 ]]; then
    echo "[!] No IPs found. Skipping port scan."
else
    echo -e "\n[*] Running RustScan on discovered IPs..."
    COMMON_PORTS="21,22,23,25,53,69,80,110,111,123,135,137,138,139,143,161,389,443,445,512,513,514,587,631,636,873,990,993,995,1080,1433,1521,1723,2049,2082,2083,2181,2222,2375,2379,3306,3389,4443,5000,5432,5900,5984,5985,5986,6379,7001,7002,8080,8081,8089,8443,8888,9200,9300,10000,11211,27017"
    rustscan --ulimit 5000 -a "$UNIQUE_IPS" -p "$COMMON_PORTS" --timeout 350 -g > "$PORT_SCAN_RESULTS"
    echo "[+] Fast port scan results saved to: $PORT_SCAN_RESULTS"
fi
echo "------------------------------------------"
echo "[✔] Done! Results saved in: $OUTDIR"
