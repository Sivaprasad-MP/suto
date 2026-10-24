#!/bin/bash

# ============================================================
#  suto.sh — Subdomain TakeOver Tool
#  Single-file approach: --install flag for setup
#  Default: subdomain enumeration + CNAME extraction
#  Extended: --full flag for advanced features
#  Output: Plain text + HTML report
# ============================================================

set -euo pipefail

VERSION="1.1.0"
export PATH="${GOPATH:-$HOME/go}/bin:${HOME}/.local/bin:${PATH}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================
#  HELP
# ============================================================
show_help() {
    cat << EOF
╔══════════════════════════════════════════════════════════════╗
║                    suto.sh v${VERSION}                        ║
║           Subdomain TakeOver Automation Tool                ║
╚══════════════════════════════════════════════════════════════╝

USAGE:
  ./suto.sh [OPTIONS] <domain>

OPTIONS:
  --install         Install all required dependencies
  --full            Enable extended features (permutations, JS scraping, screenshots)
  --output DIR      Custom output directory (default: ./outputs/<domain>_<timestamp>)
  --ports LIST      HTTP(S) ports to probe (default: 80,443; e.g. 80,443,8080,8443)
  --threads N       Thread count for parallel operations (default: 50)
  --update          Update all installed Go tools to latest versions
  -h, --help        Show this help message

EXAMPLES:
  sudo ./suto.sh --install                           # Install everything
  ./suto.sh target.com                          # Quick run (enum + CNAME)
  ./suto.sh target.com --full                   # Full recon
  ./suto.sh target.com --output ~/reports       # Custom output dir
  ./suto.sh target.com --threads 100            # Faster with more threads
  ./suto.sh target.com --update                 # Update tools

REQUIREMENTS:
  - Sudo is required only for --install
  - Internet connection required
  - Go must be installable (added by --install if missing)

TOOLS USED:
  Minimal:  subfinder, assetfinder, httpx, dnsx, nuclei, subjack
  Extended: + amass, dnsgen, gotator, shuffledns, hakrawler, gowitness, waybackurls
EOF
    exit 0
}

# ============================================================
#  PRIVILEGE CHECK
# ============================================================
check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[!] This script must be run with sudo.${NC}"
        echo -e "${YELLOW}[*] Usage: sudo $0 <domain>${NC}"
        exit 1
    fi
}

# ============================================================
#  INSTALLATION
# ============================================================
install_tools() {
    echo -e "${BLUE}[*] Starting installation of dependencies...${NC}\n"

    # Update package lists
    echo -e "${YELLOW}[+] Updating package lists...${NC}"
    apt update

    # System packages
    echo -e "${YELLOW}[+] Installing system packages...${NC}"
    apt install -y \
        dnsutils \
        curl \
        jq \
        parallel \
        git \
        golang-go \
        python3 \
        pipx \
        xdg-utils

    # Ensure Go PATH is correct
    export GOPATH="${GOPATH:-$HOME/go}"
    export PATH=$PATH:$GOPATH/bin
    mkdir -p "$GOPATH/bin"

    export GOBIN=/usr/local/bin
    mkdir -p "$GOBIN"
    local failures=0
    # Install Go tools
    echo -e "\n${YELLOW}[+] Installing Go-based tools...${NC}"

    TOOLS=(
        "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
        "github.com/tomnomnom/assetfinder@latest"
        "github.com/projectdiscovery/httpx/cmd/httpx@latest"
        "github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
        "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
        "github.com/haccer/subjack@latest"
    )

    for tool in "${TOOLS[@]}"; do
        name=$(basename "$tool" | sed 's/@latest//' | sed 's/v2//' | sed 's/v3//' | sed 's/cmd\///')
        if command -v "$name" &>/dev/null && { [[ "$name" != httpx ]] || httpx -h 2>&1 | grep -q -- "-no-fallback"; }; then
            echo -e "${GREEN}[✓] $name already installed${NC}"
        else
            echo -e "${CYAN}[~] Installing $name...${NC}"
            go install "$tool" && echo -e "${GREEN}[✓] $name installed${NC}" || { echo -e "${RED}[✗] Failed to install $name${NC}"; failures=$((failures + 1)); }
        fi
    done

    # Install nuclei templates
    echo -e "\n${YELLOW}[+] Installing/updating nuclei templates...${NC}"
    nuclei -update-templates || { echo "Nuclei template update failed" >&2; failures=$((failures + 1)); }

    # Install extended tools if --install is called with --full
    if [[ "${INSTALL_FULL:-false}" == true ]]; then
        echo -e "\n${YELLOW}[+] Installing extended tools...${NC}"
        EXTRA_TOOLS=(
            "github.com/owasp-amass/amass/v4/...@latest"
            "github.com/projectdiscovery/shuffledns/cmd/shuffledns@latest"
            "github.com/projectdiscovery/chaos-client/cmd/chaos@latest"
            "github.com/tomnomnom/waybackurls@latest"
            "github.com/hakluke/hakrawler@latest"
            "github.com/sensepost/gowitness@latest"
            "github.com/Josue87/gotator@latest"
        )
        for tool in "${EXTRA_TOOLS[@]}"; do
            name=$(basename "$tool" | sed 's/@latest//' | sed 's/v4//' | sed 's/cmd\///')
            [[ "$tool" == *amass* ]] && name=amass
            command -v "$name" &>/dev/null && echo -e "${GREEN}[✓] $name already installed${NC}" || {
                echo -e "${CYAN}[~] Installing $name...${NC}"
                go install "$tool" && echo -e "${GREEN}[✓] $name installed${NC}" || { echo -e "${RED}[✗] Failed to install $name${NC}"; failures=$((failures + 1)); }
            }
        done

        # Install dnsgen (Python)
        if ! command -v dnsgen &>/dev/null; then
            echo -e "${CYAN}[~] Installing dnsgen...${NC}"
            PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install dnsgen && echo -e "${GREEN}[✓] dnsgen installed${NC}" || { echo -e "${RED}[✗] Failed to install dnsgen${NC}"; failures=$((failures + 1)); }
        fi
    fi

    (( failures == 0 )) || { echo "Installation incomplete: $failures tool(s) failed." >&2; exit 1; }
    echo -e "\n${GREEN}[✓] Installation complete!${NC}"
    echo -e "${YELLOW}[*] Run: sudo $0 <domain>${NC}"
    exit 0
}

