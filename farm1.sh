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
FILTER="roblox|delta|aya"
CHECK_INTERVAL=${CHECK_INTERVAL:-10}    # giay giua cac lan kiem tra
STALE=${STALE:-210}                     # heartbeat cu hon X giay -> coi la ket / o sanh
JOIN_GRACE=${JOIN_GRACE:-210}           # sau khi mo app, cho toi da X giay de vao game
SOFT_GRACE=${SOFT_GRACE:-150}           # sau khi day lai vao game (chua kill), cho them X giay roi moi kill
LAUNCH_WAIT=${LAUNCH_WAIT:-5}
KILL_WAIT=${KILL_WAIT:-2}
CYCLE_RUN=${CYCLE_RUN:-28800}            # treo lien tuc X giay (mac dinh 8 tieng) roi tat het cac tab de nghi, bat ke dang o dau (0 = tat)
CYCLE_REST=${CYCLE_REST:-5400}          # nghi X giay (mac dinh 1 tieng 30 phut) roi tu mo lai tat ca
OFFLINE_ALERT=${OFFLINE_ALERT:-600}     # tat ca tab mat heartbeat qua X giay thi in canh bao tren man hinh
MIN_RAM=${MIN_RAM:-300}                 # RAM trong thap hon X MB thi in canh bao tren man hinh
ENABLE_WATCH=${ENABLE_WATCH:-1}         # 1 = tu bat lai tab bi thu nho thanh bong bong
AUTO_CAL=${AUTO_CAL:-1}                 # 1 = tu doan acc nao la tab nao (tat thu tung tab, chi 1 lan)
CAL_WAIT=${CAL_WAIT:-60}
CAL_THRESH=${CAL_THRESH:-38}
CAL_FRESH=${CAL_FRESH:-45}
CAL_COOLDOWN=${CAL_COOLDOWN:-600}         # toi thieu X giay giua 2 lan hieu chuan (kill thu)
CAL_MIN_UP=${CAL_MIN_UP:-60}            # chi hieu chuan sau khi script chay it nhat X giay
KICK_STALE=${KICK_STALE:-150}           # dang trong game ma mat heartbeat qua X giay -> day lai vao game ngay (may ban co luc heartbeat cach nhau 80s)
INITIAL_WAIT=${INITIAL_WAIT:-100}       # tab da mo san luc bat script ma chua co heartbeat: cho X giay roi day vao game
WATCH_INTERVAL=${WATCH_INTERVAL:-1}     # giay giua 2 lan kiem tra bong bong
REOPEN_COOLDOWN=${REOPEN_COOLDOWN:-8}   # toi thieu X giay giua 2 lan bat lai cung 1 tab
REJOIN_CHECK=${REJOIN_CHECK:-10}        # sau khi bat lai tab, cho X giay roi kiem tra game con song khong
LAUNCH_RETRY=${LAUNCH_RETRY:-20}        # sau khi gui link vao game X giay ma chua co heartbeat moi thi gui lai 1 lan (0 = tat)
ACT_GAP=${ACT_GAP:-25}                  # cach nhau it nhat X giay giua 2 lan mo/restart tab (tranh het RAM do mo nhieu tab cung luc)
REMAP_FRESH=${REMAP_FRESH:-100}         # heartbeat moi hon X giay moi tinh la dang chay (de doan acc moi dang nhap vao tab nao)
KILLER=${KILLER:-kill}
DEBUG=${DEBUG:-1}                       # 1 = ghi log chi tiet vao file (khong lam roi man hinh)
DEBUG_LOG=${DEBUG_LOG:-/data/local/tmp/farm_debug.log}

STATE=${STATE:-/data/local/tmp/farmstate}
ACC_FILE=${ACC_FILE:-/data/local/tmp/accounts.txt} # moi dong "username package" (script tu ghi)
PAUSE_FILE=${PAUSE_FILE:-/data/local/tmp/farm_pause}
HB_SHARED=${HB_SHARED:-"/storage/emulated/0/Delta /sdcard/Delta"}
HB_PKGBASE=${HB_PKGBASE:-"/sdcard/Android/data /data/data"}
DATA_DIR=${DATA_DIR:-/data/data}
# ------------------------------

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
: > "$DEBUG_LOG" 2>/dev/null

START=$(date +%s)
LOOP=0

rv() { local V; V=$(cat "$STATE/$1" 2>/dev/null | tr -d '\r\n'); echo "${V:-$2}"; }
wv() { echo "$2" > "$STATE/$1"; }

# ghi log chi tiet vao file: dbg "dong" hoac dbg "tieu de" "noi dung nhieu dong"
dbg() {
    [ "$DEBUG" = "1" ] || return 0
    if [ -n "$2" ]; then
        { echo "$(date +%T) $1"; echo "$2" | sed 's/^/      /'; } >> "$DEBUG_LOG" 2>/dev/null
    else
        echo "$(date +%T) $1" >> "$DEBUG_LOG" 2>/dev/null
    fi
}
dbg_trim() {
    [ -f "$DEBUG_LOG" ] || return 0
    if [ "$(wc -c < "$DEBUG_LOG" 2>/dev/null | tr -cd '0-9')" -gt 400000 ]; then
        tail -n 1500 "$DEBUG_LOG" > "$DEBUG_LOG.tmp" 2>/dev/null && mv "$DEBUG_LOG.tmp" "$DEBUG_LOG"
    fi
}

