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
JSFILES="$OUTDIR/js_files.txt"
JS_ENDPOINTS="$OUTDIR/xnlinkfinder_endpoints.txt"
RESOLVED_FILE="$OUTDIR/resolved_ips.txt"
UNIQUE_IPS="$OUTDIR/unique_ips.txt"
GAU_FILE="$OUTDIR/gau_output.txt"
WAYBACK_FILE="$OUTDIR/waybackurls_output.txt"
NUCLEI_OUTPUT="$OUTDIR/nuclei_results.txt"
IP_NUCLEI_OUTPUT="$OUTDIR/IP_nuclei_results.txt"
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
github-subdomains -d "$DOMAIN" -t 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 2>/dev/null |
    grep -oP "\b(?:[\w.-]+\.)?$DOMAIN\b" |
    grep -v "^$DOMAIN$" |
    sort -u > "$GITHUB_FILE"
[[ ! -s "$GITHUB_FILE" ]] && echo "[!] github-subdomains found no results or failed."

### waybackurls ###
echo -e "\n[*] Running waybackurls to exctract URLs subdomains..."
echo "$DOMAIN" | waybackurls | sort -u > "$WAYBACK_FILE"
echo "[+] Wayback URLs saved to: $WAYBACK_FILE"

### gau ###
echo -e "\n[*] Running gau (GetAllUrls) to extract URLs and subdomains ..."
echo "$DOMAIN" | gau --subs | sort -u > "$GAU_FILE"
echo "[+] gau output saved to: $GAU_FILE"

### Amass ###
echo "[*] Running Amass (passive)..."
amass enum -passive -d "$DOMAIN" -max-dns-queries 300 -timeout 5 -o "$AMASS_FILE"
[[ ! -s "$AMASS_FILE" ]] && echo "[!] Amass found no results or failed."

### Combine and deduplicate ###
echo "[*] Merging and deduplicating subdomains..."
cat "$SUBLIST3R_FILE" "$CRT_FILE" "$AMASS_FILE" "$ASSETFINDER_FILE" "$SUBFINDER_FILE" "$GITHUB_FILE" "$GAU_FILE" "$WAYBACK_FILE" |
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
      -ports 80,443,8080,8443,8001,8888,3000,5000,7002,591,631,6789,1234 \
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
awk -F '>>' '{gsub(/ /, "", $2); print $2}' "$RESOLVED_FILE" | grep -Ev '^$' | sort -u > "$UNIQUE_IPS"
sed -i '/^$/d' "$UNIQUE_IPS"
IP_COUNT=$(wc -l < "$UNIQUE_IPS")
echo "[+] Unique IPs saved to: $UNIQUE_IPS (${IP_COUNT} IPs)"

### Extract clean URLs ###
echo -e "\n[*] Extracting clean URLs from httpx output..."
cut -d ' ' -f 1 "$LIVE_FILE" | sort -u > "$CLEAN_LIVE_URLS"
echo "[+] Clean URLs saved to: $CLEAN_LIVE_URLS"

### getJS ###
echo -e "\n[*] Extracting JavaScript file URLs with getJS..."
cat "$CLEAN_LIVE_URLS" | getJS --complete 2>/dev/null | \
    grep -E "($DOMAIN|^/|^\.\/)" | sort -u > "$JSFILES"
echo "[+] JavaScript URLs saved to: $JSFILES"

### xnLinkFinder: Extract endpoints from JS files ###
echo -e "\n[*] Extracting endpoints from JavaScript files using xnLinkFinder..."
TMP_EP="$OUTDIR/tmp_xn_endpoints.txt"
> "$JS_ENDPOINTS"

# Color codes
BOLD_BLUE='\033[1;34m'
RESET='\033[0m'