# ============================================================
#  BANNER
# ============================================================
show_banner() {
    local domain="$1"
    local mode="$2"
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    suto.sh v${VERSION}                        ║"
    echo "║           Subdomain TakeOver Automation Tool                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${BLUE}[*] Target:${NC} $domain"
    echo -e "${BLUE}[*] Mode:${NC}   ${mode:-Standard}"
    echo -e "${BLUE}[*] Date:${NC}   $(date)"
    echo ""
}

# ============================================================
#  DNS UTILITY
# ============================================================
get_cname() {
    dig +time=3 +tries=1 +short CNAME "$1" | head -1
}

is_alive() {
    local sub="$1"
    # Strip protocol if present
    sub="${sub#http://}"
    sub="${sub#https://}"
    httpx -silent -u "https://$sub" -status-code -timeout 5 2>/dev/null | grep -qE "^https?://"
}

# ============================================================
#  KNOWN TAKEOVER SERVICES
# ============================================================
declare -A TAKEOVER_PATTERNS
TAKEOVER_PATTERNS=(
    ["s3.amazonaws.com"]="AWS S3 Bucket"
    ["s3-"]="AWS S3 Bucket"
    ["cloudfront.net"]="AWS CloudFront"
    ["herokuapp.com"]="Heroku"
    ["github.io"]="GitHub Pages"
    ["azurewebsites.net"]="Azure App Service"
    ["azurefd.net"]="Azure Front Door"
    ["trafficmanager.net"]="Azure Traffic Manager"
    ["ondigitalocean.app"]="DigitalOcean App Platform"
    ["myshopify.com"]="Shopify"
    ["fastly.net"]="Fastly"
    ["fastlylb.net"]="Fastly Load Balancer"
    ["zendesk.com"]="Zendesk"
    ["unbounce.com"]="Unbounce"
    ["surge.sh"]="Surge.sh"
    ["pages.dev"]="Cloudflare Pages"
    ["firebaseapp.com"]="Firebase"
    ["web.app"]="Firebase"
    ["bitbucket.io"]="Bitbucket Pages"
    ["pantheonsite.io"]="Pantheon"
    ["wpengine.com"]="WP Engine"
    ["wordpress.com"]="WordPress.com"
    ["vercel-dns.com"]="Vercel"
    ["vercel.app"]="Vercel"
    ["netlify.app"]="Netlify"
    ["pantheon.io"]="Pantheon"
    ["readme.io"]="ReadMe.io"
    ["gitbook.io"]="GitBook"
    ["ohdear.app"]="Oh Dear"
    ["gumroad.com"]="Gumroad"
    ["ssl.ohdear.app"]="Oh Dear Status"
)

classify_cname() {
    local cname="${1,,}" pattern
    cname="${cname%.}"
    for pattern in "${!TAKEOVER_PATTERNS[@]}"; do
        [[ "$pattern" == "s3-" ]] && continue
        if [[ "$cname" == "$pattern" || "$cname" == *."$pattern" ]]; then
            echo "${TAKEOVER_PATTERNS[$pattern]}"
            return
        fi
    done
    if [[ "$cname" == *.amazonaws.com && ( "$cname" == s3-* || "$cname" == *.s3-* || "$cname" == *.s3.* ) ]]; then
        echo "AWS S3 Bucket"
        return
    fi
    echo "Unknown/Other"
}

