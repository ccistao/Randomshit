#!/system/bin/sh
PLACE_ID="2753915549"
DISCORD_USER_ID="982107241371013132"
FILTER="roblox|delta|aya"
CHECK_INTERVAL=30
REPORT_EVERY=10
LAUNCH_WAIT=25
NET_RECHECK=15
MIN_RAM=300
MAX_TEMP=45
BAT_LOW=20
WH_FILE="/data/local/tmp/.wh"
STATE="/data/local/tmp/farmstate"

WEBHOOK_URL=$(base64 -d "$WH_FILE" 2>/dev/null || toybox base64 -d "$WH_FILE" 2>/dev/null)
if [ -z "$WEBHOOK_URL" ]; then
    echo "Khong doc duoc webhook!"
    exit 1
fi

LIST_CLONE=$(pm list packages -3 | cut -d: -f2 | grep -iE "$FILTER")
if [ -z "$LIST_CLONE" ]; then
    echo "Khong tim thay clone nao!"
    exit 1
fi
TOTAL_CLONE=$(echo "$LIST_CLONE" | wc -l)
echo "Da nhan dien $TOTAL_CLONE tab:"
echo "$LIST_CLONE"

mkdir -p "$STATE"
rm -f "$STATE"/min_*

START=$(date +%s)
PREV_TOT=""
PREV_IDLE=0
CPU=0
DTOT=1
TOTAL_REJOIN=0
LAST_ALERT=-100
MEM=0; BAT=0; TEMP=0; CHG=""; UPTXT="0h0m"

sys_stats() {
    local RAW ST U
    MEM=$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo)
    BAT=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null); BAT=${BAT:-0}
    RAW=$(cat /sys/class/power_supply/battery/temp 2>/dev/null); TEMP=$(( ${RAW:-0} / 10 ))
    ST=$(cat /sys/class/power_supply/battery/status 2>/dev/null)
    CHG=""; [ "$ST" = "Charging" ] && CHG="(sac)"
    U=$(( $(date +%s) - START ))
    UPTXT="$((U/3600))h$(((U%3600)/60))m"
}

send_discord() {
    local TIME_NOW JSON FIELDS RESP CODE
    sys_stats
    TIME_NOW=$(date +"%H:%M:%S")
    FIELDS="[{\"name\":\"CPU\",\"value\":\"${CPU:-0}%\",\"inline\":true},{\"name\":\"RAM trong\",\"value\":\"${MEM}MB\",\"inline\":true},{\"name\":\"Pin\",\"value\":\"${BAT}% ${CHG}\",\"inline\":true},{\"name\":\"Nhiet do\",\"value\":\"${TEMP}C\",\"inline\":true},{\"name\":\"Uptime\",\"value\":\"$UPTXT\",\"inline\":true},{\"name\":\"Tong rejoin\",\"value\":\"$TOTAL_REJOIN\",\"inline\":true}]"
    JSON="{\"content\":\"$1\",\"embeds\":[{\"title\":\"$3\",\"description\":\"$4\",\"color\":$2,\"fields\":$FIELDS,\"footer\":{\"text\":\"$TIME_NOW\"}}]}"
    RESP=$(curl -s -4 --connect-timeout 5 -m 15 --retry 2 \
        -H "Content-Type: application/json" -X POST -d "$JSON" \
        -w "\n%{http_code}" "$WEBHOOK_URL" 2>&1)
    CODE=$(echo "$RESP" | tail -n 1)
    if [ "$CODE" = "204" ] || [ "$CODE" = "200" ]; then
        echo "[Discord] Gui OK luc $TIME_NOW"
    else
        echo "[Discord] LOI HTTP $CODE: $(echo "$RESP" | head -n 1)"
    fi
}

launch_app() {
    am start -a android.intent.action.VIEW -p "$1" -d "roblox://experiences/start?placeId=$PLACE_ID" > /dev/null 2>&1
}

get_pid() {
    local P
    P=$(pidof "$1" 2>/dev/null | awk '{print $1}')
    if [ -z "$P" ]; then
        P=$(pgrep -f "^$1" 2>/dev/null | head -n 1)
    fi
    echo "$P"
}

has_net() {
    awk -v u="$1" 'NR>1 && $8==u {f=1} END{exit !f}' /proc/net/udp /proc/net/udp6 2>/dev/null
}

cpu_total() {
    read -r _ u n s i io irq sirq st _ < /proc/stat
    TOT=$((u+n+s+i+io+irq+sirq+st)); IDLE=$((i+io))
    if [ -n "$PREV_TOT" ]; then
        DTOT=$((TOT - PREV_TOT))
        [ "$DTOT" -le 0 ] && DTOT=1
        CPU=$(( 100 * (DTOT - (IDLE - PREV_IDLE)) / DTOT ))
    else
        CPU=0; DTOT=1
    fi
    PREV_TOT=$TOT; PREV_IDLE=$IDLE
}
