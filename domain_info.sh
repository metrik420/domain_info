#!/bin/bash

# Function to check if a given command exists on the system.
# This is used to ensure that necessary utilities are available.
# 'command -v' is used to check if the command is recognized by the system.
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to display usage information when the script is called with 
# incorrect or missing parameters. This shows the available options and
# their descriptions.
usage() {
    # Display the script name and options in red for emphasis
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
    exit 1  # Exit the script after showing the usage information
}

# Function to print colored messages on the terminal.
# $1: The color code (e.g., 31 for red, 36 for cyan).
# $2: The message to display.
print_info() {
    local color="$1"
    local message="$2"
    # Use ANSI escape sequences to colorize the output.
    echo -e "\e[${color}m${message}\e[0m"
}

# Function to show a simple loading animation while background processes are running.
# This improves user experience by indicating that the script is working.
# $1: PID of the process to wait for.
loading_animation() {
    local pid=$1
    local delay=0.1  # Delay between each frame of the animation
    local spin=('|' '/' '-' '\')  # Characters used in the spinning animation
    # Loop while the specified process is still running
    while ps -p $pid > /dev/null; do
        for i in "${spin[@]}"; do
            echo -ne "\rLoading... $i"
            sleep $delay
        done
    done
    # Clear the loading message once the process completes
    echo -ne "\rLoading complete!  \n"
}

# List of commands required for the script to function correctly.
# The script will check if these tools (dig, whois, etc.) are installed.
REQUIRED_CMDS=("dig" "whois" "curl" "host" "nslookup" "grep" "awk")

# Iterate over the list of required commands and check if each is installed.
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command_exists "$cmd"; then
        # If a required command is missing, print an error message and exit.
        print_info "31" "Error: $cmd is required but not installed. Please install it before running the script."
        exit 1
    fi
done

# Initialize flags for the various checks the script can perform.
# These can be toggled on or off depending on the user's input.
CHECK_WHOIS=true
CHECK_DNS=true
CHECK_BLACKLIST=true
CHECK_WEBSITE=true
CHECK_CMS=true
CHECK_DNS_BLACKLIST=true

# Parse command-line arguments passed to the script.
# This section processes options like -d (for domain), --no-whois, etc.
while [[ $# -gt 0 ]]; do
    case $1 in
        -d) DOMAIN="$2"; shift; shift;;  # Set the DOMAIN variable when -d is provided
        -h|--help) usage;;  # Show help if -h or --help is passed
        --no-whois) CHECK_WHOIS=false; shift;;  # Disable WHOIS check if --no-whois is passed
        --no-dns) CHECK_DNS=false; shift;;  # Disable DNS check if --no-dns is passed
        --no-blacklist) CHECK_BLACKLIST=false; shift;;  # Disable blacklist check
        --no-website) CHECK_WEBSITE=false; shift;;  # Disable website status check
        --no-cms) CHECK_CMS=false; shift;;  # Disable CMS detection
        --no-blacklist-check) CHECK_DNS_BLACKLIST=false; shift;;  # Disable DNS blacklist check
        *) print_info "31" "Unknown option: $1"; usage;;  # Handle unknown options
    esac
done

# If the domain wasn't provided through a command-line argument, prompt the user to enter it.
if [ -z "$DOMAIN" ]; then
    read -p "Enter the domain name (e.g., example.com): " DOMAIN
fi

# Basic validation of the domain format using regex.
# This checks if the domain resembles something like "example.com".
if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    print_info "31" "Error: Invalid domain format."
    usage
fi

# Print a message indicating that the script is starting to gather information for the specified domain.
print_info "36" "\nGathering information for domain: $DOMAIN"
print_info "36" "=========================================="

# Create a temporary file to store the results of the various checks.
results_file=$(mktemp)

# Function to append data to the results file.
# This is used to consolidate output from different checks into one location.
append_results() {
    echo -e "$1" >> "$results_file"
}