html_escape() {
    local value="$1"
    value="${value//&/\&amp;}"
    value="${value//</\&lt;}"
    value="${value//>/\&gt;}"
    value="${value//\"/\&quot;}"
    value="${value//\'/\&#39;}"
    printf '%s' "$value"
}

filter_scope() {
    awk -v domain="$1" '{
        host=tolower($0); sub(/\r$/, "", host)
        if (host ~ /^[a-z0-9_][a-z0-9._-]*$/ && length(host) <= 253 &&
            (host == domain || (length(host) > length(domain) &&
             substr(host, length(host)-length(domain)) == "." domain))) print host
    }' | sort -u
}

# ============================================================
#  HTML REPORT GENERATOR
# ============================================================
generate_html_report() {
    local domain="$1"
    local outdir="$2"
    local timestamp="$3"
    local html_file="$outdir/report.html"

    cat > "$html_file" << HTMLHEADER
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Subdomain TakeOver Report — $domain</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f172a; color: #e2e8f0; padding: 40px; }
        h1 { font-size: 2rem; margin-bottom: 8px; color: #38bdf8; }
        h2 { font-size: 1.4rem; margin: 30px 0 15px; color: #facc15; border-bottom: 1px solid #334155; padding-bottom: 8px; }
        .meta { color: #94a3b8; margin-bottom: 30px; }
        .meta span { margin-right: 24px; }
        table { width: 100%; border-collapse: collapse; margin-bottom: 30px; }
        th, td { padding: 10px 14px; text-align: left; border-bottom: 1px solid #1e293b; font-size: 0.9rem; }
        th { background: #1e293b; color: #94a3b8; font-weight: 600; text-transform: uppercase; font-size: 0.75rem; letter-spacing: 0.5px; }
        tr:hover { background: #1e293b; }
        .status-alive { color: #4ade80; font-weight: 600; }
        .status-dead { color: #f87171; }
        .status-potential { color: #facc15; font-weight: 600; }
        .status-confirmed { color: #ef4444; font-weight: 700; }
        .badge { display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 0.75rem; font-weight: 600; }
        .badge-s3 { background: #f97316; color: #0f172a; }
        .badge-cloudfront { background: #8b5cf6; color: #fff; }
        .badge-heroku { background: #a855f7; color: #fff; }
        .badge-vercel { background: #fff; color: #0f172a; }
        .badge-github { background: #333; color: #fff; }
        .badge-azure { background: #0078d4; color: #fff; }
        .badge-other { background: #475569; color: #fff; }
        .summary-cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 16px; margin: 20px 0; }
        .card { background: #1e293b; border-radius: 12px; padding: 20px; text-align: center; }
        .card .number { font-size: 2rem; font-weight: 700; color: #38bdf8; }
        .card .label { font-size: 0.8rem; color: #94a3b8; margin-top: 4px; }
        a { color: #38bdf8; text-decoration: none; }
        a:hover { text-decoration: underline; }
        .footer { margin-top: 40px; color: #475569; font-size: 0.8rem; text-align: center; }
    </style>
</head>
<body>
    <h1>🔍 Subdomain TakeOver Report</h1>
    <div class="meta">
        <span>🎯 Target: <strong>$domain</strong></span>
        <span>📅 Generated: $timestamp</span>
        <span>🔧 Tool: suto.sh v${VERSION}</span>
    </div>
HTMLHEADER

    # Summary cards
    local total=$(wc -l < "$outdir/all_subdomains.txt" 2>/dev/null || echo 0)
    local alive=$(wc -l < "$outdir/alive_subdomains.txt" 2>/dev/null || echo 0)
    local candidates=$(wc -l < "$outdir/takeover_candidates.txt" 2>/dev/null || echo 0)
    local confirmed=$(wc -l < "$outdir/confirmed_takeovers.txt" 2>/dev/null || echo 0)

    cat >> "$html_file" << HTMLCARDS
    <div class="summary-cards">
        <div class="card"><div class="number">$total</div><div class="label">Total Subdomains</div></div>
        <div class="card"><div class="number">$alive</div><div class="label">Alive</div></div>
        <div class="card"><div class="number">$candidates</div><div class="label">Takeover Candidates</div></div>
        <div class="card"><div class="number" style="color: #ef4444;">$confirmed</div><div class="label">Scanner Findings (unverified)</div></div>
    </div>
HTMLCARDS

    # Takeover Candidates Table
    if [[ -f "$outdir/takeover_candidates.txt" && -s "$outdir/takeover_candidates.txt" ]]; then
        cat >> "$html_file" << HTMLTABLE
    <h2>⚠️ Takeover Candidates</h2>
    <table>
        <tr><th>Subdomain</th><th>CNAME Target</th><th>Service</th><th>Status</th></tr>
HTMLTABLE
        while IFS= read -r record; do
            sub="${record%% -> *}"
            cname="${record#* -> }"
            cname_clean="${cname#-> }"
            service=$(classify_cname "$cname_clean")
            # Badge class
            service_lower=$(echo "$service" | tr '[:upper:]' '[:lower:]')
            badge_class="badge-other"
            echo "$service_lower" | grep -qi "s3" && badge_class="badge-s3"
            echo "$service_lower" | grep -qi "cloudfront" && badge_class="badge-cloudfront"
            echo "$service_lower" | grep -qi "heroku" && badge_class="badge-heroku"
            echo "$service_lower" | grep -qi "vercel" && badge_class="badge-vercel"
            echo "$service_lower" | grep -qi "github" && badge_class="badge-github"
            echo "$service_lower" | grep -qi "azure" && badge_class="badge-azure"
            echo "<tr><td>$(html_escape "$sub")</td><td>$(html_escape "$cname_clean")</td><td><span class=\"badge $badge_class\">$service</span></td><td class=\"status-potential\">Potential</td></tr>" >> "$html_file"
        done < "$outdir/takeover_candidates.txt"
        echo "</table>" >> "$html_file"
    fi

    # Scanner Findings (unverified)
    if [[ -f "$outdir/confirmed_takeovers.txt" && -s "$outdir/confirmed_takeovers.txt" ]]; then
        cat >> "$html_file" << HTMLCONF
    <h2>🚨 Scanner Findings (unverified)</h2>
    <table>
        <tr><th>Subdomain</th><th>Service</th><th>Details</th></tr>
HTMLCONF
        while IFS= read -r line; do
            echo "<tr><td class=\"status-confirmed\">$(html_escape "$line")</td><td>—</td><td>Manual validation required</td></tr>" >> "$html_file"
        done < "$outdir/confirmed_takeovers.txt"
        echo "</table>" >> "$html_file"
    fi

    # All CNAME Records
    if [[ -f "$outdir/cname_records.txt" && -s "$outdir/cname_records.txt" ]]; then
        cat >> "$html_file" << HTMLCNAME
    <h2>📋 All CNAME Records</h2>
    <table>
        <tr><th>Subdomain</th><th>CNAME Target</th><th>Service</th></tr>
HTMLCNAME
        while IFS= read -r record; do
            sub="${record%% -> *}"
            cname="${record#* -> }"
            cname_clean="${cname#-> }"
            service=$(classify_cname "$cname_clean")
            echo "<tr><td>$(html_escape "$sub")</td><td>$(html_escape "$cname_clean")</td><td>$service</td></tr>" >> "$html_file"
        done < "$outdir/cname_records.txt"
        echo "</table>" >> "$html_file"
    fi

    # All Subdomains (collapsed by default)
    if [[ -f "$outdir/all_subdomains.txt" && -s "$outdir/all_subdomains.txt" ]]; then
        cat >> "$html_file" << HTMLALL
    <h2>📄 All Discovered Subdomains ($total total)</h2>
    <details>
        <summary style="cursor:pointer;color:#38bdf8;">Click to expand</summary>
        <table>
            <tr><th>#</th><th>Subdomain</th></tr>
HTMLALL
        i=1
        while IFS= read -r sub; do
            echo "<tr><td>$i</td><td>$(html_escape "$sub")</td></tr>" >> "$html_file"
            ((i++))
        done < "$outdir/all_subdomains.txt"
        echo "</table></details>" >> "$html_file"
    fi

    # Alive Subdomains
    if [[ -f "$outdir/alive_subdomains.txt" && -s "$outdir/alive_subdomains.txt" ]]; then
        cat >> "$html_file" << HTMLALIVE
    <h2>✅ Alive Subdomains ($alive)</h2>
    <table>
        <tr><th>#</th><th>Subdomain</th></tr>
HTMLALIVE
        i=1
        while IFS= read -r sub; do
            echo "<tr><td>$i</td><td class=\"status-alive\">$(html_escape "$sub")</td></tr>" >> "$html_file"
            ((i++))
        done < "$outdir/alive_subdomains.txt"
        echo "</table>" >> "$html_file"
    fi

    # Footer
    cat >> "$html_file" << HTMLFOOTER
    <div class="footer">
        Generated by suto.sh v${VERSION} | $(date) | For authorized security testing only
    </div>
</body>
</html>
HTMLFOOTER

    echo -e "${GREEN}[✓] HTML report generated: $html_file${NC}"
}

# ============================================================
#  MAIN ENUMERATION ENGINE
# ============================================================
run_enumeration() {
    local domain="$1"
    local full_mode="${2:-false}"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local outdir="${OUTPUT_DIR:-./outputs/${domain}_${timestamp}_$$}"
    local mode=Standard
    [[ "$full_mode" == true ]] && mode=Extended
    if [[ -d "$outdir" && -n "$(ls -A "$outdir")" ]]; then
        echo "Output directory must be empty: $outdir" >&2
        return 1
    fi
    local threads="${THREADS:-50}"

    mkdir -p "$outdir/raw"

    show_banner "$domain" "$mode"

    # --------------------------------------------------------
    # PHASE 1: Subdomain Enumeration
    # --------------------------------------------------------
    echo -e "${BLUE}[*] Phase 1: Subdomain Enumeration${NC}"

    # 1a. Assetfinder
    echo -e "${YELLOW}  [→] assetfinder...${NC}"
    assetfinder --subs-only "$domain" 2>> "$outdir/errors.log" | sort -u > "$outdir/raw/assetfinder.txt" || true
    echo -e "${GREEN}      Found: $(wc -l < "$outdir/raw/assetfinder.txt")${NC}"

    # 1b. Subfinder
    echo -e "${YELLOW}  [→] subfinder...${NC}"
    subfinder -d "$domain" -silent 2>> "$outdir/errors.log" | sort -u > "$outdir/raw/subfinder.txt" || true
    echo -e "${GREEN}      Found: $(wc -l < "$outdir/raw/subfinder.txt")${NC}"

    # 1c. crt.sh
    echo -e "${YELLOW}  [→] crt.sh...${NC}"
    curl --connect-timeout 10 --max-time 60 -fsS "https://crt.sh/?q=%25.${domain}&output=json" 2>> "$outdir/errors.log" | \
        jq -r '.[].name_value' 2>> "$outdir/errors.log" | \
        sed 's/\*\.//g' | \
        sort -u > "$outdir/raw/crtsh.txt" || true
    echo -e "${GREEN}      Found: $(wc -l < "$outdir/raw/crtsh.txt")${NC}"

    # 1d. Amass (passive) — only in full mode
    if [[ "$full_mode" == true ]]; then
        echo -e "${YELLOW}  [→] amass (passive)...${NC}"
        : > "$outdir/raw/amass.txt"
        amass enum -passive -d "$domain" -o "$outdir/raw/amass.txt" 2>> "$outdir/errors.log" || true
        echo -e "${GREEN}      Found: $(wc -l < "$outdir/raw/amass.txt")${NC}"
    fi

    # 1e. Chaos (if available)
    if command -v chaos &>/dev/null; then
        echo -e "${YELLOW}  [→] chaos...${NC}"
        chaos -d "$domain" -silent 2>> "$outdir/errors.log" | sort -u > "$outdir/raw/chaos.txt" || true
        echo -e "${GREEN}      Found: $(wc -l < "$outdir/raw/chaos.txt")${NC}"
    fi

    # --------------------------------------------------------
    # PHASE 2: Merge & Deduplicate
    # --------------------------------------------------------
    echo -e "\n${BLUE}[*] Phase 2: Merging & Deduplicating${NC}"
    cat "$outdir/raw/"*.txt | filter_scope "$domain" > "$outdir/all_subdomains.txt"
    total=$(wc -l < "$outdir/all_subdomains.txt")
    echo -e "${GREEN}      Total unique subdomains: $total${NC}"

    # Permutation generation (full mode only)
    if [[ "$full_mode" == true ]] && command -v dnsgen &>/dev/null; then
        echo -e "${YELLOW}  [→] Generating permutations...${NC}"
        dnsgen "$outdir/all_subdomains.txt" 2>> "$outdir/errors.log" | \
            filter_scope "$domain" | \
            sort -u > "$outdir/permutations.txt" || true
        # Merge permutations back
        cat "$outdir/permutations.txt" >> "$outdir/all_subdomains.txt" 2>> "$outdir/errors.log" || true
        sort -u -o "$outdir/all_subdomains.txt" "$outdir/all_subdomains.txt"
        total=$(wc -l < "$outdir/all_subdomains.txt")
        echo -e "${GREEN}      After permutations: $total unique subdomains${NC}"
    fi

    # --------------------------------------------------------
    # PHASE 3: Alive Check
    # --------------------------------------------------------
    echo -e "\n${BLUE}[*] Phase 3: Checking alive subdomains${NC}"
    echo -e "${YELLOW}  [→] httpx probe...${NC}"
    : > "$outdir/alive_raw.txt"
    if ! httpx -l "$outdir/all_subdomains.txt" \
        -silent -no-color -status-code -no-fallback \
        -ports "${PORTS:-80,443}" -threads "$threads" \
        -timeout 5 -o "$outdir/alive_raw.txt" 2>> "$outdir/errors.log"; then
        echo "HTTP probe failed; see $outdir/errors.log" >&2
        return 1
    fi
    # Preserve URLs and ports for downstream HTTP tools; count unique hostnames separately.
    awk '{print $1}' "$outdir/alive_raw.txt" | sort -u > "$outdir/alive_urls.txt"
    sed -E 's@^https?://@@; s@[:/].*$@@' "$outdir/alive_urls.txt" |
        filter_scope "$domain" > "$outdir/alive_subdomains.txt"
    alive=$(wc -l < "$outdir/alive_subdomains.txt")
    echo -e "${GREEN}      Alive: $alive${NC}"

    # No HTTP response does not imply the DNS hostname is absent.
    comm -23 <(sort "$outdir/all_subdomains.txt") <(sort "$outdir/alive_subdomains.txt") 2>> "$outdir/errors.log" > "$outdir/dead_subdomains.txt" || true
    dead=$(wc -l < "$outdir/dead_subdomains.txt")
    echo -e "${YELLOW}      No HTTP response on selected ports (still check DNS): $dead${NC}"

    # --------------------------------------------------------
    # PHASE 4: CNAME Extraction (CRITICAL)
    # --------------------------------------------------------
    echo -e "\n${BLUE}[*] Phase 4: CNAME Record Extraction${NC}"
    echo -e "${YELLOW}  [→] Resolving CNAMEs on all subdomains...${NC}"

    # Process all subdomains for CNAMEs
    > "$outdir/cname_records.txt"
    export -f get_cname

    # Keep every CNAME answer on its own row, including names containing hyphens.
    parallel -j "$threads" \
        'dig +time=3 +tries=1 +short CNAME {} | while IFS= read -r cname; do if [ -n "$cname" ]; then printf "%s -> %s\n" {} "$cname"; fi; done' \
        < "$outdir/all_subdomains.txt" > "$outdir/cname_records.txt" 2>> "$outdir/errors.log"

    cname_count=$(wc -l < "$outdir/cname_records.txt")
    echo -e "${GREEN}      Subdomains with CNAMEs: $cname_count${NC}"

    # --------------------------------------------------------
    # PHASE 5: Filter Takeover Candidates
    # --------------------------------------------------------
    echo -e "\n${BLUE}[*] Phase 5: Filtering Takeover Candidates${NC}"

    : > "$outdir/takeover_candidates.txt"
    while IFS= read -r record; do
        cname="${record#* -> }"
        if [[ "$(classify_cname "$cname")" != "Unknown/Other" ]]; then
            printf '%s\n' "$record" >> "$outdir/takeover_candidates.txt"
        fi
    done < "$outdir/cname_records.txt"

    candidates=$(wc -l < "$outdir/takeover_candidates.txt")
    echo -e "${YELLOW}      Takeover candidates: $candidates${NC}"

    if [[ $candidates -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}      ┌─────────────────────────────────────────────────────┐${NC}"
        while IFS= read -r record; do
            sub="${record%% -> *}"
            cname="${record#* -> }"
            cname_clean="${cname#-> }"
            service=$(classify_cname "$cname_clean")
            echo -e "${YELLOW}      │${NC} $sub"
            echo -e "${YELLOW}      │${NC}   └→ $cname_clean"
            echo -e "${YELLOW}      │${NC}      Service: $service"
            echo ""
        done < "$outdir/takeover_candidates.txt"
        echo -e "${YELLOW}      └─────────────────────────────────────────────────────┘${NC}"
    fi

    # --------------------------------------------------------
    # PHASE 6: Confirmation with Nuclei + Subjack
    # --------------------------------------------------------
    echo -e "\n${BLUE}[*] Phase 6: Confirming Takeovers${NC}"

    > "$outdir/confirmed_takeovers.txt"

    # 6a. Nuclei takeover templates
    if command -v nuclei &>/dev/null && [[ -d ~/nuclei-templates/http/takeovers/ ]]; then
        echo -e "${YELLOW}  [→] nuclei takeover templates...${NC}"
        : > "$outdir/nuclei_results.txt"
        nuclei -l "$outdir/alive_urls.txt" \
            -t ~/nuclei-templates/http/takeovers/ \
            -silent \
            -o "$outdir/nuclei_results.txt" 2>> "$outdir/errors.log" || true
        nucount=$(wc -l < "$outdir/nuclei_results.txt")
        echo -e "${GREEN}      Nuclei findings: $nucount${NC}"
        cat "$outdir/nuclei_results.txt" >> "$outdir/confirmed_takeovers.txt" 2>> "$outdir/errors.log" || true
    fi

    # 6b. Subjack
    if command -v subjack &>/dev/null; then
        echo -e "${YELLOW}  [→] subjack scan...${NC}"
        : > "$outdir/subjack_results.txt"
        subjack -w "$outdir/all_subdomains.txt" \
            -t "$threads" \
            -timeout 30 \
            -ssl \
            -o "$outdir/subjack_results.txt" 2>> "$outdir/errors.log" || true
        sjcount=$(wc -l < "$outdir/subjack_results.txt" 2>> "$outdir/errors.log" || echo 0)
        echo -e "${GREEN}      Subjack findings: $sjcount${NC}"
        [[ -f "$outdir/subjack_results.txt" ]] && cat "$outdir/subjack_results.txt" >> "$outdir/confirmed_takeovers.txt" 2>> "$outdir/errors.log" || true
    fi

    # Deduplicate confirmed
    if [[ -f "$outdir/confirmed_takeovers.txt" ]]; then
        sort -u -o "$outdir/confirmed_takeovers.txt" "$outdir/confirmed_takeovers.txt"
        confirmed=$(wc -l < "$outdir/confirmed_takeovers.txt")
        echo -e "${RED}      Total scanner findings: $confirmed${NC}"
    fi

    # --------------------------------------------------------
    # PHASE 7: Extended Features (full mode)
    # --------------------------------------------------------
    if [[ "$full_mode" == true ]]; then

        # 7a. Wayback URLs for dead bucket discovery
        if command -v waybackurls &>/dev/null; then
            echo -e "\n${BLUE}[*] [Extended] Wayback Machine URLs${NC}"
            echo -e "${YELLOW}  [→] waybackurls on takeover candidates...${NC}"
            if [[ -s "$outdir/takeover_candidates.txt" ]]; then
                awk '{print $1}' "$outdir/takeover_candidates.txt" | \
                    waybackurls 2>> "$outdir/errors.log" > "$outdir/wayback_urls.txt" || true
                wbcount=$(wc -l < "$outdir/wayback_urls.txt")
                echo -e "${GREEN}      Wayback URLs found: $wbcount${NC}"
            fi
        fi

        # 7b. JS scraping for leaked origins
        if command -v hakrawler &>/dev/null && [[ -s "$outdir/takeover_candidates.txt" ]]; then
            echo -e "${YELLOW}  [→] hakrawler JS scraping...${NC}"
            cat "$outdir/alive_urls.txt" | \
                hakrawler -d 2 -dr -timeout 10 -t "$threads" 2>> "$outdir/errors.log" | \
                grep -iE 's3|bucket|amazonaws|origin|cloudfront' \
                > "$outdir/js_leaks.txt" || true
            jsleaks=$(wc -l < "$outdir/js_leaks.txt")
            echo -e "${GREEN}      JS leaks found: $jsleaks${NC}"
        fi

        # 7c. Screenshots with gowitness
        if command -v gowitness &>/dev/null && [[ -s "$outdir/alive_subdomains.txt" ]]; then
            echo -e "${YELLOW}  [→] gowitness screenshots...${NC}"
            mkdir -p "$outdir/screenshots"
            gowitness scan file -f "$outdir/alive_urls.txt" \
                --screenshot-path "$outdir/screenshots" \
                --threads "$threads" \
                --timeout 10 2>> "$outdir/errors.log" || true
            scount=$(find "$outdir/screenshots" -type f -name "*.png" | wc -l)
            echo -e "${GREEN}      Screenshots taken: $scount${NC}"
        fi
    fi

    # --------------------------------------------------------
    # PHASE 8: Generate Summary
    # --------------------------------------------------------
    echo -e "\n${BLUE}[*] Phase 8: Generating Summary & Report${NC}"

    {
        echo "============================================"
        echo "  suto.sh — Scan Summary"
        echo "  Target: $domain"
        echo "  Date:   $(date)"
        echo "  Mode:   $mode"
        echo "  HTTP ports: ${PORTS:-80,443}"
        echo "============================================"
        echo ""
        echo "  Total subdomains found:    $total"
        echo "  Alive subdomains:          $alive"
        echo "  No HTTP on selected ports: $dead"
        echo "  See errors.log for diagnostics. DNS existence and takeover status require separate validation."
        echo "  Subdomains with CNAMEs:    $cname_count"
        echo "  Takeover candidates:       $candidates"
        echo "  Scanner findings (unverified):       ${confirmed:-0}"
        echo ""
        if [[ $candidates -gt 0 ]]; then
            echo "  ⚠ TAKEOVER CANDIDATES:"
            while IFS= read -r record; do
            sub="${record%% -> *}"
            cname="${record#* -> }"
                echo "    $sub"
                echo "      → $cname"
            done < "$outdir/takeover_candidates.txt"
            echo ""
        fi
        if [[ ${confirmed:-0} -gt 0 ]]; then
            echo "  🚨 SCANNER FINDINGS (UNVERIFIED):"
            cat "$outdir/confirmed_takeovers.txt"
            echo ""
        fi
        echo "  Output directory: $outdir"
        echo "  HTML report:      $outdir/report.html"
        echo "============================================"
    } > "$outdir/summary.txt"

    cat "$outdir/summary.txt"

    # Generate HTML report
    generate_html_report "$domain" "$outdir" "$timestamp"

    # --------------------------------------------------------
    # DONE
    # --------------------------------------------------------
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                      SCAN COMPLETE                          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}[*] Output:${NC}   $outdir"
    echo -e "${BLUE}[*] HTML:${NC}     $outdir/report.html"
    echo -e "${BLUE}[*] Summary:${NC}  $outdir/summary.txt"
    echo ""

    if [[ -s "$outdir/errors.log" ]]; then
        echo "Some tools reported diagnostics; review $outdir/errors.log before interpreting missing findings." >&2
    fi

    # Try to open HTML report
    if command -v xdg-open &>/dev/null; then
        xdg-open "$outdir/report.html" 2>> "$outdir/errors.log" || true
    fi
}

# ============================================================
#  UPDATE TOOLS
# ============================================================
update_tools() {
    echo -e "${BLUE}[*] Updating all Go tools...${NC}"
    local failures=0
    export GOPATH="${GOPATH:-$HOME/go}"
    export PATH=$PATH:$GOPATH/bin

    TOOLS=(
        "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
        "github.com/tomnomnom/assetfinder@latest"
        "github.com/projectdiscovery/httpx/cmd/httpx@latest"
        "github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
        "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
        "github.com/haccer/subjack@latest"
    )

    for tool in "${TOOLS[@]}"; do
        name=$(basename "$tool" | sed 's/@latest//' | sed 's/v2//' | sed 's/v3//' | sed 's/cmd\///')
        echo -e "${CYAN}[~] Updating $name...${NC}"
        go install "$tool" && echo -e "${GREEN}[✓] $name updated${NC}" || { echo -e "${RED}[✗] Failed to update $name${NC}"; failures=$((failures + 1)); }
    done

    # Update nuclei templates
    echo -e "\n${YELLOW}[+] Updating nuclei templates...${NC}"
    nuclei -update-templates || { echo "Nuclei template update failed" >&2; failures=$((failures + 1)); }

    (( failures == 0 )) || { echo "Update incomplete: $failures tool(s) failed." >&2; exit 1; }
    echo -e "\n${GREEN}[✓] Update complete!${NC}"
    exit 0
}

# ============================================================
#  MAIN
# ============================================================
main() {
    local domain=""
    local full_mode=false
    local install_mode=false
    local update_mode=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --install)
                install_mode=true
                shift
                ;;
            --full)
                full_mode=true
                shift
                ;;
            --output)
                [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || { echo "--output requires a directory" >&2; exit 1; }
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --threads)
                [[ $# -ge 2 ]] || { echo "--threads requires a number" >&2; exit 1; }
                THREADS="$2"
                shift 2
                ;;
            --ports)
                [[ $# -ge 2 ]] || { echo "--ports requires a list" >&2; exit 1; }
                PORTS="$2"
                shift 2
                ;;
            --update)
                update_mode=true
                shift
                ;;
            -h|--help)
                show_help
                ;;
            -*)
                echo -e "${RED}[!] Unknown option: $1${NC}"
                echo "Usage: sudo $0 [OPTIONS] <domain>"
                exit 1
                ;;
            *)
                [[ -z "$domain" ]] || { echo "Specify exactly one domain" >&2; exit 1; }
                domain="$1"
                shift
                ;;
        esac
    done

    # Handle modes
    if [[ "$install_mode" == true ]]; then
        check_sudo
        INSTALL_FULL="$full_mode"
        install_tools
    fi

    if [[ "$update_mode" == true ]]; then
        update_tools
    fi

    # Require domain
    if [[ -z "$domain" ]]; then
        echo -e "${RED}[!] No domain specified.${NC}"
        echo "Usage: sudo $0 [OPTIONS] <domain>"
        echo "Try: sudo $0 --help"
        exit 1
    fi

    # Set defaults
    THREADS="${THREADS:-50}"

    domain="${domain,,}"
    domain="${domain%.}"
    if [[ ${#domain} -gt 253 || "$domain" != *.* || "$domain" == *..* ||
          ! "$domain" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]]; then
        echo "Invalid domain: $domain (use a hostname without scheme, path, or port)." >&2
        exit 1
    fi
    local label
    IFS=. read -ra labels <<< "$domain"
    for label in "${labels[@]}"; do
        [[ ${#label} -le 63 && "$label" != -* && "$label" != *- ]] || { echo "Invalid domain label" >&2; exit 1; }
    done
    [[ "$THREADS" =~ ^[1-9][0-9]{0,3}$ ]] || { echo "Threads must be between 1 and 9999" >&2; exit 1; }
    PORTS="${PORTS:-80,443}"
    [[ "$PORTS" =~ ^[0-9]+(,[0-9]+)*$ ]] || { echo "Ports must be a comma-separated list" >&2; exit 1; }
    local port
    IFS=, read -ra port_list <<< "$PORTS"
    for port in "${port_list[@]}"; do
        [[ ${#port} -le 5 ]] && (( 10#$port >= 1 && 10#$port <= 65535 )) || { echo "Invalid port: $port" >&2; exit 1; }
    done
    local tool
    for tool in assetfinder subfinder httpx curl jq dig parallel; do
        command -v "$tool" >/dev/null || { echo "Missing dependency: $tool (run --install)" >&2; exit 1; }
    done
    local httpx_help
    httpx_help=$(httpx -h 2>&1) || { echo "Cannot inspect httpx" >&2; exit 1; }
    [[ "$httpx_help" == *-no-fallback* && "$httpx_help" == *-ports* ]] || {
        echo "ProjectDiscovery httpx is required; another program named httpx may be on PATH." >&2
        exit 1
    }
    # Run
    run_enumeration "$domain" "$full_mode"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
