#!/system/bin/sh
echo "== farm v5 (heartbeat) =="

# ---------- CAU HINH ----------
PLACE_ID="2753915549"
DISCORD_USER_ID="982107241371013132"
FILTER="roblox|delta|aya"
CHECK_INTERVAL=${CHECK_INTERVAL:-15}    # giay giua cac lan kiem tra
STALE=${STALE:-90}                      # heartbeat cu hon X giay -> coi la ket / disconnect / o sanh
JOIN_GRACE=${JOIN_GRACE:-240}           # sau khi mo app, cho toi da X giay de vao game
LAUNCH_WAIT=${LAUNCH_WAIT:-5}
KILL_WAIT=${KILL_WAIT:-3}
REPORT_EVERY=${REPORT_EVERY:-3600}      # bao cao dinh ky (giay), khong ping

STATE=${STATE:-/data/local/tmp/farmstate}
WH_B64=${WH_B64:-/data/local/tmp/.wh}              # webhook ma hoa base64 (cach cu)
WH_TXT=${WH_TXT:-/data/local/tmp/webhook.txt}      # hoac webhook dang chu thuong
ACC_FILE=${ACC_FILE:-/data/local/tmp/accounts.txt} # tuy chon: moi dong "username package"
PAUSE_FILE=${PAUSE_FILE:-/data/local/tmp/farm_pause}  # tao file nay de tam dung script
HB_SHARED=${HB_SHARED:-"/sdcard/Delta /storage/emulated/0/Delta /sdcard"}
HB_PKGBASE=${HB_PKGBASE:-"/sdcard/Android/data /data/data"}
# ------------------------------

WEBHOOK_URL=""
if [ -f "$WH_B64" ]; then
    WEBHOOK_URL=$(base64 -d "$WH_B64" 2>/dev/null || toybox base64 -d "$WH_B64" 2>/dev/null)
fi
if [ -z "$WEBHOOK_URL" ] && [ -f "$WH_TXT" ]; then
    WEBHOOK_URL=$(tr -d '\r\n ' < "$WH_TXT")
fi
if [ -z "$WEBHOOK_URL" ]; then
    echo "[TUY CHON] gui link webhook neu muon thong bao ve discord"
    echo "           echo \"LINK_WEBHOOK\" > $WH_TXT   (khong co thi script van chay binh thuong)"
fi

LIST_CLONE=$(pm list packages -3 | cut -d: -f2 | grep -iE "$FILTER")
if [ -z "$LIST_CLONE" ]; then
    echo "Khong tim thay clone nao!"
    exit 1
fi
TOTAL_CLONE=$(echo "$LIST_CLONE" | wc -l)
echo "Da nhan dien $TOTAL_CLONE tab:"
echo "$LIST_CLONE"

rm -rf "$STATE"
mkdir -p "$STATE"

START=$(date +%s)
TOTAL_REJOIN=0
LAST_REPORT=$START
LOOP=0
EVENTS=""
PINGMSG=""
PING=0

rv() { local V; V=$(cat "$STATE/$1" 2>/dev/null); echo "${V:-$2}"; }
wv() { echo "$2" > "$STATE/$1"; }

send_discord() {
    local MEM U UPT FIELDS JSON RESP CODE
    [ -z "$WEBHOOK_URL" ] && return 0
    MEM=$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo)
    U=$(( $(date +%s) - START )); UPT="$((U/3600))h$(((U%3600)/60))m"
    FIELDS="[{\"name\":\"RAM trong\",\"value\":\"${MEM}MB\",\"inline\":true},{\"name\":\"Uptime\",\"value\":\"$UPT\",\"inline\":true},{\"name\":\"Tong rejoin\",\"value\":\"$TOTAL_REJOIN\",\"inline\":true}]"
    JSON="{\"content\":\"$1\",\"embeds\":[{\"title\":\"$3\",\"description\":\"$4\",\"color\":$2,\"fields\":$FIELDS,\"footer\":{\"text\":\"$(date +%H:%M:%S)\"}}]}"
    RESP=$(curl -s -4 --connect-timeout 5 -m 15 --retry 2 \
        -H "Content-Type: application/json" -X POST -d "$JSON" \
        -w "\n%{http_code}" "$WEBHOOK_URL" 2>&1)
    CODE=$(echo "$RESP" | tail -n 1)
    case "$CODE" in
        200|204) ;;
        *) echo "[Discord] LOI HTTP $CODE" ;;
    esac
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

