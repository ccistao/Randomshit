#!/system/bin/sh
export PATH="/data/data/com.termux/files/usr/bin:/system/bin:/system/xbin:$PATH"

PLACE_ID="2753915549"
DISCORD_USER_ID="982107241371013132"
FILTER="roblox|delta|aya"
CHECK_INTERVAL=10
STALE=210                # 45s khong co Heartbeat la xu ly
JOIN_GRACE=210         # 45s de load vao game
LAUNCH_WAIT=5
REPORT_EVERY=3600
MAX_UPTIME=7200         # 2 tieng tu kill xoa lag
WH_FILE="/data/local/tmp/.wh"
STATE="/data/local/tmp/farmstate"
ACC_FILE="/data/local/tmp/accounts.txt"

WEBHOOK_URL=$(base64 -d "$WH_FILE" 2>/dev/null || toybox base64 -d "$WH_FILE" 2>/dev/null)
if [ -z "$WEBHOOK_URL" ]; then
    WEBHOOK_URL="https://discord.com/api/webhooks/1560579280906489906/jK4Gj1NoNmqY-3x_7nOUHg0UQEXPgIgNqnN_8xG4u8LNqniyztRDE1DVXjl2a5k5EKSs"
fi

LIST_CLONE=$(pm list packages -3 | cut -d: -f2 | grep -iE "$FILTER" | tr -d '\r')
if [ -z "$LIST_CLONE" ]; then
    echo "Khong tim thay clone nao!"
    exit 1
fi
TOTAL_CLONE=$(echo "$LIST_CLONE" | wc -l | tr -cd '0-9')
echo "Da nhan dien $TOTAL_CLONE tab:"
echo "$LIST_CLONE"

mkdir -p "$STATE"
rm -f "$STATE"/min_*

START=$(date +%s | tr -cd '0-9')
LAST_REPORT=$START
PREV_TOT=""
PREV_IDLE=0
CPU=0
DTOT=1
TOTAL_REJOIN=0
LAST_ALERT=-100
MEM=0; UPTXT="0h0m"

IDX_INIT=1
for app in $LIST_CLONE; do
    echo "$START" > "$STATE/up_$IDX_INIT"
    echo "0" > "$STATE/launch_$app"
    IDX_INIT=$((IDX_INIT + 1))
done

rv() { local V; V=$(cat "$STATE/$1" 2>/dev/null | tr -d '\r\n'); echo "${V:-$2}"; }
wv() { echo "$2" > "$STATE/$1"; }

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
    FIELDS="[{\"name\":\"CPU\",\"value\":\"${CPU:-0}%\",\"inline\":true},{\"name\":\"RAM trong\",\"value\":\"${MEM}MB\",\"inline\":true},{\"name\":\"Uptime\",\"value\":\"$UPTXT\",\"inline\":true},{\"name\":\"Tong rejoin\",\"value\":\"${TOTAL_REJOIN:-0}\",\"inline\":true}]"
    
    if [ -n "$1" ]; then CONTENT_JSON="\"content\":\"$1\","; else CONTENT_JSON=""; fi
    JSON="{${CONTENT_JSON}\"embeds\":[{\"title\":\"$3\",\"description\":\"$4\",\"color\":${2:-3066993},\"fields\":$FIELDS,\"footer\":{\"text\":\"$TIME_NOW\"}}]}"
    
    RESP=$(curl -s -4 --connect-timeout 5 -m 15 --retry 2 -H "Content-Type: application/json" -X POST -d "$JSON" -w "\n%{http_code}" "$WEBHOOK_URL" 2>&1)
    CODE=$(echo "$RESP" | tail -n 1 | tr -cd '0-9')
    case "$CODE" in
        *200*|*204*) echo "[Discord] Gui OK luc $TIME_NOW" ;;
        *) echo "[Discord] LOI HTTP $CODE" ;;
    esac
}

send_screenshot() {
    local FILE="/data/local/tmp/screen.png"
    screencap -p "$FILE"
    curl -s -X POST "$WEBHOOK_URL" -F "payload_json={\"embeds\":[{\"title\":\"📸 ANH CHUP MAN HINH DINH KY (1 GIO)\",\"color\":3066993,\"image\":{\"url\":\"attachment://screen.png\"}}]}" -F "file=@$FILE" > /dev/null 2>&1
    rm -f "$FILE"
    echo "[Discord] Da gui anh chup man hinh."
}

get_pid() {
    local P
    P=$(pidof "$1" 2>/dev/null | cut -d' ' -f1 | tr -cd '0-9')
    [ -z "$P" ] && P=$(pgrep -f "^$1" 2>/dev/null | head -n 1 | tr -cd '0-9')
    echo "$P"
}

kill_tab() {
    local P
    P=$(get_pid "$1")
    if [ -n "$P" ]; then kill -9 "$P" 2>/dev/null; fi
}

launch_app() {
    monkey -p "$1" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
    sleep 2
    am start -n "$1/com.roblox.client.ActivityProtocolLaunch" -a android.intent.action.VIEW -d "roblox://experiences/start?placeId=$PLACE_ID" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        am start -a android.intent.action.VIEW -p "$1" -d "roblox://experiences/start?placeId=$PLACE_ID" > /dev/null 2>&1
    fi
    wv "launch_$1" "$(date +%s)"
}

get_file_age() {
    local f="$1"
    if [ -f "$f" ]; then
        local M=$(stat -c %Y "$f" 2>/dev/null | tr -cd '0-9')
        if [ -n "$M" ]; then
            local N=$(date +%s)
            local A=$((N - M))
            [ "$A" -lt 0 ] && A=0
            echo "$A"
            return 0
        fi
    fi
    echo 999
}

find_hb_age() {
    local p="$1" u f AGE
    if [ -f "$ACC_FILE" ]; then
        u=$(awk -v pkg="$p" '$2==pkg{print $1; exit}' "$ACC_FILE" 2>/dev/null)
        if [ -n "$u" ]; then
            for f in "/storage/emulated/0/Delta/Workspace/farmhb_${u}.txt" "/sdcard/Delta/Workspace/farmhb_${u}.txt"; do
                AGE=$(get_file_age "$f")
                if [ "$AGE" -ne 999 ]; then echo "$AGE"; return 0; fi
            done
        fi
    fi
    for f in /storage/emulated/0/Delta/Workspace/farmhb_*.txt /sdcard/Delta/Workspace/farmhb_*.txt; do
        [ -f "$f" ] || continue
        u=$(basename "$f" .txt | sed 's/farmhb_//')
        if grep -qisF "$u" /data/data/$p/shared_prefs/*.xml 2>/dev/null; then
            echo "$u $p" >> "$ACC_FILE"
            AGE=$(get_file_age "$f")
            echo "$AGE"
            return 0
        fi
    done
    echo 999
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