if [[ -s "$JSFILES" ]]; then
    while read -r jsurl; do
        # Output to terminal in color
        echo -e "${BOLD_BLUE}[URL] $jsurl${RESET}"

        # Output to file with [URL] in plain text (or you can include color codes too)
        echo -e "[URL] $jsurl" >> "$JS_ENDPOINTS"

        xnLinkFinder -i "$jsurl" -o "$TMP_EP" -sf "$DOMAIN" >/dev/null 2>&1
        if [[ -f "$TMP_EP" && -s "$TMP_EP" ]]; then
            cat "$TMP_EP" >> "$JS_ENDPOINTS"
            echo "[+] Endpoints found in $jsurl"
        else
            echo "[!] No endpoints in $jsurl"
        fi
        rm -f "$TMP_EP"
    done < "$JSFILES"

    echo "[+] Endpoints grouped by JS file saved to: $JS_ENDPOINTS"
else
    echo "[!] No JavaScript files found to analyze with xnLinkFinder."
fi

### SecretFinder: Scan JS files for secrets ###
echo -e "\n[*] Scanning JavaScript files with SecretFinder for secrets and API keys..."
SECRET_OUT="$OUTDIR/secretfinder_results.txt"
> "$SECRET_OUT"

if [[ -s "$JSFILES" ]]; then
    while read -r jsurl; do
        echo -e "\033[1;35m[URL] $jsurl\033[0m"
        echo "[URL] $jsurl" >> "$SECRET_OUT"

        /root/bin/python3 /root/recon/recon_turk.net/SecretFinder/SecretFinder.py \
            -i "$jsurl" -o cli 2>/dev/null >> "$SECRET_OUT"

        echo "----------------------------------------" >> "$SECRET_OUT"
    done < "$JSFILES"

    echo "[+] SecretFinder results saved to: $SECRET_OUT"
else
    echo "[!] No JavaScript files to analyze for secrets."
fi

cat "$CLEAN_LIVE_URLS" | getJS --complete | sort -u > "$JSFILES"

### Merge waybackurls and gau results ###
echo -e "\n[*] Merging waybackurls and gau results, removing duplicates... and making them ready for Urless"
cat "$WAYBACK_FILE" "$GAU_FILE" | sort -u > "$OUTDIR/wayback_gau_combined.txt"
echo "[+] Combined unique URLs saved to: $OUTDIR/wayback_gau_combined.txt"

echo -e "\n[*] Filtering combined URLs with urless for interesting endpoints..."
urless -i "$OUTDIR/wayback_gau_combined.txt" \
       -o "$OUTDIR/interesting_urls_from_gau_and_Waybackurls.txt" \
       -fe jpg,jpeg,png,gif,svg,webp,css,woff,woff2,ttf,ico,eot,otf,map,html,htm,swf,gif,bmp \
       -fk login,logout,signup,register
echo "[+] Filtered interesting URLs saved to: $OUTDIR/interesting_urls.txt"

### Nuclei Scan ###
echo -e "\n[*] Updating nuclei-templates..."
nuclei -update -ut
echo -e "\n[*] Update Finished. Running Nuclei on live URLs..."
nuclei -l "$CLEAN_LIVE_URLS" \
       -o "$NUCLEI_OUTPUT" \
       -severity low,medium,high,critical \
       -t "$HOME/nuclei-templates" \
       -etags dos \
       -timeout 15 \
       -rate-limit 150 \
       -c 50 \
       -markdown-export "$OUTDIR/nuclei_report.md"

echo "[+] Nuclei scan completed. Results saved to: $NUCLEI_OUTPUT"
echo "[+] Markdown report saved to: $OUTDIR/nuclei_report.md"

### Nuclei Scan ###
echo -e "\n[*] Running Nuclei on all IP's ..."
nuclei -l "$UNIQUE_IPS" \
       -o "$IP_NUCLEI_OUTPUT" \
       -severity low,medium,high,critical \
       -t "$HOME/nuclei-templates" \
       -etags dos \
       -timeout 15 \
       -rate-limit 150 \
       -c 50 \
       -markdown-export "$OUTDIR/IP_nuclei_report.md"

echo "[+] Nuclei scan completed. Results saved to: $IP_NUCLEI_OUTPUT"
echo "[+] Markdown report saved to: $OUTDIR/IP_nuclei_report.md"

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
