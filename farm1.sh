#!/system/bin/sh
echo "== farm v5.1 (heartbeat + auto reset 2h) =="

# ---------- CAU HINH ----------
PLACE_ID="2753915549"
DISCORD_USER_ID="982107241371013132"
FILTER="roblox|delta|aya"
CHECK_INTERVAL=${CHECK_INTERVAL:-10}    # giay giua cac lan kiem tra (giam xuong 10s cho nhanh)
STALE=${STALE:-60}                      # heartbeat cu hon 60s -> coi la ket / disconnect / o sanh
JOIN_GRACE=${JOIN_GRACE:-75}            # sau khi mo app, cho toi da 75s de vao game
MAX_UPTIME=${MAX_UPTIME:-7200}          # 7200 giay (2 tieng) khong vang/out -> tu tat bat lai xoa lag
LAUNCH_WAIT=${LAUNCH_WAIT:-5}
KILL_WAIT=${KILL_WAIT:-2}
REPORT_EVERY=${REPORT_EVERY:-3600}      # bao cao dinh ky 1 tieng (3600s)
ENABLE_WATCH=${ENABLE_WATCH:-1}         # 1 = tu bat lai bong bong tab bi thu nho
AUTO_CAL=${AUTO_CAL:-0}                 # 0 = tat calibrate mac dinh de khong bi treo 50s/tab luc dau
CAL_WAIT=${CAL_WAIT:-50}
CAL_THRESH=${CAL_THRESH:-38}

STATE=${STATE:-/data/local/tmp/farmstate}
WH_B64=${WH_B64:-/data/local/tmp/.wh}
WH_TXT=${WH_TXT:-/data/local/tmp/webhook.txt}
ACC_FILE=${ACC_FILE:-/data/local/tmp/accounts.txt}
PAUSE_FILE=${PAUSE_FILE:-/data/local/tmp/farm_pause}
HB_SHARED=${HB_SHARED:-"/sdcard/Delta /storage/emulated/0/Delta /sdcard"}
HB_PKGBASE=${HB_PKGBASE:-"/sdcard/Android/data /data/data"}
DATA_DIR=${DATA_DIR:-/data/data}
# ------------------------------

WEBHOOK_URL=""
if [ -f "$WH_B64" ]; then
    WEBHOOK_URL=$(base64 -d "$WH_B64" 2>/dev/null || toybox base64 -d "$WH_B64" 2>/dev/null)
fi
if [ -z "$WEBHOOK_URL" ] && [ -f "$WH_TXT" ]; then
    WEBHOOK_URL=$(tr -d '\r\n ' < "$WH_TXT")
fi

LIST_CLONE=$(pm list packages -3 | cut -d: -f2 | grep -iE "$FILTER" | tr -d '\r')
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

rv() { local V; V=$(cat "$STATE/$1" 2>/dev/null \vert{} tr -d '\r\n'); echo "${V:-$2}"; }
wv() { echo "$2" > "$STATE/$1"; }

# Khoi tao moc uptime 2 tieng cho cac tab ngay tu dau
for p in $LIST_CLONE; do
    wv "uptime_$p" "$START"
    wv "launch_$p" 0
done

send_discord() {
    local MEM U UPT FIELDS JSON RESP CODE
    [ -z "$WEBHOOK_URL" ] && return 0
    MEM=$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)
    [ -z "$MEM" ] && MEM=$(awk '/MemFree/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)
    MEM=${MEM:-0}
    U=$(($(date +%s) - START )); UPT="$((U/3600))h$(((U%3600)/60))m"
    FIELDS="[{\"name\":\"RAM trong\",\"value\":\"${MEM}MB\",\"inline\":true},{\"name\":\"Uptime\",\"value\":\"$UPT\",\"inline\":true},{\"name\":\"Tong rejoin\",\"value\":\"$TOTAL_REJOIN\",\"inline\":true}]"
    JSON="{\"content\":\"$1\",\"embeds\":[{\"title\":\"$3\",\"description\":\"$4\",\"color\":$2,\"fields\":$FIELDS,\"footer\":{\"text\":\"$(date +%H:%M:%S)\"}}]}"
    RESP=$(curl -s -4 --connect-timeout 5 -m 15 --retry 2 \
        -H "Content-Type: application/json" -X POST -d "$JSON" \
        -w "\n%{http_code}" "$WEBHOOK_URL" 2>&1)
    CODE=$(echo "$RESP" | tail -n 1 | tr -cd '0-9')
    case "$CODE" in
        *200*|*204*) ;;
        *) echo "[Discord] LOI HTTP $CODE" ;;
    esac
}