for p in $LIST_CLONE; do
    wv "launch_$p" "$START"
    wv "up_$p" "$START"
done

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
        echo "$(date +%T) [KILL] $1 pid=$P"
        $KILLER -9 "$P" 2>/dev/null
    done
    if [ -n "$(get_pid "$1")" ]; then
        sleep 1
        am force-stop "$1" 2>/dev/null
    fi
}

send_join() {
    local OUT
    OUT=$(am start -n "$1/com.roblox.client.ActivityProtocolLaunch" -a android.intent.action.VIEW -d "roblox://experiences/start?placeId=$PLACE_ID" 2>&1)
    case "$OUT" in
        *Error*|*Exception*|*unable*)
            am start -a android.intent.action.VIEW -p "$1" -d "roblox://experiences/start?placeId=$PLACE_ID" > /dev/null 2>&1
            ;;
    esac
}

# gui link vao game; neu sau LAUNCH_RETRY giay van chua co heartbeat moi (app chi mo ma khong vao game) thi gui lai 1 lan
launch_app() {
    send_join "$1"
    if [ "$LAUNCH_RETRY" -gt 0 ]; then
        ( sleep "$LAUNCH_RETRY"; retry_join "$1" ) 2> /dev/null &
    fi
}

retry_join() {
    local p="$1" f age lt N
    [ -n "$(get_pid "$p")" ] || return 0
    f=$(rv "hb_$p" ""); lt=$(rv "lt_$p" 0); N=$(date +%s)
    if [ -n "$f" ] && [ -f "$f" ]; then
        age=$(hb_age "$f")
        if [ -n "$age" ] && [ $((N - age)) -gt "$lt" ]; then return 0; fi
    fi
    echo "$(date +%T) [GUI LAI LINK] $p: chua co heartbeat moi sau ${LAUNCH_RETRY}s -> gui lai link vao game"
    dbg "ACTION retry_join pkg=$p"
    send_join "$p"
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
    } | sort -u | {
        # cung 1 file that co the hien qua nhieu duong dan (/sdcard va /storage/emulated/0) -> chi giu 1 dong cho moi ten file
        SEEN=""
        while read -r f; do
            b=${f##*/}
            case "$SEEN" in
                *"|$b|"*) ;;
                *) SEEN="$SEEN|$b|"; echo "$f" ;;
            esac
        done
    } > "$STATE/hbfiles"
    dbg "DISCOVER hbfiles" "$(while read -r f; do echo "$f age=$(hb_age "$f") mapped=$(map_file "$f")"; done < "$STATE/hbfiles")"
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

# file heartbeat dang tuoi (<= REMAP_FRESH) nhung chua biet thuoc tab nao
cand_files() {
    local f a
    [ -f "$STATE/hbfiles" ] || return 0
    while read -r f; do
        [ -f "$f" ] || continue
        a=$(hb_age "$f")
        [ -n "$a" ] && [ "$a" -le "$REMAP_FRESH" ] || continue
        [ -z "$(map_file "$f")" ] && echo "$f"
    done < "$STATE/hbfiles"
}

