#!/system/bin/sh
PLACE_ID="2753915549"
DISCORD_USER_ID="982107241371013132"
FILTER="roblox|delta|aya"
CHECK_INTERVAL=10
STALE=45                # Lua ghi moi 30s -> neu qua 45s khong co tin hieu la ket Menu/Loi
JOIN_GRACE=45           # Cho toi da 45s de load vao game
LAUNCH_WAIT=5
REPORT_EVERY=3600       # 1 gio bao cao dinh ky + chup man hinh
MAX_UPTIME=7200         # 2 tieng tu restart bang kill -9 xoa lag
WH_FILE="/data/local/tmp/.wh"
STATE="/data/local/tmp/farmstate"
ACC_FILE="/data/local/tmp/accounts.txt"
DATA_DIR="/data/data"

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
    FIELDS="[{\"name\":\"CPU\",\"value\":\"${CPU:-0}%\",\"inline\":true},{\"name\":\"RAM trong\",\"value\":\"${MEM}MB\",\"inline\":true},{\"name\":\"Uptime\",\"value\":\"$UPTXT\",\"inline\":true},{\"name\":\"Tong rejoin\",\"value\":\"$TOTAL_REJOIN\",\"inline\":true}]"
    
    if [ -n "$1" ]; then CONTENT_JSON="\"content\":\"$1\","; else CONTENT_JSON=""; fi
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

# Tim PID chuan xac 100% qua cmdline, khong bao gio bi cat cut ten app
get_pid() {
    local p="$1"
    grep -sl "$p" /proc/[0-9]*/cmdline 2>/dev/null | head -n 1 | cut -d/ -f3 | tr -cd '0-9'
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

# Doc thoi gian troi qua tu file Heartbeat cua Lua
hb_age() {
    local T N A
    T=$(cut -d, -f1 "$1" 2>/dev/null | tr -cd '0-9')
    if [ -z "$T" ]; then T=$(stat -c %Y "$1" 2>/dev/null | tr -cd '0-9'); fi
    [ -z "$T" ] && return 999
    N=$(date +%s); A=$((N - T)); [ "$A" -lt 0 ] && A=0
    echo "$A"
}

# Tu dong map file farmhb_<TenAcc>.txt voi dung package
map_file() {
    local f="$1" n p d
    n=$(basename "$f" .txt | sed 's/farmhb_//g')
    if [ -f "$ACC_FILE" ]; then
        p=$(awk -v n="$n" 'tolower($1)==tolower(n){print $2; exit}' "$ACC_FILE" 2>/dev/null | tr -d '\r')
        if [ -n "$p" ]; then echo "$p"; return 0; fi
    fi
    for p in $LIST_CLONE; do
        if grep -rlsF -i "$n" "$DATA_DIR/$p/shared_prefs" "$DATA_DIR/$p/files" > /dev/null 2>&1; then
            echo "$n $p" >> "$ACC_FILE"
            echo "$p"
            return 0
        fi
    done
    return 1
}

find_hb() {
    local p="$1" f mp
    for f in $(find /sdcard/Delta /storage/emulated/0/Delta /sdcard /storage/emulated/0 -maxdepth 4 -name 'farmhb_*.txt' 2>/dev/null); do
        mp=$(map_file "$f")
        if [ "$mp" = "$p" ]; then
            echo "$f"
            return 0
        fi
    done
    return 1
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
