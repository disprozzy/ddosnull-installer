#!/bin/bash

# Capture all output to a log file
INSTALL_LOG="/tmp/ddosnull_install_$(date +%s).log"
exec > >(tee -a "$INSTALL_LOG") 2>&1

echo "=== ddosNull Client Installation Started at $(date) ==="

# Get instance ID from command line argument
INSTANCE_ID="$1"

# Try python3 first, then python
PYTHON_CMD=$(command -v python3 || command -v python)

if [ -z "$PYTHON_CMD" ]; then
    echo "Python is not installed. Python 3.6 or higher is required."
    exit 1
fi

# Check version inside Python itself
"$PYTHON_CMD" - << 'EOF'
import sys
required = (3, 6)
if sys.version_info < required:
    print(f"Python 3.6 or higher is required, found {sys.version.split()[0]}")
    sys.exit(1)
EOF

if [ $? -ne 0 ]; then
    exit 1
fi

echo "Python version is OK (>= 3.6)."

# Check if git is installed
if command -v git >/dev/null 2>&1; then
    echo "Git is already installed."
else
    echo "Git is not installed. Installing..."

    # Detect OS family
    if [ -f /etc/redhat-release ]; then
        # RedHat-based (RHEL, CentOS, AlmaLinux, Rocky, Fedora)
        echo "Detected RedHat-based system."
        sudo yum install -y git || sudo dnf install -y git

    elif [ -f /etc/debian_version ]; then
        # Debian-based (Debian, Ubuntu, Mint)
        echo "Detected Debian/Ubuntu-based system."
        sudo apt-get update -y
        sudo apt-get install -y git

    else
        echo "Unsupported distribution. Install Git manually."
        exit 1
    fi

    # Final check
    if command -v git >/dev/null 2>&1; then
        echo "Git was successfully installed."
    else
        echo "Git installation failed."
        exit 1
    fi
fi




echo "Installing the agent and dependencies"
cd /opt/
git clone https://github.com/disprozzy/la-client.git
cd la-client/

$PYTHON_CMD -m pip install requests dotenv


echo "Updating agent the configs."
INSTANCE_ID="$1"

cat > .env <<EOF
API_URL='https://app.ddosnull.com:4433/api/'
INSTANCE_ID='${INSTANCE_ID}'
VERSION='3.1'
EOF


echo "Updating firewall rules."
iptables -I OUTPUT -d 104.154.244.71 -j ACCEPT &> /dev/null
iptables -I INPUT -s 104.154.244.71 -j ACCEPT &> /dev/null
service iptables save &> /dev/null
iptables-save > /etc/sysconfig/iptables 
echo 104.154.244.71 >> /etc/csf/csf.allow 
csf -r &> /dev/null 

URL="https://app.ddosnull.com:4433/recaptcha/"

# Prefer curl, fallback to wget
if command -v curl >/dev/null 2>&1; then
    echo "Checking $URL with curl..."
    if ! curl -sS --max-time 10 --fail "$URL" >/dev/null 2>&1; then
        echo "ERROR: $URL is not accessible. Please check firewall settings and make sure outgoing connections to port 4433 are allowed or contact support@ddosnull.com for help."
        exit 1
    fi
elif command -v wget >/dev/null 2>&1; then
    echo "Checking $URL with wget..."
    if ! wget --timeout=10 --spider "$URL" >/dev/null 2>&1; then
        echo "ERROR: $URL is not accessible. Please check firewall settings and make sure outgoing connections to port 4433 are allowed or contact support@ddosnull.com for help."
        exit 1
    fi
else
    echo "ERROR: Neither curl nor wget is installed. Cannot check $URL."
    exit 1
fi
echo "$URL is accessible."


echo "Updating web server configs."


