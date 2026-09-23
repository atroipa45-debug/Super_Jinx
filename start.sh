#!/bin/bash
set -eu

PANEL_PATH="${PANEL_PATH:-/managepanel}"
WS_PATH="${WS_PATH:-/wspath}"
SUB_PATH="${SUB_PATH:-/subpath}"
PANEL_PORT="${PANEL_PORT:-2053}"
WS_PORT="${WS_PORT:-10001}"
SUB_PORT="${SUB_PORT:-2096}"
PANEL_USER="${PANEL_USER:-admin}"
PANEL_PASS="${PANEL_PASS:-ChangeMe123!}"
PORT="${PORT:-8080}"

export PANEL_PATH WS_PATH SUB_PATH PANEL_PORT WS_PORT SUB_PORT PANEL_USER PANEL_PASS PORT

echo ">> [1/4] تنظیم یوزر/پسورد/پورت/مسیر پنل ..."
/app/x-ui setting -username "${PANEL_USER}" -password "${PANEL_PASS}" || echo "!! تنظیم یوزر/پسورد شکست خورد (ادامه می‌دیم)"
/app/x-ui setting -port "${PANEL_PORT}" || echo "!! تنظیم پورت پنل شکست خورد (ادامه می‌دیم)"
/app/x-ui setting -webBasePath "${PANEL_PATH}" || echo "!! تنظیم webBasePath شکست خورد (ادامه می‌دیم)"

echo ">> [2/4] ساخت nginx.conf ..."
envsubst '${PORT} ${PANEL_PATH} ${WS_PATH} ${SUB_PATH} ${PANEL_PORT} ${WS_PORT} ${SUB_PORT}' \
  < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
mkdir -p /var/lib/nginx/tmp /var/log/nginx
nginx -t

echo ">> [3/4] اجرای 3x-ui در پس‌زمینه ..."
/app/x-ui &
XUI_PID=$!

echo ">> [4/4] اجرای بوت‌استرپ (ساخت اینباند + تنظیمات ساب + نگهبان ۶۰ ثانیه‌ای) ..."
/bootstrap.sh &
BOOT_PID=$!

trap "kill $XUI_PID $BOOT_PID 2>/dev/null || true" EXIT

echo ">> اجرای nginx روی پورت ${PORT} ..."
exec nginx -g "daemon off;"
