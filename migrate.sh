#!/bin/bash

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variabel global
PM=""
APP_NAME=""
SYSTEMD_SERVICE=""
PACKAGE_NAME=""
PHP_PORT="3000"
PROJECT_PATH=""
NEXT_PID=""

# Fungsi print dengan warna
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

### ------------ Detect Package Manager ---------------
detect_pm() {
    print_info "Mendeteksi package manager..."
    if command -v pnpm &> /dev/null; then
        PM="pnpm"
    elif command -v yarn &> /dev/null; then
        PM="yarn"
    else
        PM="npm"
    fi
    print_info "Package Manager: $PM"
}

### ------------ Detect Project Path ---------------
detect_project_path() {
    print_info "Mendeteksi path project..."
    
    # Coba dari PWD
    if [ -f "package.json" ]; then
        PROJECT_PATH=$(pwd)
        print_info "Project path ditemukan di: $PROJECT_PATH"
        return 0
    fi
    
    # Coba cari di lokasi umum
    COMMON_PATHS=(
        "/www"
        "/var/www"
        "/home"
        "/root"
        "/app"
    )
    
    for path in "${COMMON_PATHS[@]}"; do
        if [ -d "$path" ]; then
            FOUND=$(find "$path" -name "package.json" -type f 2>/dev/null | head -1)
            if [ -n "$FOUND" ]; then
                PROJECT_PATH=$(dirname "$FOUND")
                print_info "Project path ditemukan: $PROJECT_PATH"
                return 0
            fi
        fi
    done
    
    # Jika tidak ditemukan, minta input user
    echo ""
    print_warning "Tidak dapat mendeteksi path project Next.js secara otomatis"
    read -p "Masukkan path lengkap ke folder Next.js: " PROJECT_PATH
    
    if [ ! -d "$PROJECT_PATH" ]; then
        print_error "Path tidak valid: $PROJECT_PATH"
        exit 1
    fi
    
    return 0
}

### ------------ Detect APP NAME from package.json ---------------
detect_app_name_from_package_json() {
    local path="$1"
    
    if [ -f "$path/package.json" ]; then
        PACKAGE_NAME=$(grep '"name"' "$path/package.json" | head -n 1 | sed 's/.*"name": *"//; s/".*//')
        
        if [[ -n "$PACKAGE_NAME" ]]; then
            APP_NAME="$PACKAGE_NAME"
            print_info "APP_NAME dari package.json: $APP_NAME"
        fi
    fi

    # Jika masih kosong, fallback ke nama folder
    if [[ -z "$APP_NAME" ]]; then
        APP_NAME="${PROJECT_PATH##*/}"
        print_info "APP_NAME fallback ke nama folder: $APP_NAME"
    fi
}

### ------------ Auto Detect systemd service ---------------
detect_systemd_service() {
    if command -v systemctl &>/dev/null; then
        SERVICE=$(systemctl list-units --type=service --no-pager --all | grep -Ei "$APP_NAME|next|node" | head -n 1 | awk '{print $1}')
        
        if [[ -n "$SERVICE" ]]; then
            SYSTEMD_SERVICE="$SERVICE"
            print_info "Ditemukan systemd service: $SYSTEMD_SERVICE"
        else
            # Cari dengan pattern lain
            SERVICE=$(systemctl list-units --type=service --no-pager --all | grep -E "next|node|3000" | head -n 1 | awk '{print $1}')
            if [[ -n "$SERVICE" ]]; then
                SYSTEMD_SERVICE="$SERVICE"
                print_info "Ditemukan alternatif systemd service: $SYSTEMD_SERVICE"
            fi
        fi
    fi
}