if [ -f /usr/local/psa/version ]; then
    echo "Plesk detected: $(cat /usr/local/psa/version)"
        echo '# ---- Whitelist ----
        geo $remote_addr $is_whitelisted_ip {
        include /etc/nginx/maps/whitelisted_ips.map;
        }
        # ---- Bot detection ----
        map $http_user_agent $is_bot {
        include /etc/nginx/maps/bot_user_agents.map;
        }

        # ---- Cookie check ----
        map $http_cookie $has_recaptcha_cookie {
        default 0;
        "~recaptcha_verified=1" 1;
        }

        # ---- Suspicious IPs ----
        geo $remote_addr $is_suspicious_ip {
        include /etc/nginx/maps/suspicious_ip.map;
        }

        # ---- Include domain-based DDoS mode ----
        map $host $ddos_mode {
        include /etc/nginx/maps/ddos_mode.map;
        }

        map "$is_bot:$has_recaptcha_cookie:$ddos_mode:$is_suspicious_ip:$is_whitelisted_ip" $needs_recaptcha {
        default         0;

        # Skip for bots
        "~^1:.*"        0;

        # Skip if IP is whitelisted
        "~^.*:.*:.*:.*:1" 0;

        # Skip if cookie present
        "~^.:1:.:.:."   0;

        # Force check: DDoS ON or suspicious IP and no cookie
        "~^0:0:1:.:0"   1;
        "~^0:0:.:1:0"   1;

        # All others: allow
        "~^0:0:0:0:0"   0;
        }' > /etc/nginx/conf.d/ddosnull.conf
        echo 'server {
            listen 127.0.0.1:80;
            server_name localhost;

            location /nginx_status {
                stub_status;
                allow 127.0.0.1;
                deny all;
            }
        }' > /etc/nginx/conf.d/stats.conf


        mkdir /etc/nginx/maps/
        echo 'default 0;

        safe.com    0;
        test.com    1;' > /etc/nginx/maps/ddos_mode.map

        echo 'default 0;
        127.127.127.127 1;' >  /etc/nginx/maps/suspicious_ip.map

        echo 'default 0;

        ~*googlebot        1;
        ~*bingbot          1;
        ~*yahoo            1;
        ~*rackspace      1;' > /etc/nginx/maps/bot_user_agents.map

        echo 'default 0;' > /etc/nginx/maps/whitelisted_ips.map
        /usr/bin/systemctl reload nginx

        if ls /usr/local/psa/admin/conf/templates/custom/domain/service/proxy.php; then
                echo ""exists;""
        else
                mkdir /usr/local/psa/admin/conf/templates/custom/domain/service -p
                cp /usr/local/psa/admin/conf/templates/default/domain/service/proxy.php /usr/local/psa/admin/conf/templates/custom/domain/service
        fi

        config="/usr/local/psa/admin/conf/templates/custom/domain/service/proxy.php"
        if [ `grep recaptcha $config|wc -l` -gt 0 ];then
          echo ""
        else
                sed -i '1i\
                        if ($needs_recaptcha = 1) {\
                                return 302 /recaptcha/?next=$request_uri;\
                        }' $config
        fi

        template='/usr/local/psa/admin/conf/templates/custom/domain/nginxDomainVirtualHost.php'
        if [ $(grep recaptcha $template | wc -l) -eq 0 ];then
                sed -i 's@#block bots@    location /recaptcha/ {\n        proxy_pass https://app.ddosnull.com:4433;\n                proxy_set_header X-Forwarded-Proto $scheme;\n                # send SNI to the HTTPS upstream\n                proxy_ssl_server_name on;\n                proxy_ssl_name app.ddosnull.com;\n                proxy_set_header Host app.ddosnull.com;\n                proxy_set_header X-Real-IP $remote_addr;\n                     proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n                }\n\n#block bots@g' $template;
        fi

        plesk sbin httpdmng --reconfigure-all

        # Setup crontab for Plesk
        ( crontab -l 2>/dev/null | grep -v -F "$PYTHON_CMD /opt/la-client/api_handler.py"; echo "* * * * * $PYTHON_CMD /opt/la-client/api_handler.py" ) | crontab -

        # Run api_handler.py and capture output to check for success
        echo ""
        echo "Testing connection to ddosNull API..."
        API_HANDLER_OUTPUT=$($PYTHON_CMD /opt/la-client/api_handler.py 2>&1)
        echo "$API_HANDLER_OUTPUT"

        # Check if output contains "Success"
        if echo "$API_HANDLER_OUTPUT" | grep -q "Success"; then
            INSTALLATION_SUCCESS="true"
            INSTALLATION_ERROR=""
            echo "✓ Successfully connected to ddosNull API"
        else
            INSTALLATION_SUCCESS="false"
            INSTALLATION_ERROR="API handler did not return success. Check output above."
            echo "⚠ Warning: API connection test did not return expected success message"
        fi

