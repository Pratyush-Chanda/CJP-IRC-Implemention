# Setting Up the Cockroach Janta Party (CJP) IRC Server

This guide walks through running a lightweight IRC server using **ngIRCd**, enabling **TLS encryption**, and exposing it to the internet using a **bore** tunnel — so CJP members anywhere in the country can connect, even if your machine has no public IP.

Instructions are provided for:
- **Termux (Android)**
- **Debian/Ubuntu-based distros** (apt)
- **Fedora/RHEL-based distros** (dnf)
- **Arch-based distros** (pacman)

---

## 1. Install ngIRCd

### Termux (Android)
```bash
pkg update && pkg upgrade -y
pkg install ngircd nano -y
```

### Debian / Ubuntu
```bash
sudo apt update
sudo apt install ngircd nano -y
```

### Fedora / RHEL / CentOS Stream
```bash
sudo dnf install ngircd nano -y
```

### Arch / Manjaro
```bash
sudo pacman -Syu ngircd nano
```

---

## 2. Locate the Config File

| Platform        | Config Path                                              |
|------------------|----------------------------------------------------------|
| Termux           | `$PREFIX/etc/ngircd.conf` (i.e. `/data/data/com.termux/files/usr/etc/ngircd.conf`) |
| Debian/Ubuntu    | `/etc/ngircd/ngircd.conf`                                |
| Fedora/RHEL      | `/etc/ngircd.conf`                                       |
| Arch             | `/etc/ngircd.conf`                                       |