### ------------ Auto Detect PM2 App ---------------
detect_pm2_app_name() {
    if command -v pm2 &>/dev/null; then
        # Check PM2 app matching package.json name
        if pm2 list 2>/dev/null | grep -q "$APP_NAME"; then
            print_info "PM2 app cocok: $APP_NAME"
            return 0
        fi

        # Check any PM2 process running next
        ALT=$(pm2 list 2>/dev/null | grep -Ei "next|node|3000" | awk '{print $4}' | head -n 1)
        if [[ -n "$ALT" ]]; then
            APP_NAME="$ALT"
            print_info "Ditemukan alternatif PM2 app: $APP_NAME"
        fi
    fi
}

### ------------ Detect Next.js Process ---------------
detect_next_process() {
    print_info "Mendeteksi proses Next.js yang berjalan..."
    
    # Cek process dengan next
    NEXT_PROCESS=$(ps aux | grep -E "next.*start|node.*next" | grep -v grep | head -1)
    
    if [ -n "$NEXT_PROCESS" ]; then
        NEXT_PID=$(echo "$NEXT_PROCESS" | awk '{print $2}')
        print_info "Ditemukan proses Next.js - PID: $NEXT_PID"
        print_info "Command: $(echo "$NEXT_PROCESS" | cut -d' ' -f11-)"
    fi
    
    # Cek port 3000
    PORT_PROCESS=$(lsof -ti:3000 2>/dev/null || ss -tlnp | grep :3000 | awk '{print $7}' | cut -d'/' -f1)
    
    if [ -n "$PORT_PROCESS" ]; then
        print_info "Proses di port 3000: $PORT_PROCESS"
    fi
}

### ------------ Stop Next.js ---------------
stop_nextjs() {
    print_info "Menghentikan Next.js..."
    
    # 1. Stop systemd service jika ada
    if [ -n "$SYSTEMD_SERVICE" ]; then
        print_info "Menghentikan systemd service: $SYSTEMD_SERVICE"
        systemctl stop "$SYSTEMD_SERVICE" 2>/dev/null
        systemctl disable "$SYSTEMD_SERVICE" 2>/dev/null
    fi
    
    # 2. Stop PM2 jika ada
    if command -v pm2 &>/dev/null; then
        if pm2 list 2>/dev/null | grep -q "$APP_NAME"; then
            print_info "Menghentikan PM2 app: $APP_NAME"
            pm2 stop "$APP_NAME" 2>/dev/null
            pm2 delete "$APP_NAME" 2>/dev/null
        fi
    fi
    
    # 3. Kill semua proses next dan node di path ini
    print_info "Menghentikan semua proses Next.js/Node..."
    pkill -9 -f "next.*start" 2>/dev/null
    pkill -9 -f "node.*next" 2>/dev/null
    
    # 4. Kill process di port 3000
    print_info "Mengosongkan port 3000..."
    lsof -ti:3000 | xargs kill -9 2>/dev/null
    fuser -k 3000/tcp 2>/dev/null
    
    # 5. Kill process spesifik di project path
    if [ -n "$PROJECT_PATH" ]; then
        pgrep -f "$PROJECT_PATH" | xargs kill -9 2>/dev/null
    fi
    
    # Verifikasi
    sleep 2
    if ps aux | grep -E "next.*start|node.*next" | grep -v grep | grep -v "$0"; then
        print_warning "Masih ada proses Next.js yang berjalan"
        ps aux | grep -E "next.*start|node.*next" | grep -v grep | grep -v "$0"
    else
        print_success "Next.js berhasil dihentikan"
    fi
}

### ------------ Install PHP ---------------
install_php() {
    print_info "Memeriksa PHP..."
    
    if command -v php &> /dev/null; then
        PHP_VERSION=$(php --version | head -n1)
        print_info "PHP sudah terinstall: $PHP_VERSION"
    else
        print_info "Menginstall PHP..."
        
        # Deteksi distro
        if [ -f /etc/debian_version ]; then
            apt-get update
            apt-get install -y php php-cli
        elif [ -f /etc/redhat-release ] || [ -f /etc/centos-release ] || [ -f /etc/almalinux-release ] || [ -f /etc/rocky-release ]; then
            yum install -y epel-release
            yum install -y php php-cli
        elif [ -f /etc/alpine-release ]; then
            apk add php php-cli
        else
            print_error "Distribusi Linux tidak dikenali"
            read -p "Lanjutkan tanpa install PHP? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
        
        if command -v php &> /dev/null; then
            print_success "PHP berhasil diinstall"
        else
            print_error "Gagal menginstall PHP"
            exit 1
        fi
    fi
}

