#!/bin/bash
set -u

PANEL_PATH="${PANEL_PATH:-/managepanel}"
PANEL_PORT="${PANEL_PORT:-2053}"
PANEL_USER="${PANEL_USER:-admin}"
PANEL_PASS="${PANEL_PASS:-ChangeMe123!}"
WS_PORT="${WS_PORT:-10001}"
WS_PATH="${WS_PATH:-/wspath}"
SUB_PORT="${SUB_PORT:-2096}"
SUB_PATH="${SUB_PATH:-/subpath}"
REMARK="${INBOUND_REMARK:-جینکس | 𝙎𝙪𝙥𝙚𝙧 𝗝𝗶𝗻𝗫}"
PORT="${PORT:-8080}"

# Railway این متغیر رو خودکار برای دامنه‌ی publicای که Generate کردید ست می‌کنه.
# اگه به هر دلیلی خالی بود، از PUBLIC_DOMAIN که خودتون در Variables می‌ذارید استفاده می‌شه.
PUBLIC_DOMAIN="${RAILWAY_PUBLIC_DOMAIN:-${PUBLIC_DOMAIN:-}}"

STATE_DIR="/etc/x-ui-bootstrap"
mkdir -p "$STATE_DIR"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

if [ -f "$STATE_DIR/uuid" ]; then
  CLIENT_UUID=$(cat "$STATE_DIR/uuid")
else
  CLIENT_UUID="${CLIENT_UUID:-$(cat /proc/sys/kernel/random/uuid)}"
  echo "$CLIENT_UUID" > "$STATE_DIR/uuid"
fi

if [ -f "$STATE_DIR/subid" ]; then
  SUBID=$(cat "$STATE_DIR/subid")
else
  SUBID="${SUBID:-$(head -c 32 /dev/urandom | md5sum | cut -c1-16)}"
  echo "$SUBID" > "$STATE_DIR/subid"
fi

BASE="http://127.0.0.1:${PANEL_PORT}${PANEL_PATH}"
COOKIE="$STATE_DIR/cookie.txt"

login() {
  curl -s -c "$COOKIE" -X POST "$BASE/login" \
    --data-urlencode "username=${PANEL_USER}" \
    --data-urlencode "password=${PANEL_PASS}" > /dev/null
}

inbound_exists() {
  curl -s -b "$COOKIE" "$BASE/panel/api/inbounds/list" \
    | jq -e --arg r "$REMARK" '.obj[]? | select(.remark == $r)' > /dev/null 2>&1
}

create_inbound() {
  local SETTINGS STREAM SNIFF RESP OK
  SETTINGS=$(jq -n --arg id "$CLIENT_UUID" --arg sub "$SUBID" '{
    clients: [{id:$id, flow:"", email:"superjinx", limitIp:0, totalGB:0, expiryTime:0, enable:true, tgId:"", subId:$sub, comment:"", reset:0}],
    decryption:"none", fallbacks: []
  }')
  STREAM=$(jq -n --arg path "$WS_PATH" '{
    network:"ws", security:"none", wsSettings:{path:$path, headers:{}}
  }')
  SNIFF='{"enabled":true,"destOverride":["http","tls"]}'

  RESP=$(curl -s -b "$COOKIE" -X POST "$BASE/panel/api/inbounds/add" \
    --data-urlencode "up=0" \
    --data-urlencode "down=0" \
    --data-urlencode "total=0" \
    --data-urlencode "remark=${REMARK}" \
    --data-urlencode "enable=true" \
    --data-urlencode "expiryTime=0" \
    --data-urlencode "listen=127.0.0.1" \
    --data-urlencode "port=${WS_PORT}" \
    --data-urlencode "protocol=vless" \
    --data-urlencode "settings=${SETTINGS}" \
    --data-urlencode "streamSettings=${STREAM}" \
    --data-urlencode "sniffing=${SNIFF}")

  OK=$(echo "$RESP" | jq -r '.success // false' 2>/dev/null)
  if [ "$OK" = "true" ]; then
    log "✅ اینباند «${REMARK}» ساخته شد."
  else
    log "❌ ساخت اینباند شکست خورد. پاسخ پنل: $RESP"
  fi
}