get_pid() {
    local P
    P=$(pidof "$1" 2>/dev/null | awk '{print $1}')
    if [ -z "$P" ]; then
        P=$(pgrep -f "^$1" 2>/dev/null | head -n 1)
    fi
    echo "$P" | tr -cd '0-9'
}

# Kiem tra nhanh xem tab co ket noi UDP cua server game khong (ngoai sanh = < 2 cong)
has_game_udp() {
    local P U CNT
    P=$(get_pid "$1")
    [ -z "$P" ] && return 1
    U=$(awk '/^Uid:/{print $2}' "/proc/$P/status" 2>/dev/null | tr -cd '0-9')
    [ -z "$U" ] && return 1
    CNT=$(awk -v u="$U" 'NR>1 && $8==u {c++} END{print c+0}' /proc/net/udp /proc/net/udp6 2>/dev/null | tr -cd '0-9')
    [ "${CNT:-0}" -ge 2 ]
}

launch_app() {
    local OUT
    # Neu app dang tat han, dung monkey bung cua so len truoc roi moi ban link vao game
    if [ -z "$(get_pid "$1")" ]; then
        monkey -p "$1" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
        sleep 4
    fi
    OUT=$(am start -n "$1/com.roblox.client.ActivityProtocolLaunch" -a android.intent.action.VIEW -d "roblox://experiences/start?placeId=$PLACE_ID" 2>&1)
    case "$OUT" in
        *Error*|*Exception*|*unable*)
            am start -a android.intent.action.VIEW -p "$1" -d "roblox://experiences/start?placeId=$PLACE_ID" > /dev/null 2>&1
            ;;
    esac
}

hb_age() {
    local T N A
    T=$(cut -d, -f1 "$1" 2>/dev/null | tr -cd '0-9')
    if [ -z "$T" ]; then
        T=$(stat -c %Y "$1" 2>/dev/null | tr -cd '0-9')
    fi
    [ -z "$T" ] && return 0
    N=$(date +%s); A=$((N - T)); [ "$A" -lt 0 ] && A=0
    echo "$A"
}

map_file() {
    local f="$1" n p fu pu M K d
    n=$(basename "$f" .txt); n=${n#farmhb_}
    if [ -f "$ACC_FILE" ]; then
        p=$(awk -v n="$n" 'tolower($1)==tolower(n){print $2; exit}' "$ACC_FILE" | tr -d '\r')
        if [ -n "$p" ]; then echo "$p"; return 0; fi
    fi
    for p in $LIST_CLONE; do
        case "$f" in *"$p"*) echo "$p"; return 0 ;; esac
    done
    if [ ! -f "$STATE/ng_$n" ]; then
        M=""; K=0
        for p in $LIST_CLONE; do
            for d in shared_prefs files app_webview; do
                if grep -rlsF "$n" "$DATA_DIR/$p/$d" > /dev/null 2>&1; then M="$p"; K=$((K + 1)); break; fi
            done
        done
        if [ "$K" -eq 1 ]; then echo "$M"; return 0; fi
        : > "$STATE/ng_$n"
    fi
    fu=$(stat -c \%u "$f" 2>/dev/null)
    if [ -n "$fu" ] && [ "$fu" != "0" ]; then
        for p in $LIST_CLONE; do
            pu=$(stat -c %u "$DATA_DIR/$p" 2>/dev/null)
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
                echo "[HB] $b: chua biet thuoc tab nao -> them dong 'username package' vao$ACC_FILE"
            fi
            continue
        fi
        cur=$(rv "hb_$p" "")
        if [ -z "$cur" ] \vert{}\vert{} [ ! -f "$cur" ]; then
            wv "hb_$p" "$f"; echo "[HB] $(basename "$f") -> $p"
        else
            ca=$(hb_age "$f"); oa=$(hb_age "$cur")
            if [ -n "$ca" ] && [ -n "$oa" ] && [ $((ca + 5)) -lt "$oa" ]; then
                wv "hb_$p" "$f"; echo "[HB] $(basename "$f") -> $p"
            fi
        fi
    done < "$STATE/hbfiles"
}

