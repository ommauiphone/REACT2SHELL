#!/bin/bash

# ============================================
# SCRIPT CEK PANEL HOSTING - MULTI PORT SCAN
# ============================================

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Fungsi output
print_header() { echo -e "${BLUE}[+]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_info() { echo -e "${CYAN}[i]${NC} $1"; }

# Fungsi cek port dengan curl
check_panel() {
    local panel_name="$1"
    local url="$2"
    local protocol="$3"
    local expected_codes="$4"
    
    echo -n "  ${panel_name} (${url}) ... "
    
    if [[ "$protocol" == "https" ]]; then
        response=$(curl -k -s -I -L --connect-timeout 8 --max-time 10 "${url}" 2>/dev/null | head -1)
    else
        response=$(curl -s -I -L --connect-timeout 8 --max-time 10 "${url}" 2>/dev/null | head -1)
    fi
    
    if [[ -z "$response" ]]; then
        echo -e "${RED}TIMEOUT/CONNECTION FAILED${NC}"
        return 2
    fi
    
    http_code=$(echo "$response" | awk '{print $2}')
    
    # Cek apakah kode response sesuai dengan yang diharapkan
    for code in $expected_codes; do
        if [[ "$http_code" == "$code" ]]; then
            echo -e "${GREEN}LIVE (HTTP ${http_code})${NC}"
            return 0
        fi
    done
    
    echo -e "${YELLOW}HTTP ${http_code}${NC}"
    return 1
}

# Fungsi cek port dengan telnet (fallback)
check_port_telnet() {
    local panel_name="$1"
    local host="$2"
    local port="$3"
    
    echo -n "  ${panel_name} (${host}:${port}) ... "
    
    timeout 3 bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}PORT OPEN${NC}"
        return 0
    else
        echo -e "${RED}PORT CLOSED${NC}"
        return 1
    fi
}

# ============================================
# KONFIGURASI
# ============================================

DOMAIN="${1:-gamesku.my.id}"
LOG_FILE="panel_check_$(date +%Y%m%d_%H%M%S).log"
DETECTED_PANELS=()

# Daftar panel dan URL/port untuk dicek
PANELS=(
    # cPanel & WHM
    "cPanel (2083)" "https://${DOMAIN}:2083" "https" "200 302 401 403"
    "cPanel (2082)" "http://${DOMAIN}:2082" "http" "200 302 401 403"
    "WHM (2087)" "https://${DOMAIN}:2087" "https" "200 302 401 403"
    "WHM (2086)" "http://${DOMAIN}:2086" "http" "200 302 401 403"
    "cPanel /cpanel" "http://${DOMAIN}/cpanel" "http" "200 302 301"
    "cPanel /cpanel (SSL)" "https://${DOMAIN}/cpanel" "https" "200 302 301"
    
    # Webmail
    "Webmail /webmail" "http://${DOMAIN}/webmail" "http" "200 302"
    "Roundcube /roundcube" "http://${DOMAIN}/roundcube" "http" "200 302"
    "SquirrelMail /squirrelmail" "http://${DOMAIN}/squirrelmail" "http" "200 302"
    
    # Plesk
    "Plesk (8443)" "https://${DOMAIN}:8443" "https" "200 302 401 403"
    "Plesk (8880)" "https://${DOMAIN}:8880" "https" "200 302 401 403"
    "Plesk /plesk" "http://${DOMAIN}/plesk" "http" "200 302"
    
    # DirectAdmin
    "DirectAdmin (2222)" "http://${DOMAIN}:2222" "http" "200 302"
    "DirectAdmin SSL (2222)" "https://${DOMAIN}:2222" "https" "200 302"
    
    # CyberPanel
    "CyberPanel (8090)" "http://${DOMAIN}:8090" "http" "200 302"
    "CyberPanel (8090 SSL)" "https://${DOMAIN}:8090" "https" "200 302"
    "CyberPanel /cyberpanel" "http://${DOMAIN}/cyberpanel" "http" "200 302"
    
    # ISPConfig
    "ISPConfig (8080)" "http://${DOMAIN}:8080" "http" "200 302"
    
    # VestaCP
    "VestaCP (8083)" "http://${DOMAIN}:8083" "http" "200 302"
    
    # Ajenti
    "Ajenti (8000)" "http://${DOMAIN}:8000" "http" "200 302"
    
    # Froxlor
    "Froxlor /admin" "http://${DOMAIN}/admin" "http" "200 302"
    
    # Webmin
    "Webmin (10000)" "https://${DOMAIN}:10000" "https" "200 302"
    
    # FastPanel
    "FastPanel /manager" "http://${DOMAIN}/manager" "http" "200 302"
    "FastPanel /fp" "http://${DOMAIN}/fp" "http" "200 302"
    
    # aaPanel
    "aaPanel (7800)" "http://${DOMAIN}:7800" "http" "200 302"
    
    # CWP (CentOS Web Panel)
    "CWP (2030)" "https://${DOMAIN}:2030" "https" "200 302"
    "CWP (2031)" "https://${DOMAIN}:2031" "https" "200 302"
    
    # Server Side
    "phpMyAdmin /phpmyadmin" "http://${DOMAIN}/phpmyadmin" "http" "200 302"
    "phpMyAdmin /pma" "http://${DOMAIN}/pma" "http" "200 302"
    "Adminer /adminer" "http://${DOMAIN}/adminer" "http" "200 302"
    
    # FTP Admin
    "FTP Admin /ftp" "http://${DOMAIN}/ftp" "http" "200 302"
)

