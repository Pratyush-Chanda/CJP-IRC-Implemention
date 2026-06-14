#!/data/data/com.termux/files/usr/bin/bash
#
# CJP IRC Server - Termux Setup Script
# Installs Ergo (IRCv3 IRC server), bore (TCP tunnel via cargo/rust),
# and acme.sh + DuckDNS for a trusted Let's Encrypt TLS certificate.
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

# ---- 1. Install base packages ----
echo
echo "--- Installing base packages ---"
pkg update -y
pkg install -y irssi nano curl openssl-tool rust

# ---- 2. Install bore via cargo ----
echo
echo "--- Installing bore-cli via cargo (may take several minutes on a phone) ---"
export PATH="$HOME/.cargo/bin:$PATH"
if ! command -v bore &>/dev/null; then
    cargo install bore-cli
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$HOME/.bashrc"
else
    echo "bore already installed, skipping."
fi

# ---- 3. Download Ergo binary ----
echo
echo "--- Downloading Ergo v2.18.0 (ARM64) ---"
cd ~
curl -L https://github.com/ergochat/ergo/releases/download/v2.18.0/ergo-2.18.0-linux-arm64.tar.gz -o ergo.tar.gz
tar xzf ergo.tar.gz
mkdir -p ~/bin
cp ~/ergo-2.18.0-linux-arm64/ergo ~/bin/ergo
export PATH="$HOME/bin:$PATH"
echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"

# ---- 4. Set up Ergo config directory ----
echo
echo "--- Setting up Ergo config directory ---"
mkdir -p ~/.ergo
cp ~/ergo-2.18.0-linux-arm64/default.yaml ~/.ergo/ircd.yaml
cp ~/ergo-2.18.0-linux-arm64/ergo.motd ~/.ergo/ergo.motd
cp -r ~/ergo-2.18.0-linux-arm64/languages ~/.ergo/languages

# ---- 5. Install acme.sh ----
echo
echo "--- Installing acme.sh ---"
if [ ! -d "$HOME/.acme.sh" ]; then
    curl https://get.acme.sh | sh -s email="$LE_EMAIL" --force
fi
source "$HOME/.bashrc" 2>/dev/null || true
ACME="$HOME/.acme.sh/acme.sh"

# ---- 6. Issue Let's Encrypt certificate via DuckDNS ----
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

# ---- 7. Patch ircd.yaml ----
echo
echo "--- Configuring Ergo ---"

# Fix server name (avoid duplicate key issue)
sed -i "s/name: ErgoTest/name: $DUCKDNS_DOMAIN/" ~/.ergo/ircd.yaml

# Fix TLS cert/key paths
sed -i "s|cert: fullchain.pem|cert: $FULLCHAIN|" ~/.ergo/ircd.yaml
sed -i "s|key: privkey.pem|key: $KEYFILE|" ~/.ergo/ircd.yaml

echo "Ergo config written to ~/.ergo/ircd.yaml"

# ---- 8. Initialize Ergo database ----
echo
echo "--- Initializing Ergo database ---"
cd ~/.ergo
ergo initdb --conf ircd.yaml

# ---- 9. Write the start script ----
echo
echo "--- Writing ~/start-cjp-irc.sh ---"
cat > "$HOME/start-cjp-irc.sh" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
export PATH="\$HOME/bin:\$HOME/.cargo/bin:\$PATH"

# Start Ergo in background
ergo run --conf ~/.ergo/ircd.yaml &
sleep 5

echo "-------------------------"
echo "exposing irc to public..."
echo "-------------------------"

# Keep bore running with auto-restart
while true; do
    bore local 6697 --to bore.pub --port $BORE_PORT
    clear
    echo "-------------------"
    echo "bore disconnected, restarting..."
    echo "-------------------"
done
EOF
chmod +x "$HOME/start-cjp-irc.sh"

# ---- 10. Done ----
echo
echo "==============================================="
echo " Setup complete!"
echo "==============================================="
echo
echo "Connection details for CJP members:"
echo "  Server:  $DUCKDNS_DOMAIN"
echo "  Port:    $BORE_PORT"
echo "  TLS:     required (trusted Let's Encrypt cert)"
echo "  Channel: #cjp (register with /CS REGISTER #cjp after joining)"
echo
echo "IMPORTANT: On the DuckDNS dashboard, set $DUCKDNS_DOMAIN's IP"
echo "to bore.pub's IP address. Run: nslookup bore.pub to find it."
echo
echo "To start the server:"
echo "  termux-wake-lock"
echo "  pkg install tmux -y && tmux new -s irc"
echo "  bash ~/start-cjp-irc.sh"
echo "  then Ctrl+B, D to detach"
echo
echo "Renew the TLS cert every ~60 days:"
echo "  export DuckDNS_Token=\"$DUCKDNS_TOKEN\""
echo "  $ACME --renew -d $DUCKDNS_DOMAIN --dns dns_duckdns"
echo "then restart start-cjp-irc.sh."