# Perform WHOIS check if the flag is set to true.
if $CHECK_WHOIS; then
    {
        # Execute the WHOIS command and filter relevant information.
        WHOIS_OUTPUT=$(whois "$DOMAIN" 2>&1)
        WHOIS_RESULT=$(echo "$WHOIS_OUTPUT" | grep -E 'Registrar:|Registrant:|Creation Date:|Expiration Date:|Updated Date:|Name Server:|Domain Status:')
        if [ -n "$WHOIS_RESULT" ]; then
            append_results "\n[\e[96mWHOIS Information\e[0m]:\n$WHOIS_RESULT\n"
        else
            append_results "\n[\e[96mWHOIS Information\e[0m]: No WHOIS data found.\n"
        fi
    } &  # Run in the background and store its PID
    whois_pid=$!
fi

# Perform DNS check if the flag is set to true.
if $CHECK_DNS; then
    {
        # Use 'dig' to retrieve DNS information and name server details.
        DNS_OUTPUT=$(dig "$DOMAIN" ANY +noall +answer 2>&1)
        NS_OUTPUT=$(dig "$DOMAIN" NS +short 2>/dev/null)

        # Append DNS information to the results file.
        if [ -n "$DNS_OUTPUT" ]; then
            append_results "\n[\e[95mDNS Information\e[0m]:\n$DNS_OUTPUT\n"
        else
            append_results "\n[\e[95mDNS Information\e[0m]: No DNS data found.\n"
        fi

        # Append Name Servers to the results file.
        if [ -n "$NS_OUTPUT" ]; then
            append_results "\n[\e[95mName Servers\e[0m]:\n$NS_OUTPUT\n"
        else
            append_results "\n[\e[95mName Servers\e[0m]: No name servers found.\n"
        fi
    } &  # Run in the background
    dns_pid=$!
fi

# Retrieve additional DNS records (A, MX, TXT, CNAME) if DNS check is enabled.
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

# Perform blacklist check if the flag is set to true.
if $CHECK_BLACKLIST; then
    {
        # Use 'host' to check if the domain is listed on a public DNS-based blacklist.
        BLACKLIST_CHECK=$(host "$DOMAIN.multi.rbl.valli.org" 2>/dev/null)
        if [[ "$BLACKLIST_CHECK" == *"127."* ]]; then
            append_results "\n[\e[94mBlacklist Status\e[0m]: Domain is blacklisted.\n"
        else
            append_results "\n[\e[94mBlacklist Status\e[0m]: Domain is not blacklisted.\n"
        fi
    } & 
    blacklist_pid=$!
fi

