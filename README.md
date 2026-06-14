# Setting Up the Cockroach Janta Party (CJP) IRC Server

This guide walks through running a modern IRC server using **Ergo** (a full IRCv3-compliant IRCd), enabling **trusted TLS encryption** via Let's Encrypt, and exposing it to the internet using a **bore** tunnel with a stable hostname via **DuckDNS** — so CJP members anywhere in the country can connect without warnings or restrictions, even if your machine has no public IP.

Instructions are provided for:
- **Termux (Android)** — primary platform this guide was developed on
- **Debian/Ubuntu-based distros** (apt)
- **Fedora/RHEL-based distros** (dnf)
- **Arch-based distros** (pacman)

> **Why Ergo over ngIRCd?** Ergo has full IRCv3 support (message history, SASL, message tags, always-on clients, etc.), which modern mobile clients like Goguma require. ngIRCd is lightweight but lacks these features.

---

## 1. Install Dependencies

### Termux (Android)
```bash
pkg update && pkg upgrade -y
pkg install irssi nano curl openssl-tool -y
```

### Debian / Ubuntu
```bash
sudo apt update
sudo apt install irssi nano curl openssl -y
```

### Fedora / RHEL / CentOS Stream
```bash
sudo dnf install irssi nano curl openssl -y
```

### Arch / Manjaro
```bash
sudo pacman -Syu irssi nano curl openssl
```

---

## 2. Install Ergo

Ergo is distributed as a single prebuilt binary — no compilation needed.

### Termux (Android — ARM64)
```bash
cd ~
curl -L https://github.com/ergochat/ergo/releases/download/v2.18.0/ergo-2.18.0-linux-arm64.tar.gz -o ergo.tar.gz
tar xzf ergo.tar.gz
mkdir -p ~/bin
cp ~/ergo-2.18.0-linux-arm64/ergo ~/bin/ergo
export PATH="$HOME/bin:$PATH"
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
```

### Debian / Ubuntu / Fedora / RHEL (x86_64)
```bash
cd ~
curl -L https://github.com/ergochat/ergo/releases/download/v2.18.0/ergo-2.18.0-linux-x86_64.tar.gz -o ergo.tar.gz
tar xzf ergo.tar.gz
sudo cp ~/ergo-2.18.0-linux-x86_64/ergo /usr/local/bin/ergo
```

### Arch
```bash
# Available in AUR
yay -S ergochat
```

Verify the install:
```bash
ergo --version
```

---

## 3. Set Up Ergo's Config Directory

```bash
mkdir -p ~/.ergo
cp ~/ergo-2.18.0-linux-arm64/default.yaml ~/.ergo/ircd.yaml   # ARM64/Termux
# or for x86_64:
# cp ~/ergo-2.18.0-linux-x86_64/default.yaml ~/.ergo/ircd.yaml
cp ~/ergo-2.18.0-linux-arm64/ergo.motd ~/.ergo/ergo.motd
cp -r ~/ergo-2.18.0-linux-arm64/languages ~/.ergo/languages
```

---

## 4. Get a Trusted TLS Certificate (Let's Encrypt via acme.sh + DuckDNS)

Rather than a self-signed certificate (which causes "bad certificate" warnings on mobile clients like Goguma), we use **acme.sh** to issue a real Let's Encrypt cert — validated via DuckDNS's DNS API, so no public web server is needed.