# ===== تنظیمات ساب‌اسکریپشن رو از طریق API خودکار می‌کنیم =====
configure_subscription() {
  local CURRENT NEW RESP OK SUB_URI

  if [ -n "$PUBLIC_DOMAIN" ]; then
    SUB_URI="https://${PUBLIC_DOMAIN}${SUB_PATH}/"
  else
    SUB_URI=""
    log "⚠️ متغیر RAILWAY_PUBLIC_DOMAIN پیدا نشد؛ سابلینک بدون دامنه‌ی کامل ساخته می‌شه. بعد از Generate Domain در Railway، سرویس رو یک‌بار Restart کنید."
  fi

  CURRENT=$(curl -s -b "$COOKIE" "$BASE/panel/setting/all")
  OK=$(echo "$CURRENT" | jq -r '.success // false' 2>/dev/null)
  if [ "$OK" != "true" ]; then
    log "❌ خوندن تنظیمات فعلی پنل شکست خورد. پاسخ: $CURRENT"
    return 1
  fi

  NEW=$(echo "$CURRENT" | jq --arg port "$SUB_PORT" --arg path "${SUB_PATH}/" --arg uri "$SUB_URI" '
    .obj
    | .subEnable = true
    | .subPort = ($port | tonumber)
    | .subPath = $path
    | .subDomain = ""
    | .subURI = $uri
  ')

  RESP=$(curl -s -b "$COOKIE" -X POST "$BASE/panel/setting/update" \
    -H "Content-Type: application/json" \
    --data "$NEW")

  OK=$(echo "$RESP" | jq -r '.success // false' 2>/dev/null)
  if [ "$OK" = "true" ]; then
    log "✅ تنظیمات ساب‌اسکریپشن ذخیره شد (Path=${SUB_PATH}/  Port=${SUB_PORT})."
  else
    log "❌ ذخیره‌ی تنظیمات ساب شکست خورد. پاسخ پنل: $RESP"
  fi
}

# تست واقعی اینکه سابلینک از پشت nginx واقعاً جواب می‌ده یا نه
healthcheck_sublink() {
  local CODE
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${PORT}${SUB_PATH}/${SUBID}")
  if [ "$CODE" = "200" ]; then
    log "✅ سابلینک از پشت nginx تست شد و جواب ۲۰۰ داد."
  else
    log "❌ تست سابلینک جواب ${CODE} داد (باید ۲۰۰ باشه). اگه چند دور متوالی همینه، لاگ کامل این چرخه رو بفرست."
  fi
}

log ">> صبر برای بالا اومدن پنل روی ${BASE} ..."
for i in $(seq 1 60); do
  if curl -s -o /dev/null "${BASE}/login"; then
    log "پنل بالا اومد."
    break
  fi
  sleep 2
done

log ">> لاگین اولیه ..."
login

log ">> اولین تنظیم ساب‌اسکریپشن ..."
configure_subscription

log ">> اولین ساخت اینباند ..."
create_inbound

# صبر کوتاه تا سرویس ساب با تنظیمات جدید ری‌استارت داخلی بشه
sleep 3

log ">> شروع حلقه‌ی نگهبان (هر ۶۰ ثانیه: چک اینباند + چک تنظیمات ساب + تست سلامت) ..."
while true; do
  login

  if ! inbound_exists; then
    log "⚠️ اینباند «${REMARK}» پیدا نشد؛ بازسازی خودکار ..."
    create_inbound
  fi

  CURRENT=$(curl -s -b "$COOKIE" "$BASE/panel/setting/all")
  CUR_PATH=$(echo "$CURRENT" | jq -r '.obj.subPath // ""' 2>/dev/null)
  CUR_ENABLE=$(echo "$CURRENT" | jq -r '.obj.subEnable // false' 2>/dev/null)
  if [ "$CUR_PATH" != "${SUB_PATH}/" ] || [ "$CUR_ENABLE" != "true" ]; then
    log "⚠️ تنظیمات ساب تغییر کرده بود (Path=${CUR_PATH} Enable=${CUR_ENABLE})؛ بازسازی خودکار ..."
    configure_subscription
  fi

  healthcheck_sublink

  sleep 60
done
