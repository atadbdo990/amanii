# ⚡ Amani
**Xray on Google Cloud Run — VLESS / VMess / Trojan**

👤 `@amona_mora` · 📣 [t.me/amona_mora](https://t.me/amona_mora)

---

## Transparency — read this before running

| Item | Status |
|---|---|
| Connects to a third-party server | ❌ **No** |
| Telemetry / usage reporting | ❌ **No** |
| Sends your links or UUID to anyone | ❌ **No** |
| Deletes files from your machine | ❌ **No** |
| Hardcoded credentials in the repo | ❌ **None** |
| Telegram token stored on the server | ❌ **No** — client-side only |
| Only outbound call | `api.telegram.org` — **your** bot, **your** chat, only if you configure it |
| Default cost limits | `min-instances=0`, `max=1`, `512MB` |
| Teardown command | `./install.sh delete <service> <region>` |

Verify it yourself — every one of these should return nothing:

```bash
grep -rn "deewaele\|youyoulofi1\|notify-admin\|workers.dev" .
grep -rn 'rm -rf "$script_dir"' .
```

> Began as a fork of `zalsofoy-dev/skysofo`. The upstream version posts
> every deployed subscription link to a third-party Cloudflare Worker using
> a hardcoded key, and deletes the directory it was launched from.
> **None of that exists here** — `install.sh`, `main.go`, `config.json.tpl`
> and `Dockerfile` were rewritten from scratch.

---

## Requirements
- `gcloud` SDK, authenticated, with a billing account attached
- `curl`, `git`, Linux / macOS / Google Cloud Shell

## Quick start
```bash
git clone https://github.com/atadbdo990/amanii.git && cd amanii
./install.sh
```

## Telegram auto-send (optional)

**Recommended — one-time setup, nothing to type later:**
```bash
cp amani.secrets.example amani.secrets
chmod 600 amani.secrets
nano amani.secrets          # fill BOT_TOKEN + CHAT_ID
./install.sh notify         # test it before deploying
./install.sh                # deploy → link arrives in your chat
```

**Or pass it per run:**
```bash
BOT_TOKEN="123:ABC..." \
CHAT_ID="123456789" \
./install.sh
```

> ⚠ No spaces inside the quotes — `"123:ABC "` (trailing space) is an invalid token.
> ⚠ Anything on the command line is saved to your shell history. Prefix the
>   command with a space, or use `amani.secrets`.
> ⚠ **Never** put your token in `install.sh` or `amani.conf` — both are public.

Get your chat ID: message [@userinfobot](https://t.me/userinfobot) on Telegram.

## Two modes
```bash
MODE=stealth ./install.sh   # ← default: random path, name only in #Amani
MODE=brand   ./install.sh   # /amani + amani-xxxx — visible, blockable
```
**Why stealth is the default:** the `#Amani` fragment never leaves the user's
device. A `/amani` path appears in every packet, so one filter rule would
take down every server you deploy.

## Commands
```bash
./install.sh notify                          # test Telegram only
./install.sh list                            # all your services
./install.sh delete amani-a1b2 us-central1   # stop billing
PROTO=trojan ./install.sh                    # pick protocol
MEMORY=1024 ./install.sh                     # override limits
ASSUME_YES=yes ./install.sh                  # non-interactive (CI)
```

## Cost warning
Cloud Run is **not free**. Defaults here are conservative (`min-instances=0`),
but set a budget alert first:
→ [console.cloud.google.com/budget](https://console.cloud.google.com/budget)

## Customising
All naming lives in **`amani.conf`**. All secrets live in **`amani.secrets`**.
You should never need to edit `install.sh`.

## License
MIT