### Prerequisite: a DuckDNS subdomain
Create one at [duckdns.org](https://www.duckdns.org) (e.g. `cjp-test-irc.duckdns.org`) and copy your **token** from the top of the dashboard after logging in.

### Install acme.sh

```bash
curl https://get.acme.sh | sh -s email=youremail@example.com --force
source ~/.bashrc
```

> On Termux, you'll see a warning about `crontab` not being available — this is expected. Certs won't auto-renew, so you'll need to renew manually every ~60 days (see Section 9).

### Issue the certificate

```bash
export DuckDNS_Token="your-duckdns-token-here"
acme.sh --issue --dns dns_duckdns -d cjp-test-irc.duckdns.org
```

acme.sh sets the required DNS TXT record automatically via DuckDNS's API, waits for validation, and issues the cert. On success it prints the cert paths — note them down, typically:

```
~/.acme.sh/cjp-test-irc.duckdns.org_ecc/fullchain.cer
~/.acme.sh/cjp-test-irc.duckdns.org_ecc/cjp-test-irc.duckdns.org.key
```

---

## 5. Configure Ergo

Edit the config:
```bash
nano ~/.ergo/ircd.yaml
```

Key things to set:

**Server name** (search for `name:` under `server:`):
```yaml
server:
    name: cjp-test-irc.duckdns.org
```

**TLS cert/key** (search for `fullchain.pem`):
```yaml
        tls:
            cert: /data/data/com.termux/files/home/.acme.sh/cjp-test-irc.duckdns.org_ecc/fullchain.cer
            key: /data/data/com.termux/files/home/.acme.sh/cjp-test-irc.duckdns.org_ecc/cjp-test-irc.duckdns.org.key
```

> On non-Termux distros, adjust the path to `~/.acme.sh/cjp-test-irc.duckdns.org_ecc/` using the full absolute path for your user.

Save and exit (`Ctrl+O`, Enter, `Ctrl+X`).

> **YAML note:** Ergo's config is YAML — indentation matters. Double-check that any lines you edit use spaces (not tabs) and match the surrounding indentation exactly. A common mistake is accidentally duplicating a key name (e.g. `name: name: ...`) which causes a parse error.

---

## 6. Initialize the Database and Start Ergo

```bash
cd ~/.ergo
ergo initdb --conf ircd.yaml
ergo run --conf ircd.yaml
```

On a successful start you'll see:
```
info : listeners : now listening on 127.0.0.1:6667, tls=false ...
info : listeners : now listening on :6697, tls=true ...
info : server     : Server running
```

---

## 7. Test Locally

In a second terminal session:
```bash
irssi
```
Then:
```
/connect -tls 127.0.0.1 6697
/join #cjp
```

To make channels persistent in Ergo (unlike ngIRCd, channels need to be registered):
```
/join #cjp
/CS REGISTER #cjp
```

---

## 8. Expose the Server Publicly with bore (Fixed Port + Stable Hostname)

[bore](https://github.com/ekzhang/bore) creates a public TCP tunnel to your local port — useful if your machine has no public IP (common on mobile networks behind CGNAT).

### Install bore

#### Termux
`bore-cli` is not available via `pkg`, so install via Rust/cargo:
```bash
pkg install rust -y
export PATH="$HOME/.cargo/bin:$PATH"
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
cargo install bore-cli
```
> This compilation step can take 5–15 minutes on a phone — be patient.

#### Debian / Ubuntu
```bash
sudo apt install cargo -y
cargo install bore-cli
export PATH="$HOME/.cargo/bin:$PATH"
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
```

#### Fedora
```bash
sudo dnf install cargo -y
cargo install bore-cli
export PATH="$HOME/.cargo/bin:$PATH"
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
```

#### Arch
```bash
yay -S bore-cli
```

### Start the tunnel with a fixed port

```bash
bore local 6697 --to bore.pub --port 56926
```

bore.pub generally honors the `--port` request on each restart, giving you a consistent port number (`56926` in this example) across restarts.

### Point DuckDNS at bore.pub's IP

Since `bore.pub` has a stable public IP, point your DuckDNS hostname at it:

1. Find bore.pub's current IP:
   ```bash
   nslookup bore.pub
   ```
2. On the [DuckDNS dashboard](https://www.duckdns.org), set your subdomain's current IP to bore.pub's IP (e.g. `159.223.110.159`).

Now `cjp-test-irc.duckdns.org:56926` resolves to `bore.pub:56926` which tunnels to your Ergo server — **stable hostname AND stable port, no VPS required**.

> ⚠️ **Notes:**
> - If bore.pub's IP ever changes, update the DuckDNS record.
> - If you restart Ergo, also restart the bore tunnel — a stale tunnel appears alive but stops working.
> - On mobile data, idle carrier NAT can occasionally drop the tunnel. This is less of an issue with Ergo since connected clients generate regular IRCv3 keepalive traffic.

---

## 9. Connection Details to Share with CJP Members

- **Server:** `cjp-test-irc.duckdns.org`
- **Port:** `56926`
- **TLS/SSL:** required (no certificate warning — trusted Let's Encrypt cert)
- **Main channel:** `#cjp`

### Client setup examples

**irssi / WeeChat (terminal):**
```
/connect -tls cjp-test-irc.duckdns.org 56926
```

**HexChat / GUI clients:**
- Server: `cjp-test-irc.duckdns.org`, Port: `56926`
- Enable "Use SSL/TLS"
- No need to accept invalid cert warnings

**Goguma / mobile clients:**
- Enable TLS/secure connection toggle
- Host: `cjp-test-irc.duckdns.org`, Port: `56926`
- Full IRCv3 features (message history, notifications, etc.) work out of the box with Ergo

> **Note:** Some clients (e.g. IrisChat from F-Droid) lack TLS support entirely and cannot connect. Recommend Goguma, irssi, WeeChat, or HexChat for members.

---

## 10. Renewing the TLS Certificate

Let's Encrypt certs are valid for **90 days**. On Termux (no cron), renew manually every ~60 days:

```bash
export DuckDNS_Token="your-token-here"
acme.sh --renew -d cjp-test-irc.duckdns.org --dns dns_duckdns
```

Then restart Ergo to pick up the new cert. On non-Termux distros with cron, acme.sh sets up auto-renewal automatically.

---

## 11. Auto-Restart Script (Termux)

Save this as `~/start-cjp-irc.sh`:

```bash
#!/data/data/com.termux/files/usr/bin/bash
export PATH="$HOME/bin:$HOME/.cargo/bin:$PATH"

# Start Ergo in background
ergo run --conf ~/.ergo/ircd.yaml &
sleep 5

echo "-------------------------"
echo "exposing irc to public..."
echo "-------------------------"

# Keep bore running with auto-restart
while true; do
    bore local 6697 --to bore.pub --port 56926
    clear
    echo "-------------------"
    echo "bore disconnected, restarting..."
    echo "-------------------"
done
```

Make it executable:
```bash
chmod +x ~/start-cjp-irc.sh
```

---

## 12. Keeping the Server Running (Termux-specific)

Android aggressively kills background processes. To prevent this:

```bash
termux-wake-lock
```

Run the start script inside `tmux` so it survives the Termux app being closed:
```bash
pkg install tmux -y
tmux new -s irc
bash ~/start-cjp-irc.sh
```

Detach with `Ctrl+B` then `D`. Reattach anytime with:
```bash
tmux attach -t irc
```

Also go to Android Settings → Apps → Termux → Battery and set it to **Unrestricted** to prevent Android from killing it.

---

## 13. Managing Channels and Users in Ergo

Unlike ngIRCd, Ergo uses built-in services (`ChanServ`, `NickServ`) for persistent management.

### Register a channel
```
/join #cjp
/CS REGISTER #cjp
```

### Register your nickname (recommended for admins)
```
/NS REGISTER yourpassword youremail@example.com
```

### Set yourself as channel operator
```
/CS OP #cjp YourNick
```

### Set channel topic (as op)
```
/topic #cjp Welcome to the Cockroach Janta Party!
```

### Make a channel auto-op you on join
```
/CS AMODE #cjp +o YourNick
```

---

## Notes & Limitations

- **Stable hostname + port**: by requesting a fixed port from `bore.pub` (`--port 56926`) and pointing DuckDNS at bore.pub's IP, `cjp-test-irc.duckdns.org:56926` stays consistent across restarts — no VPS required.
- **Trusted TLS**: acme.sh + DuckDNS DNS challenge gives a real Let's Encrypt cert — no certificate warnings on any properly implemented client.
- **Full IRCv3**: Ergo supports message history, SASL, always-on clients, push notifications (via Goguma), and more — unlike ngIRCd.
- **Mobile data caveats**: carrier CGNAT can occasionally drop idle tunnels. Ergo's built-in keepalive traffic helps when clients are connected.
- **Certificate renewal**: Let's Encrypt certs last 90 days. On Termux (no cron), renew manually every ~60 days.
- **If bore.pub's IP changes**, update the DuckDNS A record to match.
- **For a fully maintenance-free setup**, running Ergo directly on a free-tier cloud VM (e.g. Oracle Cloud Always Free ARM instances) avoids tunnels, port changes, and cert renewal reminders entirely — but is not required for the current working setup.
