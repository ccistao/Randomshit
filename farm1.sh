#!/system/bin/sh
PLACE_ID="2753915549"
DISCORD_USER_ID="982107241371013132"
FILTER="roblox|delta|aya"
CHECK_INTERVAL=15
REPORT_EVERY=3600
LAUNCH_WAIT=5
NET_RECHECK=5
MIN_RAM=300
MAX_UPTIME=7200 # 2 tieng (7200 giay) tu kill mo lai xoa lag
WH_FILE="/data/local/tmp/.wh"
STATE="/data/local/tmp/farmstate"

WEBHOOK_URL=$(base64 -d "$WH_FILE" 2>/dev/null || toybox base64 -d "$WH_FILE" 2>/dev/null)
if [ -z "$WEBHOOK_URL" ]; then
    WEBHOOK_URL="https://discord.com/api/webhooks/1560579280906489906/jK4Gj1NoNmqY-3x_7nOUHg0UQEXPgIgNqnN_8xG4u8LNqniyztRDE1DVXjl2a5k5EKSs"
fi

LIST_CLONE=$(pm list packages -3 | cut -d: -f2 | grep -iE "$FILTER" | tr -d '\r')
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
LAST_REPORT=$START
PREV_TOT=""
PREV_IDLE=0
CPU=0
DTOT=1
TOTAL_REJOIN=0
LAST_ALERT=-100
MEM=0; UPTXT="0h0m"

# Khoi tao moc dem 2h cho tung tab
IDX_INIT=1
for app in $LIST_CLONE; do
    echo "$START" > "$STATE/up_$IDX_INIT"
    IDX_INIT=$((IDX_INIT + 1))
done

sys_stats() {
    local U
    MEM=$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)
    [ -z "$MEM" ] && MEM=$(awk '/MemFree/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)
    MEM=${MEM:-0}
    U=$(( $(date +%s) - START ))
    UPTXT="$((U/3600))h$(((U%3600)/60))m"
}

send_discord() {
    local TIME_NOW JSON FIELDS RESP CODE CONTENT_JSON
    sys_stats
    TIME_NOW=$(date +"%H:%M:%S")
    FIELDS="[{\"name\":\"CPU\",\"value\":\"${CPU:-0}%\",\"inline\":true},{\"name\":\"RAM trong\",\"value\":\"${MEM}MB\",\"inline\":true},{\"name\":\"Uptime\",\"value\":\"$UPTXT\",\"inline\":true},{\"name\":\"Tong rejoin\",\"value\":\"$TOTAL_REJOIN\",\"inline\":true}]"
    
    if [ -n "$1" ]; then
        CONTENT_JSON="\"content\":\"$1\","
    else
        CONTENT_JSON=""
    fi
    
    JSON="{${CONTENT_JSON}\"embeds\":[{\"title\":\"$3\",\"description\":\"$4\",\"color\":${2:-3066993},\"fields\":$FIELDS,\"footer\":{\"text\":\"$TIME_NOW\"}}]}"
    
    RESP=$(curl -s -4 --connect-timeout 5 -m 15 --retry 2 \
        -H "Content-Type: application/json" -X POST -d "$JSON" \
        -w "\n%{http_code}" "$WEBHOOK_URL" 2>&1)
    CODE=$(echo "$RESP" | tail -n 1 | tr -cd '0-9')
    case "$CODE" in
        *200*|*204*) echo "[Discord] Gui OK luc $TIME_NOW" ;;
        *) echo "[Discord] LOI HTTP $CODE" ;;
    esac
}

send_screenshot() {
    local FILE="/data/local/tmp/screen.png"
    screencap -p "$FILE"
    curl -s -X POST "$WEBHOOK_URL" \
        -F "payload_json={\"embeds\":[{\"title\":\"📸 ANH CHUP MAN HINH DINH KY (1 GIO)\",\"color\":3066993,\"image\":{\"url\":\"attachment://screen.png\"}}]}" \
        -F "file=@$FILE" > /dev/null 2>&1
    rm -f "$FILE"
    echo "[Discord] Da gui anh chup man hinh."
}

get_pid() {
    local P
    P=$(pidof "$1" 2>/dev/null | awk '{print $1}')
    if [ -z "$P" ]; then
        P=$(pgrep -f "^$1" 2>/dev/null | head -n 1)
    fi
    echo "$P" | tr -cd '0-9'
}

# Ban tia dung tab do bang PID de khong lam vang cac tab clone khac
kill_tab() {
    local P
    P=$(get_pid "$1")
    if [ -n "$P" ]; then
        kill -9 "$P" 2>/dev/null
    else
        am force-stop "$1" 2>/dev/null
    fi
}

launch_app() {
    monkey -p "$1" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
    sleep 2
    am start -a android.intent.action.VIEW -p "$1" -d "roblox://experiences/start?placeId=$PLACE_ID" > /dev/null 2>&1
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
