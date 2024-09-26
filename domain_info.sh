#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to display usage information
usage() {
    echo -e "\e[31mUsage: $0 [OPTIONS]\e[0m"
    echo -e "\e[31mOptions:\e[0m"
    echo -e "\e[31m  -d DOMAIN        Specify a domain to check.\e[0m"
    echo -e "\e[31m  -h, --help       Show this help message.\e[0m"
    echo -e "\e[31m  --no-whois       Skip WHOIS check.\e[0m"
    echo -e "\e[31m  --no-dns         Skip DNS information check.\e[0m"
    echo -e "\e[31m  --no-blacklist    Skip blacklist check.\e[0m"
    echo -e "\e[31m  --no-website      Skip website status check.\e[0m"
    echo -e "\e[31m  --no-cms         Skip CMS detection.\e[0m"
    echo -e "\e[31m  --no-blacklist-check Skip DNS blacklist check.\e[0m"
    exit 1
}

# Function to print colored messages
print_info() {
    local color="$1"
    local message="$2"
    echo -e "\e[${color}m${message}\e[0m"
}

# Function to show a loading animation
loading_animation() {
    local pid=$1
    local delay=0.1
    local spin=('|' '/' '-' '\')
    while ps -p $pid > /dev/null; do
        for i in "${spin[@]}"; do
            echo -ne "\rLoading... $i"
            sleep $delay
        done
    done
    echo -ne "\rLoading complete!  \n"
}

# Check for required tools and prompt to install if missing
REQUIRED_CMDS=("dig" "whois" "curl" "host" "nslookup" "grep" "awk")

for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command_exists "$cmd"; then
        print_info "31" "Error: $cmd is required but not installed. Please install it before running the script."
        exit 1
    fi
done

# Initialize flags
CHECK_WHOIS=true
CHECK_DNS=true
CHECK_BLACKLIST=true
CHECK_WEBSITE=true
CHECK_CMS=true
CHECK_DNS_BLACKLIST=true

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d) DOMAIN="$2"; shift; shift;;
        -h|--help) usage;;
        --no-whois) CHECK_WHOIS=false; shift;;
        --no-dns) CHECK_DNS=false; shift;;
        --no-blacklist) CHECK_BLACKLIST=false; shift;;
        --no-website) CHECK_WEBSITE=false; shift;;
        --no-cms) CHECK_CMS=false; shift;;
        --no-blacklist-check) CHECK_DNS_BLACKLIST=false; shift;;
        *) print_info "31" "Unknown option: $1"; usage;;
    esac
done

# Prompt user for the domain if not provided
if [ -z "$DOMAIN" ]; then
    read -p "Enter the domain name (e.g., example.com): " DOMAIN
fi

# Validate domain format (basic regex)
if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    print_info "31" "Error: Invalid domain format."
    usage
fi

print_info "36" "\nGathering information for domain: $DOMAIN"
print_info "36" "=========================================="

# Temporary file to store results
results_file=$(mktemp)

# Function to append results
append_results() {
    echo -e "$1" >> "$results_file"
}

# Execute checks in the background
if $CHECK_WHOIS; then
    {
        WHOIS_OUTPUT=$(whois "$DOMAIN" 2>&1)
        WHOIS_RESULT=$(echo "$WHOIS_OUTPUT" | grep -E 'Registrar:|Registrant:|Creation Date:|Expiration Date:|Updated Date:|Name Server:|Domain Status:')
        if [ -n "$WHOIS_RESULT" ]; then
            append_results "\n[\e[96mWHOIS Information\e[0m]:\n$WHOIS_RESULT\n"
        else
            append_results "\n[\e[96mWHOIS Information\e[0m]: No WHOIS data found.\n"
        fi
    } & 
    whois_pid=$!
fi