# Perform website availability check if the flag is set to true.
if $CHECK_WEBSITE; then
    {
        # Use 'curl' to check the HTTP status code and response time of the website.
        HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code} %{time_total}" "http://$DOMAIN")
        HTTP_STATUS=$(echo "$HTTP_RESPONSE" | awk '{print $1}')
        RESPONSE_TIME=$(echo "$HTTP_RESPONSE" | awk '{print $2}')

        # Check if the website is up or down based on HTTP status code.
        if [ "$HTTP_STATUS" -eq "200" ]; then
            append_results "\n[\e[93mWebsite Status\e[0m]: Website is UP (HTTP Status Code: $HTTP_STATUS, Response Time: ${RESPONSE_TIME}s)\n"
        else
            append_results "\n[\e[93mWebsite Status\e[0m]: Website is DOWN or unreachable (HTTP Status Code: $HTTP_STATUS, Response Time: ${RESPONSE_TIME}s)\n"
        fi

        # Perform HTTPS check to ensure SSL/TLS availability.
        HTTPS_STATUS=$(curl -o /dev/null -s -w "%{http_code}" "https://$DOMAIN")
        if [ "$HTTPS_STATUS" -eq "200" ]; then
            append_results "\n[\e[93mHTTPS Status\e[0m]: HTTPS is working (HTTP Status Code: $HTTPS_STATUS)\n"
        else
            append_results "\n[\e[93mHTTPS Status\e[0m]: HTTPS is not available or has issues (HTTP Status Code: $HTTPS_STATUS)\n"
        fi

        # Check for SSL certificate expiration if HTTPS is available.
        if command_exists openssl; then
            EXPIRATION_DATE=$(echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -dates | grep 'notAfter')
            if [ -n "$EXPIRATION_DATE" ]; then
                append_results "\n[\e[93mSSL Certificate Status\e[0m]: $EXPIRATION_DATE\n"
            else
                append_results "\n[\e[93mSSL Certificate Status\e[0m]: Unable to retrieve SSL certificate expiration date.\n"
            fi
        else
            append_results "\n[\e[93mSSL Certificate Status\e[0m]: 'openssl' is not installed, skipping SSL certificate check.\n"
        fi

        # Check website's redirect chain (if applicable).
        REDIRECT_CHAIN=$(curl -sIL "http://$DOMAIN" | grep -i "Location:")
        if [ -n "$REDIRECT_CHAIN" ]; then
            append_results "\n[\e[93mRedirect Chain\e[0m]: Detected the following redirects:\n$REDIRECT_CHAIN\n"
        else
            append_results "\n[\e[93mRedirect Chain\e[0m]: No redirects detected.\n"
        fi

        # Check for website content (basic keyword match to see if it’s loading correctly).
        HOMEPAGE_CONTENT=$(curl -sL "http://$DOMAIN")
        if [[ "$HOMEPAGE_CONTENT" == *"DOCTYPE html"* ]]; then
            append_results "\n[\e[93mContent Check\e[0m]: Website content appears valid.\n"
        else
            append_results "\n[\e[93mContent Check\e[0m]: Website content may be missing or invalid.\n"
        fi
    } &
    website_pid=$!
fi