### ------------ Setup PHP Server ---------------
setup_php_server() {
    print_info "Menyiapkan PHP server di port $PHP_PORT..."
    
    # Ganti ke project directory
    cd "$PROJECT_PATH" || {
        print_error "Tidak dapat masuk ke directory: $PROJECT_PATH"
        exit 1
    }
    
    # Backup package.json jika ada
    if [ -f "package.json" ]; then
        BACKUP_FILE="package.json.backup.$(date +%Y%m%d_%H%M%S)"
        cp package.json "$BACKUP_FILE"
        print_info "Backup package.json: $BACKUP_FILE"
    fi
    
    # Buat index.php
    cat > index.php << 'EOF'
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PHP Application</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            border-bottom: 2px solid #4CAF50;
            padding-bottom: 10px;
        }
        .info-box {
            background: #f8f9fa;
            border-left: 4px solid #4CAF50;
            padding: 15px;
            margin: 20px 0;
        }
        .success {
            color: #4CAF50;
            font-weight: bold;
        }
        .detail {
            background: #e8f5e9;
            padding: 10px;
            border-radius: 5px;
            margin: 5px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 PHP Application Berjalan!</h1>
        
        <div class="info-box">
            <p class="success">✔ Konversi Next.js ke PHP berhasil!</p>
            <p>Aplikasi sekarang berjalan dengan PHP di port yang sama.</p>
        </div>
        
        <div class="detail">
            <strong>Informasi Server:</strong><br>
            PHP Version: <?php echo phpversion(); ?><br>
            Port: <?php echo $_SERVER['SERVER_PORT'] ?? '3000'; ?><br>
            Path: <?php echo __DIR__; ?><br>
            Server: <?php echo $_SERVER['SERVER_SOFTWARE'] ?? 'PHP Built-in Server'; ?>
        </div>
        
        <div class="detail">
            <strong>PHP Modules:</strong><br>
            <?php
            foreach (get_loaded_extensions() as $ext) {
                echo "• " . $ext . "<br>";
            }
            ?>
        </div>
        
        <div class="detail">
            <strong>Server Info:</strong><br>
            OS: <?php echo php_uname(); ?><br>
            Time: <?php echo date('Y-m-d H:i:s'); ?><br>
            Memory: <?php echo ini_get('memory_limit'); ?>
        </div>
        
        <p style="margin-top: 30px; font-style: italic;">
            Halaman ini dibuat secara otomatis oleh migration script.
        </p>
    </div>
</body>
</html>
EOF
    
    print_success "File index.php berhasil dibuat"
    
    # Buat file info.php untuk testing
    cat > info.php << 'EOF'
<?php
header('Content-Type: text/plain');
echo "PHP Info:\n";
echo "---------\n";
echo "PHP Version: " . phpversion() . "\n";
echo "Server Port: " . ($_SERVER['SERVER_PORT'] ?? '3000') . "\n";
echo "Document Root: " . $_SERVER['DOCUMENT_ROOT'] . "\n";
echo "Request Method: " . $_SERVER['REQUEST_METHOD'] . "\n";
echo "---------\n";
echo "PHP Modules:\n";
foreach (get_loaded_extensions() as $ext) {
    echo "- $ext\n";
}
?>
EOF
}

