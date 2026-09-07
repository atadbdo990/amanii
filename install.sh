#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  Amani — Xray on Google Cloud Run
#  @amona_mora
#
#  No external server. No telemetry. No phoning home.
#  The only outbound call is api.telegram.org — and only if you
#  explicitly choose it at the prompt.
# ══════════════════════════════════════════════════════════════
set -euo pipefail
umask 077

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$HERE/amani.conf" ]]; then
  # shellcheck source=amani.conf
  source "$HERE/amani.conf"
fi

# ── Defaults if the conf file is missing ───────────────────────
: "${BRAND_NAME:=Amani}"
: "${BRAND_HANDLE:=@amona_mora}"
: "${BRAND_CHANNEL:=https://t.me/amona_mora}"
: "${BRAND_FRAGMENT:=Amani}"
: "${BRAND_TAG:=amani-in}"
: "${BRAND_SERVICE_PREFIX:=amani}"
: "${BRAND_PATH:=/amani}"
: "${MODE:=stealth}"
: "${MEMORY:=512}"
: "${CPU:=1}"
: "${MIN_INSTANCES:=0}"
: "${MAX_INSTANCES:=1}"
: "${CONCURRENCY:=80}"
: "${TIMEOUT:=900}"
: "${XRAY_VERSION:=25.3.6}"
: "${PASSWORD:=}"

R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m'
M='\033[0;35m' B='\033[1m' D='\033[2m' N='\033[0m'

say(){  echo -e "${C}${B}›${N} $1"; }
ok(){   echo -e "${G}${B}✓${N} $1"; }
warn(){ echo -e "${Y}${B}⚠${N} $1"; }
die(){  echo -e "${R}${B}✗${N} $1" >&2; exit 1; }

banner(){
  echo -e "\n${M}${B}╔════════════════════════════════════════════════╗${N}"
  echo -e "${M}${B}║      ${G}⚡ ${BRAND_NAME}${M}${B}    ${D}${BRAND_HANDLE}${N}${M}${B}              ║${N}"
  echo -e "${M}${B}║      ${D}Xray on Google Cloud Run${N}${M}${B}                 ║${N}"
  echo -e "${M}${B}╚════════════════════════════════════════════════╝${N}\n"
}