elif [ -f /usr/local/cpanel/version ]; then
        echo "cPanel detected: $(cat /usr/local/cpanel/version)"

        echo ">>> Checking for ea-nginx (cPanel Nginx)..."

        # Pick package manager
        PKG_MGR=$(command -v dnf 2>/dev/null || command -v yum)

        # 1. Is ea-nginx installed?
        if rpm -q ea-nginx >/dev/null 2>&1; then
            echo "ea-nginx is already installed."
        else
            echo "ea-nginx is NOT installed. Installing..."
            $PKG_MGR -y install ea-nginx || {
                echo "ERROR: Failed to install ea-nginx via $PKG_MGR"
                exit 1
            }
        fi

        # 2. Make sure the cPanel nginx script exists
        if [ ! -x /usr/local/cpanel/scripts/ea-nginx ]; then
            echo "ERROR: /usr/local/cpanel/scripts/ea-nginx not found."
            echo "Your cPanel version may be too old. Try: /scripts/upcp --force"
            exit 1
        fi

        # 3. Configure nginx for all accounts
        echo "Configuring ea-nginx for all accounts..."
        /usr/local/cpanel/scripts/ea-nginx config --all &> /dev/null

        # 4. Make sure nginx service is enabled & running
        echo "Enabling and starting nginx service..."
        systemctl enable nginx >/dev/null 2>&1 || true
        /usr/local/cpanel/scripts/restartsrv_nginx

        # 5. Final status
        if systemctl is-active --quiet nginx; then
            echo "ea-nginx installed and nginx is running as reverse proxy."
        else
            echo "WARNING: nginx service is not active. Check logs in /var/log/nginx/."
        fi


        echo '# ---- Whitelist ----
        geo $remote_addr $is_whitelisted_ip {
            include /etc/nginx/maps/whitelisted_ips.map;
        }

        # ---- Bot detection ----
        map $http_user_agent $is_bot {
            include /etc/nginx/maps/bot_user_agents.map;
        }

        # ---- Cookie check ----
        map $http_cookie $has_recaptcha_cookie {
            default 0;
            "~recaptcha_verified=1" 1;
        }

        # ---- Suspicious IPs ----
        geo $remote_addr $is_suspicious_ip {
            include /etc/nginx/maps/suspicious_ip.map;
        }

        # ---- Domain-based DDoS mode ----
        map $host $ddos_mode {
            include /etc/nginx/maps/ddos_mode.map;
        }

        # ---- NEW: Recaptcha path flag ----
        map $uri $is_recaptcha_path {
            default 0;
            ~^/recaptcha(/|$) 1;
        }

        # ---- Combined decision ----
        # Key order: bot : cookie : ddos : suspicious : whitelisted : recaptcha_path
        map "$is_bot:$has_recaptcha_cookie:$ddos_mode:$is_suspicious_ip:$is_whitelisted_ip:$is_recaptcha_path" $needs_recaptcha {
            default 0;

            # Skip for bots
            "~^1:.*"             0;

            # Skip if IP is whitelisted
            "~^.*:.*:.*:.*:1:."  0;

            # Skip if cookie present
            "~^.:1:.:.:.:."      0;

            # Skip if hitting recaptcha path
            "~^.*:.*:.*:.*:.*:1" 0;

            # Force check: DDoS ON or suspicious IP and no cookie
            "~^0:0:1:.:0:0"      1;
            "~^0:0:.:1:0:0"      1;

            # All others: allow
            "~^0:0:0:0:0:0"      0;
        }
        ' > /etc/nginx/conf.d/ddosnull.conf
        echo '    location /recaptcha/ {
                proxy_pass https://app.ddosnull.com:4433;
                        proxy_set_header X-Forwarded-Proto $scheme;
                        # send SNI to the HTTPS upstream
                        proxy_ssl_server_name on;
                        proxy_ssl_name app.ddosnull.com;
                        proxy_set_header Host app.ddosnull.com;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            }

        if ($needs_recaptcha = 1) {
                return 302 /recaptcha/?next=$request_uri;
        }' > /etc/nginx/conf.d/server-includes/ddosnull.conf

        echo 'server {
            listen 127.0.0.1:80;
            server_name localhost;

            location /nginx_status {
                stub_status;
                allow 127.0.0.1;
                deny all;
            }
        }' > /etc/nginx/conf.d/stats.conf


        mkdir /etc/nginx/maps/
        echo 'default 0;

        safe.com    0;
        test.com    1;' > /etc/nginx/maps/ddos_mode.map

        echo 'default 0;
        127.127.127.127 1;' >  /etc/nginx/maps/suspicious_ip.map

        echo 'default 0;

        ~*googlebot        1;
        ~*bingbot          1;
        ~*yahoo            1;
        ~*rackspace      1;' > /etc/nginx/maps/bot_user_agents.map

        echo 'default 0;' > /etc/nginx/maps/whitelisted_ips.map
        /usr/bin/systemctl reload nginx

        /usr/local/cpanel/scripts/ea-nginx config --all &> /dev/null

        # Setup crontab for cPanel
        ( crontab -l 2>/dev/null | grep -v -F "$PYTHON_CMD /opt/la-client/api_handler.py"; echo "* * * * * $PYTHON_CMD /opt/la-client/api_handler.py" ) | crontab -

        # Run api_handler.py and capture output to check for success
        echo ""
        echo "Testing connection to ddosNull API..."
        API_HANDLER_OUTPUT=$($PYTHON_CMD /opt/la-client/api_handler.py 2>&1)
        echo "$API_HANDLER_OUTPUT"

        # Check if output contains "Success"
        if echo "$API_HANDLER_OUTPUT" | grep -q "Success"; then
            INSTALLATION_SUCCESS="true"
            INSTALLATION_ERROR=""
            echo "✓ Successfully connected to ddosNull API"
        else
            INSTALLATION_SUCCESS="false"
            INSTALLATION_ERROR="API handler did not return success. Check output above."
            echo "⚠ Warning: API connection test did not return expected success message"
        fi