# tuoi cua heartbeat (giay). Doc thoi gian trong file, neu khong doc duoc thi dung mtime
hb_age() {
    local T N A
    T=$(cut -d, -f1 "$1" 2>/dev/null | tr -d '\r\n ')
    case "$T" in
        ''|*[!0-9]*) T=$(stat -c %Y "$1" 2>/dev/null) ;;
    esac
    [ -z "$T" ] && return 0
    N=$(date +%s); A=$((N - T)); [ "$A" -lt 0 ] && A=0
    echo "$A"
}

# file heartbeat nay thuoc package nao? (in ra ten package, hoac de trong)
map_file() {
    local f="$1" n p fu pu
    n=$(basename "$f" .txt); n=${n#farmhb_}
    if [ -f "$ACC_FILE" ]; then
        p=$(awk -v n="$n" 'tolower($1)==tolower(n){print $2; exit}' "$ACC_FILE" | tr -d '\r')
        if [ -n "$p" ]; then echo "$p"; return 0; fi
    fi
    for p in $LIST_CLONE; do
        case "$f" in *"$p"*) echo "$p"; return 0 ;; esac
    done
    fu=$(stat -c %u "$f" 2>/dev/null)
    if [ -n "$fu" ] && [ "$fu" != "0" ]; then
        for p in $LIST_CLONE; do
            pu=$(stat -c %u "/data/data/$p" 2>/dev/null)
            if [ "$pu" = "$fu" ]; then echo "$p"; return 0; fi
        done
    fi
    return 0
}

discover_hb() {
    local f p b d cur ca oa
    {
        for d in $HB_SHARED; do
            find "$d" -maxdepth 4 -name 'farmhb_*.txt' 2>/dev/null
        done
        for p in $LIST_CLONE; do
            for b in $HB_PKGBASE; do
                find "$b/$p" -maxdepth 9 -name 'farmhb_*.txt' 2>/dev/null
            done
        done
    } | sort -u > "$STATE/hbfiles"
    while read -r f; do
        [ -f "$f" ] || continue
        p=$(map_file "$f")
        if [ -z "$p" ]; then
            b=$(basename "$f")
            if [ ! -f "$STATE/w_$b" ]; then
                : > "$STATE/w_$b"
                echo "[HB] $b: chua biet thuoc tab nao -> them dong 'username package' vao $ACC_FILE"
            fi
            continue
        fi
        cur=$(rv "hb_$p" "")
        if [ -z "$cur" ] || [ ! -f "$cur" ]; then
            wv "hb_$p" "$f"; echo "[HB] $(basename "$f") -> $p"
        else
            ca=$(hb_age "$f"); oa=$(hb_age "$cur")
            if [ -n "$ca" ] && [ -n "$oa" ] && [ $((ca + 5)) -lt "$oa" ]; then
                wv "hb_$p" "$f"; echo "[HB] $(basename "$f") -> $p"
            fi
        fi
    done < "$STATE/hbfiles"
}

# $1=package $2=so tab $3=ly do $4=1 neu can force-stop truoc
restart_tab() {
    local C R
    C=$(( $(rv "consec_$1" 0) + 1 )); wv "consec_$1" "$C"
    R=$(( $(rv "rj_$1" 0) + 1 )); wv "rj_$1" "$R"
    TOTAL_REJOIN=$((TOTAL_REJOIN + 1))
    echo "$(date +%T) [RESTART] Tab $2 ($1): $3 (lan $C lien tiep)"
    EVENTS="${EVENTS}Tab $2 (\`$1\`): $3 -> restart (lan $C)\\n"
    if [ "$C" -eq 3 ] || { [ "$C" -gt 3 ] && [ $((C % 10)) -eq 0 ]; }; then
        PING=1
        PINGMSG="${PINGMSG}Tab $2 da restart $C lan lien tiep van chua vao duoc game. Kiem tra acc/autoexec.\\n"
    fi
    if [ "$4" = "1" ]; then
        am force-stop "$1"
        sleep "$KILL_WAIT"
    fi
    launch_app "$1"
    wv "launch_$1" "$(date +%s)"
    sleep "$LAUNCH_WAIT"
}

