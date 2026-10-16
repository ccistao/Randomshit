#!/system/bin/sh
echo "== farm1_fixed v4 (DEBUG2) =="
PLACE_ID="2753915549"
DISCORD_USER_ID="982107241371013132"
WEBHOOK_URL="https://discord.com/api/webhooks/1560579280906489906/jK4Gj1NoNmqY-3x_7nOUHg0UQEXPgIgNqnN_8xG4u8LNqniyztRDE1DVXjl2a5k5EKSs"
FILTER="roblox|delta|aya"

CHECK_INTERVAL=15
LAUNCH_WAIT=10
NET_RECHECK=30
REPORT_INTERVAL=3600 # Gửi báo cáo định kỳ sau mỗi 3600 giây (1 giờ)
MIN_RAM=300
ENABLE_WATCH=1   # 1 = tu mo lai tab bi thu nho/dong; 0 = tat
DEBUG=1          # 1 = in danh sach socket UDP cua tung tab de soi
STATE="/data/local/tmp/farmstate"
INPUT_FILE="/data/local/tmp/farm_input"

LIST_CLONE=$(pm list packages -3 | cut -d: -f2 | grep -iE "$FILTER")
if [ -z "$LIST_CLONE" ]; then
    echo "Không tìm thấy clone nào!"
    exit 1
fi

TOTAL_CLONE=$(echo "$LIST_CLONE" | wc -l)
echo "Đã nhận diện $TOTAL_CLONE tab:"
echo "$LIST_CLONE"

mkdir -p "$STATE"
rm -f "$STATE"/min_*
echo "continue" > "$INPUT_FILE"

START=$(date +%s)
PREV_TOT=""
PREV_IDLE=0
CPU=0
DTOT=1
TOTAL_REJOIN=0
LAST_ALERT=-100
MEM=0; UPTXT="0h0m"

get_cmd() {
    cat "$INPUT_FILE" 2>/dev/null | tr -d '\r\n ' | head -n 1
}

wait_delay() {
    local t=$1
    local c=0
    while [ "$c" -lt "$t" ]; do
        local current_cmd=$(get_cmd)
        if [ "x$current_cmd" = "xstop" ]; then
            break
        fi
        sleep 1
        c=$((c + 1))
    done
}

sys_stats() {
    local U
    MEM=$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo)
    [ -z "$MEM" ] && MEM=$(awk '/MemFree/{printf "%d", $2/1024}' /proc/meminfo)
    MEM=${MEM:-0}
    U=$(($(date +%s) - START ))
    UPTXT="$((U/3600))h$(((U%3600)/60))m"
}

send_discord() {
    local TIME_NOW JSON FIELDS RESP CODE
    sys_stats
    TIME_NOW=$(date +"%H:%M:%S")
    FIELDS="[{\"name\":\"CPU\",\"value\":\"${CPU:-0}%\",\"inline\":true},{\"name\":\"RAM Trống\",\"value\":\"${MEM}MB\",\"inline\":true},{\"name\":\"Uptime\",\"value\":\"$UPTXT\",\"inline\":true},{\"name\":\"Tổng Rejoin\",\"value\":\"$TOTAL_REJOIN\",\"inline\":true}]"
    JSON="{\"content\":\"$1\",\"embeds\":[{\"title\":\"$3\",\"description\":\"$4\",\"color\":$2,\"fields\":$FIELDS,\"footer\":{\"text\":\"$TIME_NOW\"}}]}"
    RESP=$(curl -s -4 --connect-timeout 5 -m 15 --retry 2 \
        -H "Content-Type: application/json" -X POST -d "$JSON" \
        -w "\n%{http_code}" "$WEBHOOK_URL" 2>&1)
    CODE=$(echo "$RESP" | tail -n 1 | tr -d '\r\n ')
    
    if [ "x$CODE" = "x204" ] || [ "x$CODE" = "x200" ]; then
        echo "[Discord] Gửi OK lúc $TIME_NOW"
    else
        echo "[Discord] LỖI HTTP $CODE"
    fi
}

send_screenshot() {
    local FILE="/data/local/tmp/screen.png"
    screencap -p "$FILE"
    curl -s -X POST "$WEBHOOK_URL" \
        -F "payload_json={\"embeds\":[{\"title\":\"📸 ẢNH CHỤP MÀN HÌNH 1 GIỜ/LẦN\",\"color\":3066993,\"image\":{\"url\":\"attachment://screen.png\"}}]}" \
        -F "file=@$FILE" > /dev/null 2>&1
    rm -f "$FILE"
    echo "[Discord] Đã tự động gửi ảnh chụp màn hình."
}

launch_app() {
    local OUT
    OUT=$(am start -n "$1/com.roblox.client.ActivityProtocolLaunch" -a android.intent.action.VIEW -d "roblox://experiences/start?placeId=$PLACE_ID" 2>&1)
    case "$OUT" in
        *Error*|*Exception*|*unable*)
            am start -a android.intent.action.VIEW -p "$1" -d "roblox://experiences/start?placeId=$PLACE_ID" > /dev/null 2>&1
            ;;
    esac
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

udp_info() {
    awk -v u="$1" 'NR>1 && $8==u {printf "%s>%s ", $2, $3}' /proc/net/udp /proc/net/udp6 2>/dev/null | cut -c1-150
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

watch_visible() {
    local W a IDX C CMD
    while true; do
        CMD=$(get_cmd)
        if [ "x$CMD" = "xstop" ]; then sleep 2; continue; fi

        W=$(dumpsys window windows 2>/dev/null)
        IDX=1
        for a in $LIST_CLONE; do
            if [ -n "$(get_pid "$a")" ]; then
                if ! echo "$W" | grep -A40 "u0 $a/com.roblox.client.ActivityNativeMain" | grep -q "mHasSurface=true"; then
                    echo "$(date +%T) [THU NHO] Tab $IDX ($a) -> mo lai"
                    C=$(cat "$STATE/min_$IDX" 2>/dev/null)
                    C=${C:-0}
                    echo $(( C + 1 )) > "$STATE/min_$IDX"
                    monkey -p "$a" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
                    sleep 2
                fi
            fi
            IDX=$((IDX + 1))
        done
        sleep 2
    done
}

(
    while read -r user_cmd 2>/dev