if $CHECK_DNS; then
    {
        DNS_OUTPUT=$(dig "$DOMAIN" ANY +noall +answer 2>&1)
        NS_OUTPUT=$(dig "$DOMAIN" NS +short 2>/dev/null)

        if [ -n "$DNS_OUTPUT" ]; then
            append_results "\n[\e[95mDNS Information\e[0m]:\n$DNS_OUTPUT\n"
        else
            append_results "\n[\e[95mDNS Information\e[0m]: No DNS data found.\n"
        fi

        if [ -n "$NS_OUTPUT" ]; then
            append_results "\n[\e[95mName Servers\e[0m]:\n$NS_OUTPUT\n"
        else
            append_results "\n[\e[95mName Servers\e[0m]: No name servers found.\n"
        fi
    } & 
    dns_pid=$!
fi

if $CHECK_DNS; then
    {
        additional_records=""
        for record_type in A MX TXT CNAME; do
            RECORD_OUTPUT=$(dig "$DOMAIN" "$record_type" +short 2>/dev/null)
            additional_records+="\n[\e[95m$record_type Records\e[0m]:\n"
            if [[ -z "$RECORD_OUTPUT" ]]; then
                additional_records+="No $record_type records found.\n"
            else
                additional_records+="$RECORD_OUTPUT\n"
            fi
        done
        append_results "\n[\e[95mAdditional DNS Records\e[0m]:$additional_records\n"
    } & 
    dns_additional_pid=$!
fi

if $CHECK_BLACKLIST; then
    {
        BLACKLIST_CHECK=$(host "$DOMAIN.multi.rbl.valli.org" 2>/dev/null)
        if [[ "$BLACKLIST_CHECK" == *"127."* ]]; then
            append_results "\n[\e[94mBlacklist Status\e[0m]: Domain is blacklisted.\n"
        else
            append_results "\n[\e[94mBlacklist Status\e[0m]: Domain is not blacklisted.\n"
        fi
    } & 
    blacklist_pid=$!
fi

if $CHECK_WEBSITE; then
    {
        HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" "http://$DOMAIN")
        if [ "$HTTP_STATUS" -eq "200" ]; then
            append_results "\n[\e[93mWebsite Status\e[0m]: Website is UP (HTTP Status Code: $HTTP_STATUS)\n"
        else
            append_results "\n[\e[93mWebsite Status\e[0m]: Website is DOWN or unreachable (HTTP Status Code: $HTTP_STATUS)\n"
        fi
    } & 
    website_pid=$!
fi

if $CHECK_CMS; then
    {
        CMS_CHECK=$(curl -sL "http://$DOMAIN")
        if [[ "$CMS_CHECK" == *"wp-content"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: WordPress detected\n"
        elif [[ "$CMS_CHECK" == *"drupal"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: Drupal detected\n"
        elif [[ "$CMS_CHECK" == *"joomla"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: Joomla detected\n"
        elif [[ "$CMS_CHECK" == *"magento"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: Magento detected\n"
        elif [[ "$CMS_CHECK" == *"shopify"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: Shopify detected\n"
        else
            append_results "\n[\e[92mCMS Detection\e[0m]: No CMS detected\n"
        fi
    } & 
    cms_pid=$!
fi

if $CHECK_DNS_BLACKLIST; then
    {
        BL_LIST=("sbl.spamhaus.org" "xbl.spamhaus.org" "pbl.spamhaus.org" "dnsbl.sorbs.net" "bl.spamcop.net")
        for blacklist in "${BL_LIST[@]}"; do
            BL_STATUS=$(nslookup -q=a "$DOMAIN" "$blacklist" 2>/dev/null)
            if [[ "$BL_STATUS" == *"127."* ]]; then
                append_results "\n[\e[91mDNS Blacklist Check\e[0m]: $DOMAIN is listed on $blacklist\n"
            else
                append_results "\n[\e[91mDNS Blacklist Check\e[0m]: $DOMAIN is NOT listed on $blacklist\n"
            fi
        done
    } & 
    dns_blacklist_pid=$!
fi

# Start loading animation
loading_animation $!

# Wait for all background jobs to finish
wait

# Print all results at once
print_info "36" "\nDomain Overview Complete!\n"
cat "$results_file"

# Clean up
rm "$results_file"