# ============================================
# EXECUTION
# ============================================

echo -e "${CYAN}"
echo "============================================"
echo "   PANEL HOSTING SCANNER"
echo "   Domain: ${DOMAIN}"
echo "   Time: $(date)"
echo "============================================"
echo -e "${NC}"

print_header "Starting comprehensive panel check..."
echo ""

# Cek koneksi dasar ke domain
print_info "Checking basic domain connectivity..."
ping -c 2 -W 2 "${DOMAIN}" >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
    print_success "Domain responds to ping"
else
    print_warning "Domain does not respond to ping (may be blocked)"
fi

echo ""
print_header "Checking common control panels..."

# Loop melalui semua panel
count=0
for ((i=0; i<${#PANELS[@]}; i+=4)); do
    panel_name="${PANELS[$i]}"
    url="${PANELS[$i+1]}"
    protocol="${PANELS[$i+2]}"
    expected_codes="${PANELS[$i+3]}"
    
    ((count++))
    
    # Cek panel
    check_panel "$panel_name" "$url" "$protocol" "$expected_codes"
    result=$?
    
    # Jika berhasil (return 0), tambahkan ke list
    if [[ $result -eq 0 ]]; then
        DETECTED_PANELS+=("${panel_name} - ${url}")
    fi
    
    # Jeda kecil untuk menghindari rate limiting
    if [[ $((count % 5)) -eq 0 ]]; then
        sleep 0.5
    fi
done

echo ""
print_header "Checking common open ports (quick scan)..."
# Cek port-port penting dengan telnet-style
PORTS_TO_CHECK="21 22 25 53 80 110 143 443 465 587 993 995 2082 2083 2086 2087 2222 3306 8080 8443 8880 10000"
for port in $PORTS_TO_CHECK; do
    check_port_telnet "Port $port" "${DOMAIN}" "$port"
done

echo ""
print_header "Results Summary:"

if [[ ${#DETECTED_PANELS[@]} -gt 0 ]]; then
    print_success "Detected ${#DETECTED_PANELS[@]} potential panel(s):"
    for panel in "${DETECTED_PANELS[@]}"; do
        echo "  • ${panel}"
    done
    
    echo ""
    print_info "Try accessing these URLs in your browser:"
    for panel in "${DETECTED_PANELS[@]}"; do
        url=$(echo "$panel" | awk -F' - ' '{print $2}')
        echo "  - ${url}"
    done
else
    print_warning "No common control panels detected on standard ports/paths."
    print_info "Possible reasons:"
    echo "  1. Panel is on a non-standard port"
    echo "  2. Panel is only accessible via server IP, not domain"
    echo "  3. Panel access is restricted by firewall"
    echo "  4. No control panel is installed (server managed via SSH)"
fi

# Cek juga IP server
echo ""
print_header "Checking server IP information..."
print_info "Server IP from domain resolution:"
dig +short "${DOMAIN}" | while read ip; do
    echo "  - $ip"
done

print_info "Your external IP (for comparison):"
curl -s --max-time 3 https://api.ipify.org || echo "  (Could not determine)"

# Cek apakah ada redirect ke www
echo ""
print_header "Checking for www redirect..."
curl -s -I -L --max-time 5 "http://${DOMAIN}" 2>/dev/null | grep -i "location:\|http/" | head -5

# Log results
{
    echo "============================================"
    echo "Panel Check Report for ${DOMAIN}"
    echo "Date: $(date)"
    echo "============================================"
    echo ""
    echo "Detected Panels:"
    if [[ ${#DETECTED_PANELS[@]} -gt 0 ]]; then
        for panel in "${DETECTED_PANELS[@]}"; do
            echo "  • ${panel}"
        done
    else
        echo "  None detected"
    fi
    echo ""
    echo "Scan completed."
} > "${LOG_FILE}"

echo ""
print_success "Scan complete! Detailed log saved to: ${LOG_FILE}"
print_info "Next steps:"
echo "  1. Try accessing detected URLs"
echo "  2. Check your hosting provider's control panel"
echo "  3. If nothing found, try accessing via server IP address"

# ============================================
# OPSIONAL: Jika ingin cek lebih detail
# ============================================

echo ""
read -p "Run extended port scan (100 common ports, slower)? [y/N]: " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_header "Running extended port scan (top 100 ports)..."
    # Menggunakan netcat jika tersedia
    if command -v nc &> /dev/null; then
        for port in {1..100}; do
            (echo >/dev/tcp/${DOMAIN}/${port}) >/dev/null 2>&1 && echo -e "  ${GREEN}Port ${port}: OPEN${NC}" || continue
        done
    else
        print_warning "netcat not available for extended scan"
    fi
fi

echo -e "\n${CYAN}============================================${NC}"
print_success "Script execution finished!"
