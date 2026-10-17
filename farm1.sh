#!/system/bin/sh
echo "== farm v6 =="

# ---- kiem tra file co bi loi ky tu la khi copy-paste khong ----
P1='ver'; P2='t{}'; BS='\'
if [ -r "$0" ] && { grep -qF "${P1}${P2}" "$0" 2>/dev/null || grep -qF "${BS}%{" "$0" 2>/dev/null; }; then
    printf '[!] File script bi loi ky tu la (%s%s%s hoac %s%%) do copy-paste.\n' "$BS" "$P1" "$P2" "$BS"
    printf '    Hay UPLOAD file len GitHub (dung dan noi dung), roi chay lai.\n'
    exit 1
fi

# ---------- CAU HINH ----------
PLACE_ID="2753915549"
DISCORD_USER_ID="982107241371013132"
FILTER="roblox|delta|aya"
CHECK_INTERVAL=${CHECK_INTERVAL:-10}    # giay giua cac lan kiem tra
STALE=${STALE:-300}                     # heartbeat cu hon X giay -> coi la ket / o sanh
JOIN_GRACE=${JOIN_GRACE:-300}           # sau khi mo app, cho toi da X giay de vao game
SOFT_GRACE=${SOFT_GRACE:-150}           # sau khi day lai vao game (chua kill), cho them X giay roi moi kill
LAUNCH_WAIT=${LAUNCH_WAIT:-5}
KILL_WAIT=${KILL_WAIT:-2}
MAX_RUN=${MAX_RUN:-7200}                # chay lien tuc X giay thi tu restart cho do lag (0 = tat)
SCHED_GAP=${SCHED_GAP:-60}              # cach nhau it nhat X giay giua 2 lan restart dinh ky
REPORT_EVERY=${REPORT_EVERY:-3600}      # bao cao dinh ky kem anh chup (khong ping)
OFFLINE_ALERT=${OFFLINE_ALERT:-600}     # tat ca tab mat heartbeat qua X giay moi ping
MIN_RAM=${MIN_RAM:-300}                 # RAM trong thap hon X MB thi bao (khong ping)
ENABLE_WATCH=${ENABLE_WATCH:-1}         # 1 = tu bat lai tab bi thu nho thanh bong bong
AUTO_CAL=${AUTO_CAL:-1}                 # 1 = tu doan acc nao la tab nao (tat thu tung tab, chi 1 lan)
CAL_WAIT=${CAL_WAIT:-50}
CAL_THRESH=${CAL_THRESH:-38}
CAL_FRESH=${CAL_FRESH:-45}
CAL_MIN_UP=${CAL_MIN_UP:-60}            # chi hieu chuan sau khi script chay it nhat X giay
KILLER=${KILLER:-kill}

STATE=${STATE:-/data/local/tmp/farmstate}
WH_B64=${WH_B64:-/data/local/tmp/.wh}              # webhook ma hoa base64
WH_TXT=${WH_TXT:-/data/local/tmp/webhook.txt}      # hoac webhook dang chu thuong
ACC_FILE=${ACC_FILE:-/data/local/tmp/accounts.txt} # moi dong "username package" (script tu ghi)
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
if [ -z "$WEBHOOK_URL" ]; then
    echo "[TUY CHON] gui link webhook neu muon thong bao ve discord"
    echo "           echo \"LINK_WEBHOOK\" > $WH_TXT   (khong co thi script van chay binh thuong)"
fi

LIST_CLONE=$(pm list packages -3 | cut -d: -f2 | grep -iE "$FILTER" | tr -d '\r')
if [ -z "$LIST_CLONE" ]; then
    echo "Khong tim thay clone nao!"
    exit 1
fi
TOTAL_CLONE=$(echo "$LIST_CLONE" | wc -l | tr -cd '0-9')
echo "Da nhan dien $TOTAL_CLONE tab:"
echo "$LIST_CLONE"

rm -rf "$STATE"
mkdir -p "$STATE"

START=$(date +%s)
TOTAL_RESTART=0
LAST_REPORT=$START
LOOP=0
EVENTS=""
PINGMSG=""
PING=0

rv() { local V; V=$(cat "$STATE/$1" 2>/dev/null | tr -d '\r\n'); echo "${V:-$2}"; }
wv() { echo "$2" > "$STATE/$1"; }

