#!/usr/bin/env bash
# InstaBox sing-box installer: VLESS + WebSocket inbound (user-space, no root needed)
# Run ONCE inside the InstaBox machine terminal:  bash instabox-singbox-install.sh
set -u
cd "$HOME"
mkdir -p sing-box && cd sing-box

VER="1.14.3"
ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
  x86_64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "unsupported arch: $ARCH_RAW"; exit 1 ;;
esac

if [ ! -x ./sing-box ]; then
  URL="https://github.com/SagerNet/sing-box/releases/download/v${VER}/sing-box-${VER}-linux-${ARCH}.tar.gz"
  echo "Downloading: $URL"
  curl -fL -o sb.tar.gz "$URL" || { echo "DOWNLOAD FAILED"; exit 1; }
  tar -xzf sb.tar.gz || { echo "EXTRACT FAILED"; exit 1; }
  cp "sing-box-${VER}-linux-${ARCH}/sing-box" ./sing-box
  chmod +x ./sing-box
  rm -rf sb.tar.gz "sing-box-${VER}-linux-${ARCH}"
fi
./sing-box version

UUID="$(cat /proc/sys/kernel/random/uuid)"
PORT=8080
WSPATH="/ws"

cat > config.json <<EOF
{
  "log": { "level": "warn" },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-ws-in",
      "listen": "0.0.0.0",
      "listen_port": ${PORT},
      "users": [ { "uuid": "${UUID}" } ],
      "transport": { "type": "ws", "path": "${WSPATH}" }
    }
  ],
  "outbounds": [ { "type": "direct", "tag": "direct" } ]
}
EOF

cat > start.sh <<'EOS'
#!/usr/bin/env bash
cd "$HOME/sing-box"
if [ -f sb.pid ] && kill -0 "$(cat sb.pid)" 2>/dev/null; then
  echo "sing-box already running (pid $(cat sb.pid))"
  exit 0
fi
nohup ./sing-box run -c config.json > sb.log 2>&1 &
echo $! > sb.pid
echo "sing-box started (pid $(cat sb.pid))"
EOS
chmod +x start.sh

./sing-box check -c config.json || { echo "CONFIG CHECK FAILED"; exit 1; }
bash start.sh
sleep 2

CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:${PORT}${WSPATH}" || true)"
if [ "$CODE" = "400" ]; then
  echo "LOCAL CHECK OK: WS endpoint alive on port ${PORT} (HTTP 400 is expected for a plain GET)"
else
  echo "LOCAL CHECK WARNING: got HTTP '$CODE', expected 400. Last log lines:"
  tail -5 sb.log || true
fi

echo ""
echo "================ NODE INFO - KEEP PRIVATE ================"
echo "UUID:      ${UUID}"
echo "PORT:      ${PORT} (local, to publish)"
echo "WS PATH:   ${WSPATH}"
echo "=========================================================="
echo "NEXT: InstaBox dashboard -> Ports tab -> Publish port ${PORT}."
echo "Then pair the public URL with the UUID above to build the client link."
echo "If the machine was paused and the node is down, restart with: bash ~/sing-box/start.sh"