# Perform CMS (Content Management System) detection if the flag is set to true.
if $CHECK_CMS; then
    {
        # Fetch the homepage HTML content and store it in a variable.
        CMS_CHECK=$(curl -sL "http://$DOMAIN")

        # WordPress detection
        if [[ "$CMS_CHECK" == *"wp-content"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: WordPress detected\n"

        # Drupal detection
        elif [[ "$CMS_CHECK" == *"drupal"* || "$CMS_CHECK" == *"sites/default/files"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: Drupal detected\n"

        # Joomla detection
        elif [[ "$CMS_CHECK" == *"joomla"* || "$CMS_CHECK" == *"/templates/"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: Joomla detected\n"

        # Magento detection
        elif [[ "$CMS_CHECK" == *"Magento"* || "$CMS_CHECK" == *"mage" || "$CMS_CHECK" == *"/skin/frontend/"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: Magento detected\n"

        # Shopify detection
        elif [[ "$CMS_CHECK" == *"cdn.shopify.com"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: Shopify detected\n"

        # Wix detection
        elif [[ "$CMS_CHECK" == *"wix.com"* || "$CMS_CHECK" == *"wix-code"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: Wix detected\n"

        # Squarespace detection
        elif [[ "$CMS_CHECK" == *"squarespace.com"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: Squarespace detected\n"

        # TYPO3 detection
        elif [[ "$CMS_CHECK" == *"typo3/"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: TYPO3 detected\n"

        # PrestaShop detection
        elif [[ "$CMS_CHECK" == *"PrestaShop"* || "$CMS_CHECK" == *"/modules/"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: PrestaShop detected\n"

        # OpenCart detection
        elif [[ "$CMS_CHECK" == *"route=common/home"* || "$CMS_CHECK" == *"index.php?route="* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: OpenCart detected\n"

        # Bitrix detection
        elif [[ "$CMS_CHECK" == *"bitrix/"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: Bitrix detected\n"

        # Blogger detection
        elif [[ "$CMS_CHECK" == *"blogger.com"* || "$CMS_CHECK" == *"blogspot.com"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: Blogger detected\n"

        # Ghost detection
        elif [[ "$CMS_CHECK" == *"Ghost"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: Ghost detected\n"

        # Weebly detection
        elif [[ "$CMS_CHECK" == *"weebly.com"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: Weebly detected\n"

        # Duda detection
        elif [[ "$CMS_CHECK" == *"dudamobile.com"* || "$CMS_CHECK" == *"duda.co"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: Duda detected\n"

        # Umbraco detection
        elif [[ "$CMS_CHECK" == *"umbraco/"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: Umbraco detected\n"

        # ExpressionEngine detection
        elif [[ "$CMS_CHECK" == *"ExpressionEngine"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: ExpressionEngine detected\n"

        # Craft CMS detection
        elif [[ "$CMS_CHECK" == *"Craft CMS"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: Craft CMS detected\n"

        # SilverStripe detection
        elif [[ "$CMS_CHECK" == *"SilverStripe"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: SilverStripe detected\n"

        # TYPO3 detection
        elif [[ "$CMS_CHECK" == *"typo3"* ]]; then
            append_results "\n[\e[92mCMS Detection\e[0m]: TYPO3 detected\n"

        # Other/No CMS detected
        else
            append_results "\n[\e[92mCMS Detection\e[0m]: No CMS detected or unknown CMS\n"
        fi
    } & 
    cms_pid=$!
fi


# Perform DNS Blacklist check if the flag is set to true.
if $CHECK_DNS_BLACKLIST; then
    {
        # List of extended common DNS blacklists to check.
        BL_LIST=(
            "sbl.spamhaus.org"        # Spamhaus SBL
            "xbl.spamhaus.org"        # Spamhaus XBL
            "pbl.spamhaus.org"        # Spamhaus PBL
            "dnsbl.sorbs.net"         # SORBS DNSBL
            "bl.spamcop.net"          # SpamCop
            "zen.spamhaus.org"        # Spamhaus ZEN
            "b.barracudacentral.org"  # Barracuda Reputation Block List
            "dnsbl-1.uceprotect.net"  # UCEPROTECT Level 1
            "dnsbl-2.uceprotect.net"  # UCEPROTECT Level 2
            "dnsbl-3.uceprotect.net"  # UCEPROTECT Level 3
            "all.s5h.net"             # S5H DNSBL
            "dnsbl.inps.de"           # INPS DNSBL
            "dnsbl.sorbs.net"         # SORBS Aggregate zone
            "bl.mailspike.net"        # Mailspike Blacklist
            "ubl.unsubscore.com"      # Unsubscore UBL
            "rbl.realtimeblacklist.com" # Real-time Blacklist
            "dnsbl.justspam.org"      # JustSpam DNSBL
            "psbl.surriel.com"        # Passive Spam Block List (PSBL)
        )

        # Iterate over the list of DNS blacklists and check each one.
        for blacklist in "${BL_LIST[@]}"; do
            BL_STATUS=$(nslookup -q=a "$DOMAIN" "$blacklist" 2>/dev/null)

            # Check if the domain is listed in the blacklist (127.x.x.x IPs indicate blacklisting).
            if [[ "$BL_STATUS" == *"127."* ]]; then
                append_results "\n[\e[91mDNS Blacklist Check\e[0m]: $DOMAIN is listed on $blacklist\n"
            else
                append_results "\n[\e[91mDNS Blacklist Check\e[0m]: $DOMAIN is NOT listed on $blacklist\n"
            fi

            # Handle potential errors or issues with the nslookup command.
            if [[ -z "$BL_STATUS" ]]; then
                append_results "\n[\e[93mDNS Blacklist Check\e[0m]: Unable to query $blacklist for $DOMAIN (no response or error)\n"
            fi
        done
    } & 
    dns_blacklist_pid=$!
fi

# Start a loading animation while background processes are running.
loading_animation $!

# Wait for all background jobs to finish before proceeding.
wait

# Once all checks are complete, display the consolidated results.
print_info "36" "\nDomain Overview Complete!\n"
cat "$results_file"

# Clean up temporary files after execution.
rm "$results_file"
