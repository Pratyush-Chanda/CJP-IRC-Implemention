#!/data/data/com.termux/files/usr/bin/bash
#
# CJP IRC Server - Termux Setup Script
# Automates: ngIRCd install, bore install, Let's Encrypt cert via acme.sh + DuckDNS,
# SSL config, channels, and a start script.
#
# Run with: bash setup-cjp-irc-termux.sh
#

set -e

echo "==============================================="
echo " CJP IRC Server Setup (Termux)"
echo "==============================================="

# ---- Gather info ----
read -rp "Enter your DuckDNS domain (e.g. cjp-test-irc.duckdns.org): " DUCKDNS_DOMAIN
read -rp "Enter your DuckDNS token: " DUCKDNS_TOKEN
read -rp "Enter your email (for Let's Encrypt): " LE_EMAIL
read -rp "Enter desired fixed bore port (e.g. 56926): " BORE_PORT
read -rp "Enter an oper username [admin]: " OPER_NAME
OPER_NAME=${OPER_NAME:-admin}
read -rsp "Enter an oper password: " OPER_PASS
echo

CONF="$PREFIX/etc/ngircd.conf"

# ---- 1. Install packages ----
echo
echo "--- Installing packages (ngircd, openssl, irssi, bore-cli) ---"
pkg update -y
pkg install -y ngircd openssl-tool irssi bore-cli nano curl

# ---- 2. Install acme.sh ----
echo
echo "--- Installing acme.sh ---"
if [ ! -d "$HOME/.acme.sh" ]; then
    curl https://get.acme.sh | sh -s email="$LE_EMAIL" --force
fi
# shellcheck disable=SC1090
source "$HOME/.bashrc" 2>/dev/null || true
ACME="$HOME/.acme.sh/acme.sh"

# ---- 3. Issue certificate via DuckDNS DNS challenge ----
echo
echo "--- Issuing Let's Encrypt certificate for $DUCKDNS_DOMAIN ---"
export DuckDNS_Token="$DUCKDNS_TOKEN"
"$ACME" --issue --dns dns_duckdns -d "$DUCKDNS_DOMAIN" || {
    echo "Certificate issuance failed. Check your DuckDNS domain/token and try again."
    exit 1
}

CERT_DIR="$HOME/.acme.sh/${DUCKDNS_DOMAIN}_ecc"
FULLCHAIN="$CERT_DIR/fullchain.cer"
KEYFILE="$CERT_DIR/${DUCKDNS_DOMAIN}.key"

# ---- 4. Write ngircd.conf ----
echo
echo "--- Writing $CONF ---"
cat > "$CONF" <<EOF
[Global]
    Name = irc.cjp.local
    Info = Cockroach Janta Party IRC Server
    AdminInfo1 = Run by CJP
    Ports = 6667

[SSL]
    Ports = 6697
    CertFile = $FULLCHAIN
    KeyFile = $KEYFILE

[Limits]
    MaxNickLength = 20
    PingTimeout = 60
    PongTimeout = 20

[Operator]
    Name = $OPER_NAME
    Password = $OPER_PASS

[Channel]
    Name = #cjp
    Topic = Welcome to the Cockroach Janta Party! General discussion here.
    Modes = tn

[Channel]
    Name = #cjp-help
    Topic = Ask questions about the CJP server here.
    Modes = tn
EOF

echo "Config written to $CONF"

# ---- 5. Write the start script ----
echo
echo "--- Writing start-cjp-irc.sh ---"
cat > "$HOME/start-cjp-irc.sh" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
ngircd -n -f $CONF &
sleep 5
echo -------------------------
echo "exposing irc to public..."
echo -------------------------
while true; do
    bore local 6697 --to bore.pub --port $BORE_PORT
    clear
    echo -------------------
    echo "bore disconnected, restarting..."
    echo -------------------
done
EOF
chmod +x "$HOME/start-cjp-irc.sh"

# ---- 6. Done ----
echo
echo "==============================================="
echo " Setup complete!"
echo "==============================================="
echo "Connection details for CJP members:"
echo "  Server: $DUCKDNS_DOMAIN"
echo "  Port:   $BORE_PORT"
echo "  TLS:    required (trusted Let's Encrypt cert)"
echo "  Channel: #cjp"
echo
echo "To start the server, run:"
echo "  termux-wake-lock"
echo "  ./start-cjp-irc.sh"
echo
echo "(Recommended: run inside tmux so it survives backgrounding:"
echo "  pkg install tmux -y && tmux new -s irc"
echo "  ./start-cjp-irc.sh"
echo "  then Ctrl+B, D to detach)"
echo
echo "NOTE: On the DuckDNS dashboard, make sure $DUCKDNS_DOMAIN's IP"
echo "is set to bore.pub's current IP address (run: nslookup bore.pub)."
echo
echo "Renew the TLS cert every ~60 days with:"
echo "  $ACME --renew -d $DUCKDNS_DOMAIN --dns dns_duckdns"
echo "then restart start-cjp-irc.sh."