else
    echo "Neither Plesk nor cPanel detected"
    echo "ERROR: Installation failed - no supported control panel found"
    INSTALLATION_SUCCESS="false"
    INSTALLATION_ERROR="Neither Plesk nor cPanel detected. Installation requires a supported control panel."
fi

# Function to send installation log to API
send_installation_log() {

    # Get system information
    OS_INFO=$(uname -a 2>/dev/null || echo "unknown")
    PYTHON_VERSION=$("$PYTHON_CMD" --version 2>&1 || echo "unknown")

    # Detect panel type and version
    if [ -f /usr/local/psa/version ]; then
        PANEL_TYPE="plesk"
        PANEL_VERSION=$(cat /usr/local/psa/version 2>/dev/null || echo "unknown")
    elif [ -f /usr/local/cpanel/version ]; then
        PANEL_TYPE="cpanel"
        PANEL_VERSION=$(cat /usr/local/cpanel/version 2>/dev/null || echo "unknown")
    else
        PANEL_TYPE="unknown"
        PANEL_VERSION="N/A"
    fi

    # Get server IP (non-blocking, use default if fails)
    if command -v curl >/dev/null 2>&1; then
        SERVER_IP=$(timeout 5 curl -s https://api.ipify.org 2>/dev/null || echo "unknown")
    elif command -v wget >/dev/null 2>&1; then
        SERVER_IP=$(timeout 5 wget -qO- https://api.ipify.org 2>/dev/null || echo "unknown")
    else
        SERVER_IP="unknown"
    fi

    # Send log to API (this should not block or fail the installation)
    $PYTHON_CMD - <<PYEOF 2>/dev/null || true
import json
import sys

try:
    import requests
except ImportError:
    print("Installation log saved locally (requests module not available)")
    sys.exit(0)

# Read the log content
try:
    with open("$INSTALL_LOG", "r") as f:
        log_content = f.read()
except:
    log_content = "Could not read log file"

# Convert bash boolean to Python boolean
success = "$INSTALLATION_SUCCESS" == "true"

payload = {
    "datatype": "installation_log",
    "instance_id": "$INSTANCE_ID",
    "installation_output": log_content,
    "success": success,
    "error_message": "$INSTALLATION_ERROR",
    "server_ip": "$SERVER_IP",
    "os_info": "$OS_INFO",
    "python_version": "$PYTHON_VERSION",
    "panel_type": "$PANEL_TYPE",
    "panel_version": "$PANEL_VERSION"
}

# Single attempt to send log
try:
    response = requests.post(
        "https://app.ddosnull.com:4433/api/",
        json=payload,
        timeout=10,
        verify=True
    )
    if response.status_code == 200:
        print("✓ Installation log sent to ddosNull API")
    else:
        print(f"Log saved locally (HTTP {response.status_code})")
except:
    print("Log saved locally (connection failed)")
PYEOF

    # Always clean up log file after attempting to send
    rm -f "$INSTALL_LOG" 2>/dev/null || true
}

# Send the installation log
send_installation_log

echo ""
echo "=== Installation completed at $(date) ==="