# tab dang chay nhung khong co file heartbeat nao (da map) con tuoi
orphan_pkgs() {
    local p f a ok
    for p in $LIST_CLONE; do
        [ -n "$(get_pid "$p")" ] || continue
        ok=0
        if [ -f "$STATE/hbfiles" ]; then
            while read -r f; do
                [ -f "$f" ] || continue
                [ "$(map_file "$f")" = "$p" ] || continue
                a=$(hb_age "$f")
                if [ -n "$a" ] && [ "$a" -le "$REMAP_FRESH" ]; then ok=1; break; fi
            done < "$STATE/hbfiles"
        fi
        [ "$ok" = "0" ] && echo "$p"
    done
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

# Dang nhap acc moi vao 1 tab: tab do khong con file heartbeat tuoi + co dung 1 file moi chua map => ghep luon (khong can kill)
remap() {
    local C O NC NO f p
    C=$(cand_files); O=$(orphan_pkgs)
    NC=$(echo "$C" | grep -c .); NO=$(echo "$O" | grep -c .)
    dbg "REMAP cand=$NC orphan=$NO" "candidates: $(echo $C)  orphans: $(echo $O)"
    if [ "$NC" -eq 1 ] && [ "$NO" -eq 1 ]; then
        f=$(echo "$C" | grep .); p=$(echo "$O" | grep .)
        echo "$(date +%T) [REMAP] $(basename "$f") -> $p (acc moi dang nhap vao tab nay)"
        map_save "$f" "$p"
    fi
}

# Tu doan acc nao la tab nao: tat tung tab, xem file heartbeat nao ngung cap nhat.
calibrate() {
    local UF UP f p a K cand NUF REM NOWC LASTC FAILS
    NOWC=$(date +%s)
    [ $((NOWC - START)) -ge "$CAL_MIN_UP" ] || return 0
    [ -f "$STATE/hbfiles" ] || return 0
    LASTC=$(rv "cal_last" 0)
    [ $((NOWC - LASTC)) -ge "$CAL_COOLDOWN" ] || return 0
    UF=$(cand_files); UP=$(orphan_pkgs)
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
    wv "cal_last" "$NOWC"
    FAILS=0
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
        for f in $UF; do wv "a0_$(basename "$f")" "$(hb_age "$f")"; done
        kill_tab "$p"
        sleep "$CAL_WAIT"
        cand=""; K=0
        for f in $UF; do
            a=$(hb_age "$f")
            if [ -n "$a" ] && [ "$a" -gt "$CAL_THRESH" ] && [ "$a" -ge $(( $(rv "a0_$(basename "$f")" 0) + CAL_WAIT - 10 )) ]; then cand="$f"; K=$((K + 1)); fi
        done
        if [ "$K" -eq 1 ]; then
            map_save "$cand" "$p"
            UF=$(echo "$UF" | grep -vxF "$cand")
            FAILS=0
        else
            echo "[CAL] $p: khong chac file nao (K=$K), bo qua"
            FAILS=$((FAILS + 1))
        fi
        launch_app "$p"
        wv "launch_$p" "$(date +%s)"; wv "up_$p" "$(date +%s)"; wv "lt_$p" "$(date +%s)"
        sleep "$LAUNCH_WAIT"
        REM=$((REM - 1))
        if [ "$FAILS" -ge 2 ]; then
            echo "[CAL] doan sai 2 lan lien tiep -> dung, khong tat them tab nao. Hay ghi tay $ACC_FILE"
            wv "cal_last" "$(( $(date +%s) + CAL_COOLDOWN * 2 ))"
            return 0
        fi
    done
    NUF=$(echo "$UF" | grep -c .)
    if [ "$NUF" -gt 0 ]; then
        echo "[CAL] xong, con $NUF file chua map duoc: them dong 'username package' vao $ACC_FILE"
    else
        echo "[CAL] xong, da map het."
    fi
}

# nguong "heartbeat da dung" theo chu ky ghi cua Lua (truong thu 3 trong file), mac dinh chu ky 30s
hb_fast_stale() {
    local I
    I=$(cut -d, -f3 "$1" 2>/dev/null | tr -cd '0-9')
    echo $(( ${I:-30} * 4 + 10 ))
}

# day lai vao game bang link (KHONG kill app)
soft_push() {   # $1=package $2=so tab $3=ly do
    local N
    N=$(date +%s)
    echo "$(date +%T) [DAY LAI] Tab $2 ($1): $3 -> day lai vao game (chua kill)"
    dbg "ACTION soft_push tab=$2 pkg=$1 why=$3"
    launch_app "$1"
    wv "launch_$1" "$((N - JOIN_GRACE + SOFT_GRACE))"
    wv "stage_$1" 1; wv "lt_$1" "$N"; wv "up_$1" "$N"
}

# tab da mo san luc bat script thi khong can cho het JOIN_GRACE, chi cho INITIAL_WAIT
init_tabs() {
    local p
    for p in $LIST_CLONE; do
        wv "lt_$p" "$((START - KICK_STALE))"
        if [ -n "$(get_pid "$p")" ]; then wv "launch_$p" "$((START - JOIN_GRACE + INITIAL_WAIT))"; fi
    done
}

# mo tab sau gio nghi: khong tinh la loi, khong dem restart, khong gui tin
open_tab() {   # $1=package $2=so tab
    local N
    echo "$(date +%T) [MO] Tab $2 ($1): mo lai sau gio nghi"
    dbg "ACTION open_after_rest tab=$2 pkg=$1"
    launch_app "$1"
    N=$(date +%s)
    wv "launch_$1" "$N"; wv "up_$1" "$N"; wv "stage_$1" 0; wv "lt_$1" "$N"
    sleep "$LAUNCH_WAIT"
}

# $1=package $2=so tab $3=ly do $4=1 neu can kill truoc
restart_tab() {
    local C R N
    C=$(( $(rv "consec_$1" 0) + 1 )); wv "consec_$1" "$C"
    echo "$(date +%T) [RESTART] Tab $2 ($1): $3 (lan $C lien tiep)"
    if [ "$C" -eq 3 ] || { [ "$C" -gt 3 ] && [ $((C % 10)) -eq 0 ]; }; then
        echo "$(date +%T) [CANH BAO] Tab $2 ($1) da restart $C lan lien tiep van chua vao duoc game. Kiem tra acc / autoexec."
    fi
    R=$(( $(rv "rj_$1" 0) + 1 )); wv "rj_$1" "$R"
    if [ "$4" = "1" ]; then
        kill_tab "$1"
        sleep "$KILL_WAIT"
    fi
    launch_app "$1"
    N=$(date +%s)
    wv "launch_$1" "$N"; wv "up_$1" "$N"; wv "stage_$1" 0; wv "lt_$1" "$N"
    sleep "$LAUNCH_WAIT"
}