map_save() {
    local f="$1" p="$2" n
    n=$(basename "$f" .txt); n=${n#farmhb_}
    wv "hb_$p" "$f"
    if [ -f "$ACC_FILE" ]; then
        grep -viE "^$n[[:space:]]" "$ACC_FILE" > "$ACC_FILE.tmp" 2>/dev/null
        mv "$ACC_FILE.tmp" "$ACC_FILE"
    fi
    echo "$n $p" >> "$ACC_FILE"
    echo "[HB] $n -> $p (da luu vao$ACC_FILE)"
}

unmapped_fresh() {
    local f a c=0
    [ -f "$STATE/hbfiles" ] || { echo 0; return 0; }
    while read -r f; do
        [ -f "$f" ] || continue
        a=$(hb_age "$f")
        [ -n "$a" ] && [ "$a" -le "$STALE" ] || continue
        [ -z "$(map_file "$f")" ] && c=$((c + 1))
    done < "$STATE/hbfiles"
    echo "$c"
}

calibrate() {
    local UF="" UP="" f p a K cand NUF REM NOW_TS
    while read -r f; do
        [ -f "$f" ] || continue
        [ -n "$(map_file "$f")" ] && continue
        a=$(hb_age "$f")
        if [ -n "$a" ] && [ "$a" -le "$STALE" ]; then UF="$UF$f
"; fi
    done < "$STATE/hbfiles"
    for p in $LIST_CLONE; do
        f=$(rv "hb_$p" "")
        if [ -z "$f" ] \vert{}\vert{} [ ! -f "$f" ]; then UP="$UP$p
"; fi
    done
    NUF=$(echo "$UF" | grep -c .); REM=$(echo "$UP" | grep -c .)
    if [ "$NUF" -eq 0 ] \vert{}\vert{} [ "$REM" -eq 0 ]; then return 0; fi
    : > "$STATE/cal_done"
    echo "[CAL] $NUF file chua ro tab nao, thu tat tung tab de doan (~${CAL_WAIT}s/tab)"
    for p in $UP; do
        NUF=$(echo "$UF" | grep -c .)
        [ "$NUF" -eq 0 ] && break
        if [ "$NUF" -eq 1 ] && [ "$REM" -eq 1 ]; then
            map_save "$(echo "$UF" \vert{} grep .)" "$p"
            UF=""
            break
        fi
        echo "[CAL] tat thu $p ..."
        am force-stop "$p"
        sleep "$CAL_WAIT"
        cand=""; K=0
        for f in $UF; do
            a=$(hb_age "$f")
            if [ -n "$a" ] && [ "$a" -gt "$CAL_THRESH" ]; then cand="$f"; K=$((K + 1)); fi
        done
        if [ "$K" -eq 1 ]; then
            map_save "$cand" "$p"
            UF=$(echo "$UF" \vert{} grep -vxF "$cand")
        else
            echo "[CAL] $p: khong chac file nao (K=$K), bo qua"
        fi
        launch_app "$p"
        NOW_TS=$(date +%s)
        wv "launch_$p" "$NOW_TS"
        wv "uptime_$p" "$NOW_TS"
        sleep "$LAUNCH_WAIT"
        REM=$((REM - 1))
    done
}

# $1=package $2=so tab $3=ly do $4=1 neu can force-stop truoc $5=1 neu la reset dinh ky 2h
restart_tab() {
    local C R NOW_TS
    if [ "$5" = "1" ]; then
        C=0
        wv "consec_$1" 0
    else
        C=$(($(rv "consec_$1" 0) + 1 ))
        wv "consec_$1" "$C"
    fi
    R=$(($(rv "rj_$1" 0) + 1 )); wv "rj_$1" "$R"
    TOTAL_REJOIN=$((TOTAL_REJOIN + 1))
    echo "$(date +%T) [RESTART] Tab $2 ($1): $3"
    EVENTS="${EVENTS}Tab $2 (\`$1\`): $3 -> restart (tong lan $R)\\n"
    if [ "$C" -eq 3 ] || { [ "$C" -gt 3 ] && [ $((C % 10)) -eq 0 ]; }; then
        PING=1
        PINGMSG="${PINGMSG}Tab $2 da restart $C lan lien tiep van chua vao duoc game. Kiem tra acc/autoexec.\\n"
    fi
    if [ "$4" = "1" ]; then
        am force-stop "$1"
        sleep "$KILL_WAIT"
    fi
    launch_app "$1"
    NOW_TS=$(date +%s)
    wv "launch_$1" "$NOW_TS"
    # Reset lai bo dem 2 tieng moi khi tab bi tat bat lai
    wv "uptime_$1" "$NOW_TS"
    sleep "$LAUNCH_WAIT"
}