for p in $LIST_CLONE; do
    wv "launch_$p" "$START"
    wv "up_$p" "$START"
done

send_discord() {   # $1=noi dung (de @mention) $2=mau $3=tieu de $4=mo ta
    local MEM U UPT FIELDS JSON RESP CODE
    [ -z "$WEBHOOK_URL" ] && return 0
    MEM=$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)
    U=$(( $(date +%s) - START )); UPT="$((U/3600))h$(((U%3600)/60))m"
    FIELDS="[{\"name\":\"RAM trong\",\"value\":\"${MEM:-0}MB\",\"inline\":true},{\"name\":\"Uptime\",\"value\":\"$UPT\",\"inline\":true},{\"name\":\"Tong restart\",\"value\":\"$TOTAL_RESTART\",\"inline\":true}]"
    JSON="{\"content\":\"$1\",\"embeds\":[{\"title\":\"$3\",\"description\":\"$4\",\"color\":$2,\"fields\":$FIELDS,\"footer\":{\"text\":\"$(date +%H:%M:%S)\"}}]}"
    RESP=$(curl -s -4 --connect-timeout 5 -m 15 --retry 2 \
        -H "Content-Type: application/json" -X POST -d "$JSON" \
        -w "\n%{http_code}" "$WEBHOOK_URL" 2>&1)
    CODE=$(echo "$RESP" | tail -n 1 | tr -cd '0-9')
    case "$CODE" in
        200|204) ;;
        401|404) echo "[Discord] LOI HTTP $CODE: webhook sai hoac da bi xoa -> tao webhook moi" ;;
        *) echo "[Discord] LOI HTTP ${CODE:-khong co phan hoi}" ;;
    esac
}

send_screenshot() {
    local FILE="/data/local/tmp/screen.png"
    [ -z "$WEBHOOK_URL" ] && return 0
    screencap -p "$FILE" 2>/dev/null || return 0
    curl -s -4 --connect-timeout 5 -m 30 -X POST "$WEBHOOK_URL" \
        -F "payload_json={\"embeds\":[{\"title\":\"ANH CHUP MAN HINH DINH KY\",\"color\":3066993,\"image\":{\"url\":\"attachment://screen.png\"}}]}" \
        -F "file=@$FILE" > /dev/null 2>&1
    rm -f "$FILE"
}

get_pid() {
    local P
    P=$(pidof "$1" 2>/dev/null | cut -d' ' -f1 | tr -cd '0-9')
    if [ -z "$P" ]; then
        P=$(pgrep -f "^$1" 2>/dev/null | head -n 1 | tr -cd '0-9')
    fi
    echo "$P"
}