# ── Random hex, SIGPIPE-safe with layered fallbacks ────────────
rand_hex(){
  local n=$1 r=""
  r="$(head -c $((n+8)) /dev/urandom 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n' | head -c "$n" || true)"
  [[ ${#r} -ge $n ]] || r="$(tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c "$n" || true)"
  [[ ${#r} -ge $n ]] || r="$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | head -c "$n" || true)"
  while [[ ${#r} -lt $n ]]; do r+="$(printf '%04x' $(( (RANDOM + 1) * 4093 % 65536 )))"; done
  printf '%s' "${r:0:$n}"
}

# ── Cleanup: removes ONLY the mktemp dir we created ─────────────
#    (The original ran rm -rf on the folder it was launched from.)
WORKDIR=""
cleanup(){
  [[ -n "$WORKDIR" && -d "$WORKDIR" ]] && rm -rf -- "$WORKDIR"
}
trap cleanup EXIT

require(){ command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

usage(){
  cat <<EOF
${BRAND_NAME} ${BRAND_HANDLE} — usage

  ./install.sh                       Deploy (stealth mode)
  MODE=brand ./install.sh            Deploy with visible /amani path
  PROTO=trojan ./install.sh          Choose protocol
  ./install.sh list                  List your Cloud Run services
  ./install.sh delete <svc> <reg>    Tear down a service (stops billing)
  ./install.sh help                  This screen
EOF
}

# ══════════════════════════════════════════════════════════════
#  Admin subcommands
# ══════════════════════════════════════════════════════════════
case "${1:-deploy}" in
  help|--help|-h) usage; exit 0 ;;

  list|--list)
    require gcloud
    echo -e "${B}${BRAND_NAME} services on Cloud Run:${N}\n"
    gcloud run services list --platform managed \
      --format='table(name,region,uri,creation_timestamp.date())'
    echo -e "\n${D}To remove one:  ./install.sh delete <service> <region>${N}"
    exit 0 ;;

  delete|--delete)
    require gcloud
    S="${2:-}"; RG="${3:-us-central1}"
    [[ -n "$S" ]] || die "Usage: ./install.sh delete <service> <region>"
    say "Deleting ${B}$S${N} from $RG ..."
    gcloud run services delete "$S" --region "$RG" --platform managed --quiet
    ok "Done — billing stopped."
    exit 0 ;;

  deploy|"") : ;;
  *) die "Unknown command: $1  (deploy | list | delete | help)" ;;
esac

# ══════════════════════════════════════════════════════════════
#  Mandatory cost warning
# ══════════════════════════════════════════════════════════════
banner
warn "${B}This creates a resource on YOUR Google Cloud account, billed to YOUR payment method.${N}"
echo -e "   ${D}Check: console.cloud.google.com/budget${N}"
echo -e "   ${D}To stop later: ./install.sh delete <service> <region>${N}"
echo

INTERACTIVE=false; [[ -t 0 && -t 1 ]] && INTERACTIVE=true
if $INTERACTIVE; then
  read -rp "$(echo -e "${B}Continue? [y/N]: ${N}")" A
  [[ "$A" == [yY]* ]] || die "Cancelled."
fi

require gcloud; require curl

PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
[[ -n "$PROJECT" && "$PROJECT" != "(unset)" ]] || die "Set a project first: gcloud config set project <ID>"
ok "Project: ${B}$PROJECT${N}"

say "Enabling Cloud Run + Cloud Build ..."
gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet >/dev/null
ok "APIs ready"

# ══════════════════════════════════════════════════════════════
#  Configuration
# ══════════════════════════════════════════════════════════════
pick(){ # $1=var $2=prompt $3=default $4=regex
  local v="${!1:-}"
  if $INTERACTIVE && [[ -z "$v" ]]; then
    read -rp "$(echo -e "${B}$2${N} ${D}[$3]${N}: ")" v
  fi
  v="${v:-$3}"
  [[ "$v" =~ $4 ]] || die "Invalid value for $1: $v"
  printf -v "$1" '%s' "$v"
}

PROTO="";  pick PROTO  "Protocol (vless/vmess/trojan)" vless '^(vless|vmess|trojan)$'
REGION=""; pick REGION "Cloud Run region"              us-central1 '^[a-z0-9-]+$'

# ── Path depends on mode ───────────────────────────────────────
if [[ "$MODE" == "brand" ]]; then
  WSPATH="${WSPATH:-$BRAND_PATH}"
  warn "${B}BRAND${N} mode: path ${M}${WSPATH}${N} is ${R}visible on the wire and trivially blockable.${N}"
else
  WSPATH="${WSPATH:-/$(rand_hex 12)}"
  ok "${B}STEALTH${N} mode: random path ${M}${WSPATH}${N} — your name stays in the #fragment only."
fi
[[ "$WSPATH" =~ ^/[A-Za-z0-9_/-]*$ ]] || die "Invalid path: $WSPATH"

# ── Service name ───────────────────────────────────────────────
SERVICE="${SERVICE:-${BRAND_SERVICE_PREFIX}-$(rand_hex 4)}"
[[ "$SERVICE" =~ ^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || die "Invalid service name: $SERVICE"

# ── Secret ─────────────────────────────────────────────────────
if [[ -n "$PASSWORD" ]]; then
  SECRET="$PASSWORD"
  warn "Pinned credential from amani.conf — ${R}do not distribute the script in this state.${N}"
elif [[ "$PROTO" == "trojan" ]]; then
  SECRET="$(rand_hex 32)"
else
  SECRET="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)"
  [[ -n "$SECRET" ]] || SECRET="$(rand_hex 32)"
fi
[[ "$SECRET" =~ ^[A-Za-z0-9-]+$ ]] || die "Invalid credential characters"

# ══════════════════════════════════════════════════════════════
#  Summary
# ══════════════════════════════════════════════════════════════
echo
echo -e "${M}${B}━━━━━━━━━━━━━━━━━━ ${BRAND_NAME} ━━━━━━━━━━━━━━━━━━${N}"
printf "  ${B}%-13s${N} %s\n" "Name"      "${G}${BRAND_NAME}${N} ${D}${BRAND_HANDLE}${N}"
printf "  ${B}%-13s${N} %s\n" "Protocol"  "$PROTO"
printf "  ${B}%-13s${N} %s\n" "Service"   "$SERVICE"
printf "  ${B}%-13s${N} %s\n" "Region"    "$REGION"
printf "  ${B}%-13s${N} %s\n" "Path"      "$WSPATH"
printf "  ${B}%-13s${N} %s\n" "Mode"      "$MODE"
printf "  ${B}%-13s${N} %s\n" "Resources" "${MEMORY}MB / ${CPU} cpu / min=${MIN_INSTANCES}"
echo -e "${M}${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}\n"

# ══════════════════════════════════════════════════════════════
#  Isolated build dir — never touches your home folder
# ══════════════════════════════════════════════════════════════
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/amani-deploy.XXXXXX")"
say "Staging build files ..."
for f in Dockerfile main.go go.mod config.json.tpl; do
  [[ -f "$HERE/$f" ]] || die "Missing required file: $f"
  cp "$HERE/$f" "$WORKDIR/"
done
cd "$WORKDIR"

# BSD/GNU-portable in-place edit
sed "s|__XRAY_VERSION__|${XRAY_VERSION}|g" Dockerfile > Dockerfile.tmp && mv Dockerfile.tmp Dockerfile

# ══════════════════════════════════════════════════════════════
#  Deploy
# ══════════════════════════════════════════════════════════════
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" \
  || die "Could not read project number — check your permissions."
HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"

# NOTE: PORT is intentionally omitted — Cloud Run injects $PORT itself.
ENV_VARS="PROTO=${PROTO},USER_ID=${SECRET},WS_PATH=${WSPATH},NETWORK=ws,HOST=${HOST},INBOUND_TAG=${BRAND_TAG}"

say "Building and deploying to Cloud Run (about 2 minutes) ..."
gcloud run deploy "$SERVICE" \
  --source . \
  --region "$REGION" --platform managed \
  --allow-unauthenticated \
  --execution-environment=gen2 \
  --memory "${MEMORY}Mi" --cpu "$CPU" --timeout "$TIMEOUT" \
  --min-instances "$MIN_INSTANCES" --max-instances "$MAX_INSTANCES" \
  --concurrency "$CONCURRENCY" \
  --labels "managed-by=amani,owner=${BRAND_SERVICE_PREFIX}" \
  --set-env-vars "$ENV_VARS" \
  --quiet || die "Deployment failed — see the gcloud error above."

ok "Deployed: ${B}https://${HOST}${N}"

# ══════════════════════════════════════════════════════════════
#  Share links — this is where your name appears
# ══════════════════════════════════════════════════════════════
Q="type=ws&security=tls&path=${WSPATH}&host=${HOST}"
case "$PROTO" in
  vless)  LINK="vless://${SECRET}@${HOST}:443?${Q}#${BRAND_FRAGMENT}" ;;
  trojan) LINK="trojan://${SECRET}@${HOST}:443?${Q}#${BRAND_FRAGMENT}" ;;
  vmess)
    VMESS_JSON="$(printf '{"v":"2","ps":"%s","add":"%s","port":"443","id":"%s","aid":"0","net":"ws","type":"none","host":"%s","path":"%s","tls":"tls","sni":"%s","alpn":"h2"}' \
      "$BRAND_FRAGMENT" "$HOST" "$SECRET" "$HOST" "$WSPATH" "$HOST")"
    LINK="vmess://$(printf '%s' "$VMESS_JSON" | base64 | tr -d '\n')" ;;
esac

echo
echo -e "${G}${B}╔══════════════════════════════════════════════════════╗${N}"
echo -e "${G}${B}║  ${BRAND_NAME} ${D}${BRAND_HANDLE}${N}${G}${B}  —  connection ready                    ║${N}"
echo -e "${G}${B}╚══════════════════════════════════════════════════════╝${N}"
echo -e "${C}${B}${LINK}${N}"
echo
echo -e "${D}  Connection name in the app: ${N}${M}${BRAND_FRAGMENT}${N}"
echo -e "${D}  Support: ${N}${BRAND_CHANNEL}"
echo

# ── Optional QR code ───────────────────────────────────────────
if command -v qrencode >/dev/null 2>&1; then
  echo -e "${D}  Scan to connect:${N}"
  qrencode -t ANSIUTF8 "$LINK" | sed 's/^/    /'
  echo
fi

echo -e "${Y}${B}⚠ Save this link. Whoever holds it owns the server.${N}"
echo -e "${Y}${B}⚠ To stop billing:${N} ./install.sh delete ${SERVICE} ${REGION}"
echo

# ══════════════════════════════════════════════════════════════
#  Telegram — opt-in, announced, sends to YOUR chat only
# ══════════════════════════════════════════════════════════════
if $INTERACTIVE; then
  read -rp "$(echo -e "${B}Send the link to Telegram? [y/N]: ${N}")" TG
  if [[ "$TG" == [yY]* ]]; then
    read -rp "Bot Token: " BOT_TOKEN
    read -rp "Chat ID:   " CHAT_ID
    [[ "$BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]] || die "Invalid bot token."
    curl -s --data-urlencode "chat_id=${CHAT_ID}" \
            --data-urlencode "text=${LINK}" \
         "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" >/dev/null \
      && ok "Sent to your own Telegram." || warn "Send failed."
  fi
fi

echo -e "${D}${BRAND_NAME} ${BRAND_HANDLE} — done.${N}"