Edit it with:
```bash
nano <path-to-config>
```
(Use `sudo nano <path>` on non-Termux systems if the file isn't user-writable.)

---

## 3. Basic Configuration

In the `[Global]` section, set:

```ini
[Global]
    Name = irc.cjp.local
    Info = Cockroach Janta Party IRC Server
    AdminInfo1 = Run by CJP
    Ports = 6667
```

If a `Listen` directive restricts the server to `127.0.0.1` and you want it reachable from other devices on your network, comment it out or remove it:
```ini
;Listen = 127.0.0.1
```

---

## 4. Run the Server

### Termux
```bash
ngircd -n -f $PREFIX/etc/ngircd.conf
```

### Debian/Ubuntu (systemd)
```bash
sudo systemctl enable --now ngircd
sudo systemctl status ngircd
```
Or run manually in the foreground for testing:
```bash
sudo ngircd -n -f /etc/ngircd/ngircd.conf
```

### Fedora/RHEL/Arch (systemd)
```bash
sudo systemctl enable --now ngircd
```
Or manually:
```bash
sudo ngircd -n -f /etc/ngircd.conf
```

The `-n` flag runs ngIRCd in the foreground with logs visible — useful for debugging. Drop it (and use systemd or `&`/`nohup`/`tmux`) once everything works.

---

## 5. Test Locally

Install an IRC client to test:

```bash
# Termux
pkg install irssi -y

# Debian/Ubuntu
sudo apt install irssi -y

# Fedora
sudo dnf install irssi -y

# Arch
sudo pacman -S irssi
```

Connect:
```bash
irssi -c 127.0.0.1 -p 6667
```

Inside irssi:
```
/join #test
```

Open a second terminal/session, connect again with a different nick, join the same channel, and confirm messages appear in both.

---

## 6. Enable TLS Encryption (Trusted Certificate via Let's Encrypt)

Rather than a self-signed certificate (which causes "untrusted" or "bad certificate" warnings on many clients, especially mobile apps like Goguma), we'll use **acme.sh** to get a real, browser/client-trusted certificate from Let's Encrypt — validated via DuckDNS's DNS API, so no public-facing web server is required.

### Prerequisite: a DuckDNS subdomain
Create one at [duckdns.org](https://www.duckdns.org) (e.g. `cjp-test-irc.duckdns.org`) and note your **token** from the dashboard (top of the page after logging in).

### Install acme.sh

```bash
curl https://get.acme.sh | sh -s email=youremail@example.com
```

If you see a warning about `crontab` not being available (common on Termux), it's safe to ignore — it just means certificate renewal won't happen automatically and you'll need to renew manually every ~60 days (see Section 8).

Reload your shell so the `acme.sh` alias is available:
```bash
source ~/.bashrc
```

(On non-Termux distros, `cron`/`crontab` is usually already installed, so acme.sh sets up auto-renewal for you.)

### Issue the certificate using DuckDNS DNS validation

```bash
export DuckDNS_Token="your-duckdns-token-here"
acme.sh --issue --dns dns_duckdns -d cjp-test-irc.duckdns.org
```

acme.sh will automatically set the required DNS TXT record via DuckDNS's API, wait for validation, and issue the cert. On success it prints the paths to your certificate files, e.g.:

```
Your cert is in: ~/.acme.sh/cjp-test-irc.duckdns.org_ecc/cjp-test-irc.duckdns.org.cer
Your cert key is in: ~/.acme.sh/cjp-test-irc.duckdns.org_ecc/cjp-test-irc.duckdns.org.key
The full-chain cert is in: ~/.acme.sh/cjp-test-irc.duckdns.org_ecc/fullchain.cer
```

### Add an SSL section to ngircd.conf

Use the **fullchain** cert (includes the intermediate CA, required for clients to fully validate the chain):

```ini
[SSL]
    Ports = 6697
    CertFile = /data/data/com.termux/files/home/.acme.sh/cjp-test-irc.duckdns.org_ecc/fullchain.cer
    KeyFile = /data/data/com.termux/files/home/.acme.sh/cjp-test-irc.duckdns.org_ecc/cjp-test-irc.duckdns.org.key
```

> On non-Termux distros, adjust the path to wherever acme.sh stored the cert/key for your user (typically `~/.acme.sh/<domain>_ecc/`).

### Restart ngIRCd
- Termux: stop with `Ctrl+C`, then re-run `ngircd -n -f $PREFIX/etc/ngircd.conf`
- systemd distros: `sudo systemctl restart ngircd`

Check the startup log for lines confirming it's listening on port 6697 with no SSL errors.

### Test the TLS port locally
```bash
openssl s_client -connect 127.0.0.1:6697
```
With a real Let's Encrypt cert, this should show a clean verified chain (no "self-signed certificate" warning).

### Connect with TLS from a client
```bash
irssi
```
Then:
```
/connect -tls 127.0.0.1 6697
```
With a trusted cert, no warning prompt should appear.

---

## 7. Expose the Server Publicly with bore (Fixed Port + Stable Hostname)

[bore](https://github.com/ekzhang/bore) creates a public TCP tunnel to your local port — useful if your machine has no public IP (common on mobile networks behind CGNAT, etc.).

### Install bore

```bash
# Termux
pkg install bore-cli -y

# Debian/Ubuntu (via cargo, if not packaged)
sudo apt install cargo -y
cargo install bore-cli

# Fedora
sudo dnf install cargo -y
cargo install bore-cli

# Arch (available in AUR)
yay -S bore-cli
```

If installed via cargo, make sure `~/.cargo/bin` is in your `PATH`:
```bash
export PATH="$HOME/.cargo/bin:$PATH"
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
```

### Get a fixed public port

By default, `bore.pub` assigns a **random** port each time you start a tunnel. You can instead **request a specific port** with `--port`:

```bash
bore local 6697 --to bore.pub --port 56926
```

bore.pub will generally honor this request on each restart (as long as nothing else is using that port at that moment), giving you a **consistent port number** — `56926` in this example — across restarts.

### Point DuckDNS at bore.pub's IP

Since `bore.pub` itself has a stable public IP, you can set your DuckDNS hostname to point at it:

1. Find bore.pub's current IP:
   ```bash
   curl -4 ifconfig.io --resolve bore.pub:443:bore.pub
   # or simply:
   nslookup bore.pub
   ```
2. On the [DuckDNS dashboard](https://www.duckdns.org), set your subdomain's IP to bore.pub's IP address (e.g. `159.223.110.159`).

Now `cjp-test-irc.duckdns.org:56926` resolves to `bore.pub:56926`, which forwards through your tunnel to ngIRCd on your phone — giving you a **stable hostname AND a stable port**.

> ⚠️ **Notes:**
> - If bore.pub's IP ever changes, you'll need to update the DuckDNS record to match.
> - If you restart ngIRCd, also restart the `bore` tunnel (with the same `--port` flag) — an old tunnel pointing at a now-closed local connection will appear "alive" but stop working.
> - On mobile data, idle connections can occasionally drop due to carrier NAT timeouts. The `PingTimeout`/`PongTimeout` settings in Section 11 help keep the tunnel active when at least one client is connected.

### Auto-restart script

To automatically restart both ngIRCd and the bore tunnel (e.g. after a phone reboot or a dropped connection), save this as `start-cjp-irc.sh`:

```bash
ngircd -n -f $PREFIX/etc/ngircd.conf &
sleep 5
echo -------------------------
echo "exposing irc to public..."
echo -------------------------
while true; do
    bore local 6697 --to bore.pub --port 56926
    clear
    echo -------------------
    echo "bore disconnected, restarting..."
    echo -------------------
done
```

Make it executable and run it:
```bash
chmod +x start-cjp-irc.sh
./start-cjp-irc.sh
```

---

## 8. Connection Details to Share with CJP Members

Give members:

- **Server:** `cjp-test-irc.duckdns.org`
- **Port:** `56926`
- **Connection type:** TLS/SSL **required**
- **Certificate:** trusted (Let's Encrypt) — no security warnings on properly TLS-supporting clients
- **Main channel:** `#cjp`

### Example client setup

**irssi / WeeChat (terminal):**
```
/connect -tls cjp-test-irc.duckdns.org 56926
```

**HexChat / GUI clients:**
- Server: `cjp-test-irc.duckdns.org`
- Port: `56926`
- Enable "Use SSL/TLS for this server"
- "Accept invalid SSL certificate" is **not needed** (cert is trusted)

**Mobile clients (Goguma, etc.):**
- Use the `ircs://` scheme or enable the "Secure connection / TLS" toggle
- Host: `cjp-test-irc.duckdns.org`, Port: `56926`

> Some clients (e.g. IrisChat from F-Droid) may not support TLS at all and will fail to connect to port 6697/56926 — if a member's client lacks TLS support, recommend switching to a client that supports it (e.g. Goguma, irssi/WeeChat, HexChat, The Lounge).

---

## 9. Renewing the TLS Certificate

Let's Encrypt certificates are valid for **90 days**. Since Termux typically lacks `cron`, acme.sh can't auto-renew — set a reminder to run this manually every **~60 days**:

```bash
acme.sh --renew -d cjp-test-irc.duckdns.org --dns dns_duckdns
```

Then restart ngIRCd (and the bore tunnel) to pick up the renewed certificate. On non-Termux distros with `cron` available, acme.sh sets up automatic renewal during install, so this step usually isn't needed.

---

## 10. Configuring Channels

Channels can be created on-the-fly with `/join #channelname`, or pre-defined for persistence:

```ini
[Channel]
    Name = #cjp
    Topic = Welcome to the Cockroach Janta Party! General discussion here.
    Modes = tn

[Channel]
    Name = #cjp-help
    Topic = Ask questions about the CJP server here.
    Modes = tn
```

Common mode flags:
- `t` — only ops can change topic
- `n` — must be in channel to send messages
- `m` — moderated (only voiced/op can speak)
- `s` — secret (hidden from `/list`)
- `k` — requires a password (set with `Key = ...`)
- `l` — user limit (set with `MaxUsers = ...`)

Restart ngIRCd after editing.

---

## 11. Becoming a Server Operator

Add to the config:
```ini
[Operator]
    Name = admin
    Password = yourpassword
```

Then in your client:
```
/oper admin yourpassword
```

Once oper'd, you can grant yourself channel-op status:
```
/op YourNick
```
giving you the ability to kick, ban, set topics, and manage channel modes.

---

## 12. Increasing Limits (e.g. Nickname Length) & Keeping the Tunnel Alive

Add a `[Limits]` section:
```ini
[Limits]
    MaxNickLength = 20
    PingTimeout = 60
    PongTimeout = 20
```

- `MaxNickLength` — allows longer nicknames (some clients enforce their own limit regardless)
- `PingTimeout` — ngIRCd pings connected clients every 60s of inactivity, which helps generate traffic to keep the bore tunnel's NAT mapping alive on mobile data
- `PongTimeout` — disconnects clients that don't respond to a PING within 20s

Restart ngIRCd for changes to apply. Note that ping traffic only flows while at least one client is connected — if the server is completely empty for long stretches on mobile data, the tunnel may still occasionally need a restart.

---

## 13. Keeping the Server Running (Termux-specific)

On Android, background processes get killed aggressively. To keep things running:

```bash
termux-wake-lock
```

Run the `start-cjp-irc.sh` script (from Section 7) inside `tmux` so it survives even if the Termux app is closed:
```bash
pkg install tmux -y
tmux new -s irc
./start-cjp-irc.sh
```
Detach with `Ctrl+B` then `D` — it keeps running in the background. Reattach anytime with `tmux attach -t irc`.

Also disable battery optimization for Termux in Android's app settings.

On regular Linux distros with systemd, ngIRCd can simply be enabled as a service (see Section 4) and will start on boot / restart on failure automatically. For `bore`, consider a systemd user service or a simple restart loop script if you need it to persist.

---

## Notes & Limitations

- **Stable hostname + port achieved**: by requesting a fixed port from `bore.pub` (`--port`) and pointing DuckDNS at `bore.pub`'s own IP, `cjp-test-irc.duckdns.org:56926` stays consistent across restarts — no VPS required.
- **Trusted TLS certificate**: using acme.sh + DuckDNS's DNS API to get a Let's Encrypt cert means clients (including strict mobile apps) connect without certificate warnings.
- **Mobile data caveats**: carrier CGNAT can drop idle tunnels. `PingTimeout`/`PongTimeout` settings help when at least one client is connected; if the server is empty for long periods, the tunnel may occasionally need restarting.
- **Certificate renewal**: Let's Encrypt certs last 90 days. On Termux (no cron), renew manually every ~60 days with `acme.sh --renew`.
- **If `bore.pub`'s IP ever changes**, update the DuckDNS A record to match, or the hostname will stop resolving to the right relay.
- **For a fully maintenance-free setup** (no manual cert renewal, no occasional tunnel restarts, no dependency on bore.pub's IP staying the same), running ngIRCd directly on a free-tier cloud VM (e.g. Oracle Cloud's Always Free ARM instances) remains the most robust long-term option — but is not required for the current working setup.