# chi tat dung tab nay (kill -9 moi tien trinh cua package do)
kill_tab() {
    local P
    for P in $(pidof "$1" 2>/dev/null); do
        $KILLER -9 "$P" 2>/dev/null
    done
    if [ -n "$(get_pid "$1")" ]; then
        sleep 1
        am force-stop "$1" 2>/dev/null
    fi
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
                echo "[HB] $b: chua biet thuoc tab nao"
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

# gan file heartbeat cho 1 package va nho vao accounts.txt (lan sau khoi tao nhanh)
map_save() {
    local f="$1" p="$2" n
    n=$(basename "$f" .txt); n=${n#farmhb_}
    wv "hb_$p" "$f"
    if [ -f "$ACC_FILE" ]; then
        grep -viE "^$n[[:space:]]" "$ACC_FILE" > "$ACC_FILE.tmp" 2>/dev/null
        mv "$ACC_FILE.tmp" "$ACC_FILE"
    fi
    echo "$n $p" >> "$ACC_FILE"
    echo "[HB] $n -> $p (da luu vao $ACC_FILE)"
}

# so file heartbeat dang tuoi nhung chua biet thuoc tab nao
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

# Tu doan acc nao la tab nao: tat tung tab, xem file heartbeat nao ngung cap nhat.
calibrate() {
    local UF="" UP="" f p a K cand NUF REM NOWC
    NOWC=$(date +%s)
    [ $((NOWC - START)) -ge "$CAL_MIN_UP" ] || return 0
    [ -f "$STATE/hbfiles" ] || return 0
    while read -r f; do
        [ -f "$f" ] || continue
        [ -n "$(map_file "$f")" ] && continue
        a=$(hb_age "$f")
        if [ -n "$a" ] && [ "$a" -le "$CAL_FRESH" ]; then UF="$UF$f
"; fi
    done < "$STATE/hbfiles"
    for p in $LIST_CLONE; do
        [ -n "$(get_pid "$p")" ] || continue
        f=$(rv "hb_$p" "")
        if [ -z "$f" ] || [ ! -f "$f" ]; then UP="$UP$p
"; fi
    done
    NUF=$(echo "$UF" | grep -c .); REM=$(echo "$UP" | grep -c .)
    if [ "$NUF" -eq 0 ] || [ "$REM" -eq 0 ]; then return 0; fi
    if [ "$NUF" -gt "$REM" ]; then
        if [ ! -f "$STATE/cal_warn" ]; then
            : > "$STATE/cal_warn"
            echo "[CAL] co $NUF file dang chay nhung chi $REM tab chua map -> khong hieu chuan duoc, hay ghi tay $ACC_FILE"
        fi
        return 0
    fi
    # con tab dang load thi doi them, tru khi da qua lau
    if [ "$NUF" -lt "$REM" ] && [ $((NOWC - START)) -lt $((JOIN_GRACE * 2)) ]; then return 0; fi
    : > "$STATE/cal_done"
    echo "[CAL] $NUF file chua ro tab nao, thu tat tung tab de doan (~${CAL_WAIT}s/tab)"
    for p in $UP; do
        NUF=$(echo "$UF" | grep -c .)
        [ "$NUF" -eq 0 ] && break
        if [ "$NUF" -eq 1 ] && [ "$REM" -eq 1 ]; then
            map_save "$(echo "$UF" | grep .)" "$p"
            UF=""
            break
        fi
        echo "[CAL] tat thu $p ..."
        kill_tab "$p"
        sleep "$CAL_WAIT"
        cand=""; K=0
        for f in $UF; do
            a=$(hb_age "$f")
            if [ -n "$a" ] && [ "$a" -gt "$CAL_THRESH" ]; then cand="$f"; K=$((K + 1)); fi
        done
        if [ "$K" -eq 1 ]; then
            map_save "$cand" "$p"
            UF=$(echo "$UF" | grep -vxF "$cand")
        else
            echo "[CAL] $p: khong chac file nao (K=$K), bo qua"
        fi
        launch_app "$p"
        wv "launch_$p" "$(date +%s)"; wv "up_$p" "$(date +%s)"
        sleep "$LAUNCH_WAIT"
        REM=$((REM - 1))
    done
    NUF=$(echo "$UF" | grep -c .)
    if [ "$NUF" -gt 0 ]; then
        echo "[CAL] xong, con $NUF file chua map duoc: them dong 'username package' vao $ACC_FILE"
    else
        echo "[CAL] xong, da map het."
    fi
}

# $1=package $2=so tab $3=ly do $4=1 neu can kill truoc $5=1 neu la restart dinh ky
restart_tab() {
    local C R N
    if [ "$5" = "1" ]; then
        echo "$(date +%T) [DINH KY] Tab $2 ($1): $3"
        EVENTS="${EVENTS}Tab $2 (\`$1\`): $3\\n"
    else
        C=$(( $(rv "consec_$1" 0) + 1 )); wv "consec_$1" "$C"
        echo "$(date +%T) [RESTART] Tab $2 ($1): $3 (lan $C lien tiep)"
        EVENTS="${EVENTS}Tab $2 (\`$1\`): $3 -> restart (lan $C)\\n"
        if [ "$C" -eq 3 ] || { [ "$C" -gt 3 ] && [ $((C % 10)) -eq 0 ]; }; then
            PING=1
            PINGMSG="${PINGMSG}Tab $2 da restart $C lan lien tiep van chua vao duoc game. Kiem tra acc/autoexec.\\n"
        fi
    fi
    R=$(( $(rv "rj_$1" 0) + 1 )); wv "rj_$1" "$R"
    TOTAL_RESTART=$((TOTAL_RESTART + 1))
    if [ "$4" = "1" ]; then
        kill_tab "$1"
        sleep "$KILL_WAIT"
    fi
    launch_app "$1"
    N=$(date +%s)
    wv "launch_$1" "$N"; wv "up_$1" "$N"; wv "stage_$1" 0
    sleep "$LAUNCH_WAIT"
}
