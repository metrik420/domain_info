# Domain Info Script

## Overview
The Domain Info Script is a powerful Bash script designed to gather essential information about a specified domain. It performs a variety of checks, including WHOIS information, DNS records, blacklist status, website availability, and content management system (CMS) detection. This script is particularly useful for system administrators, web developers, and cybersecurity professionals who need to quickly assess domain properties.

## Features
- **WHOIS Information**: Retrieve registrar details, registration dates, and domain status.
- **DNS Records**: Fetch various DNS records (A, MX, TXT, CNAME) to analyze domain configurations.
- **Blacklist Status**: Check if the domain is listed on common email blacklists.
- **Website Status**: Determine if the website is online and responding with the appropriate HTTP status code.
- **CMS Detection**: Identify common content management systems used by the website (e.g., WordPress, Drupal).

## Usage
To execute the script, run the following command in your terminal:

```bash
./domain_info.sh [OPTIONS]
Options
-d DOMAIN Specify the domain to check (e.g., example.com).
-h, --help Display help information and exit.
--no-whois Skip the WHOIS check.
--no-dns Skip DNS information check.
--no-blacklist Skip the blacklist check.
--no-website Skip the website status check.
--no-cms Skip CMS detection.
--no-blacklist-check Skip DNS blacklist check.
Example
To check the domain example.com, execute:

bash
Copy code
./domain_info.sh -d example.com
Prompted Input
If the -d option is not provided, the script will prompt you to enter the domain name:

bash
Copy code
Enter the domain name (e.g., example.com): example.com
Prerequisites
Before running the script, ensure the following command-line tools are installed on your system:

dig: A DNS lookup utility to fetch DNS records.
whois: A tool to query the WHOIS database for domain information.
curl: A tool for transferring data from or to a server, used for checking website availability.
host: Another DNS lookup utility for resolving domain names.
nslookup: A DNS query tool.
grep: A command-line utility for searching plain-text data.
awk: A programming language for text processing.
Installation
To install the required tools, use your package manager. For example, on Ubuntu, you can run:

bash
Copy code
sudo apt update
sudo apt install dnsutils whois curl
For macOS, use Homebrew:

bash
Copy code
brew install bind whois curl
How It Works
Argument Parsing: The script begins by parsing command-line arguments to determine which checks to perform.
Validation: It validates the provided domain format using a basic regex pattern.
Checks Execution: Depending on the specified options, the script executes various checks in parallel:
WHOIS information is retrieved using the whois command.
DNS records are fetched using dig.
The blacklist status is checked against common RBLs (Real-time Blackhole Lists).
The website status is checked using curl to determine if the server responds correctly.
CMS detection involves fetching the website content and searching for common patterns associated with popular CMS platforms.
Results Compilation: The results from all checks are collected and displayed at the end of the execution.
Contributing
Contributions to improve the script are welcome! If you'd like to contribute, please follow these steps:

Fork the repository.
Create a new branch for your feature or bug fix.
Make your changes and commit them with descriptive messages.
Push your branch to your fork.
Submit a pull request detailing your changes.
Code Style
Follow consistent formatting and naming conventions.
Ensure your code is well-commented for clarity.

Acknowledgments
Inspired by various tools and scripts used in domain analysis and web security.
Thanks to the open-source community for their contributions.