### ------------ Start PHP Server ---------------
start_php_server() {
    print_info "Menjalankan PHP server..."
    
    cd "$PROJECT_PATH"
    
    # Hentikan PHP server lama jika ada
    pkill -f "php.*3000" 2>/dev/null
    
    # Jalankan PHP server
    nohup php -S 0.0.0.0:$PHP_PORT > php-server.log 2>&1 &
    
    # Tunggu sebentar
    sleep 3
    
    # Verifikasi
    if pgrep -f "php.*$PHP_PORT" > /dev/null; then
        PHP_PID=$(pgrep -f "php.*$PHP_PORT")
        print_success "PHP server berjalan di port $PHP_PORT (PID: $PHP_PID)"
        
        # Test dengan curl
        print_info "Testing server..."
        if curl -s -o /dev/null -w "%{http_code}" http://localhost:$PHP_PORT/ | grep -q "200"; then
            print_success "Server merespon dengan baik!"
            echo ""
            echo "================================================"
            echo "    PHP SERVER BERHASIL DIJALANKAN!"
            echo "================================================"
            echo "URL: http://localhost:$PHP_PORT"
            echo "Path: $PROJECT_PATH"
            echo "Log: $PROJECT_PATH/php-server.log"
            echo "================================================"
            echo ""
        fi
    else
        print_error "Gagal menjalankan PHP server"
        print_info "Cek log: $PROJECT_PATH/php-server.log"
        exit 1
    fi
    
    # Buat startup script
    cat > start-php.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "Starting PHP server on port 3000..."
php -S 0.0.0.0:3000
EOF
    chmod +x start-php.sh
}

### ------------ Create Systemd Service ---------------
create_systemd_service() {
    if command -v systemctl &>/dev/null; then
        print_info "Membuat systemd service untuk PHP..."
        
        SERVICE_NAME="php-${APP_NAME// /-}"
        SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
        
        cat > "$SERVICE_FILE" << EOF
[Unit]
Description=PHP Server for $APP_NAME
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PROJECT_PATH
ExecStart=/usr/bin/php -S 0.0.0.0:$PHP_PORT
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        systemctl enable "$SERVICE_NAME"
        systemctl start "$SERVICE_NAME"
        
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            print_success "Systemd service berhasil dibuat: $SERVICE_NAME"
        else
            print_warning "Systemd service dibuat tapi tidak aktif"
        fi
    fi
}

### ------------ Summary ---------------
show_summary() {
    echo ""
    echo "================================================"
    echo "           MIGRASI SELESAI!"
    echo "================================================"
    echo "Next.js di: $PROJECT_PATH"
    echo "Diganti dengan: PHP Built-in Server"
    echo "Port: $PHP_PORT"
    echo ""
    echo "Perintah berguna:"
    echo "  Cek status:   curl http://localhost:$PHP_PORT/"
    echo "  Info PHP:     curl http://localhost:$PHP_PORT/info.php"
    echo "  Log server:   tail -f $PROJECT_PATH/php-server.log"
    echo ""
    
    if [ -n "$SYSTEMD_SERVICE" ]; then
        echo "Service systemd: $SYSTEMD_SERVICE (dimatikan)"
    fi
    
    echo "================================================"
    print_success "Selamat! PHP server berjalan di port yang sama"
}

### ------------ Main Function ---------------
main() {
    echo ""
    echo "================================================"
    echo "   MIGRASI NEXT.JS KE PHP - SCRIPT"
    echo "================================================"
    
    # Deteksi
    detect_project_path
    detect_app_name_from_package_json "$PROJECT_PATH"
    detect_pm
    detect_systemd_service
    detect_pm2_app_name
    detect_next_process
    
    echo ""
    read -p "Lanjutkan migrasi Next.js ke PHP? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Migrasi dibatalkan"
        exit 0
    fi
    
    # Install PHP
    install_php
    
    # Stop Next.js
    stop_nextjs
    
    # Setup PHP
    setup_php_server
    start_php_server
    create_systemd_service
    
    # Summary
    show_summary
}

### ------------ Run Main ---------------
# Cek jika running sebagai root
if [[ $EUID -ne 0 ]]; then
   print_error "Script ini harus dijalankan sebagai root"
   exit 1
fi

# Jalankan main function
main "$@"
