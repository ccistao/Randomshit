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
PLACE_ID="123974602339071" # Baseplate lam game vao cua
FILTER="roblox|delta|aya"
CHECK_INTERVAL=${CHECK_INTERVAL:-10}
STALE=${STALE:-210}
JOIN_GRACE=${JOIN_GRACE:-210}
SOFT_GRACE=${SOFT_GRACE:-150}
LAUNCH_WAIT=${LAUNCH_WAIT:-5}
KILL_WAIT=${KILL_WAIT:-2}
CYCLE_RUN=${CYCLE_RUN:-28800}
CYCLE_REST=${CYCLE_REST:-5400}
OFFLINE_ALERT=${OFFLINE_ALERT:-600}
MIN_RAM=${MIN_RAM:-300}
ENABLE_WATCH=${ENABLE_WATCH:-1}
AUTO_CAL=${AUTO_CAL:-1}
CAL_WAIT=${CAL_WAIT:-60}
CAL_THRESH=${CAL_THRESH:-38}
CAL_FRESH=${CAL_FRESH:-45}
CAL_COOLDOWN=${CAL_COOLDOWN:-600}
CAL_MIN_UP=${CAL_MIN_UP:-60}
KICK_STALE=${KICK_STALE:-150}
INITIAL_WAIT=${INITIAL_WAIT:-100}
WATCH_INTERVAL=${WATCH_INTERVAL:-1}
REOPEN_COOLDOWN=${REOPEN_COOLDOWN:-8}
REJOIN_CHECK=${REJOIN_CHECK:-10}
LAUNCH_RETRY=${LAUNCH_RETRY:-20}
ACT_GAP=${ACT_GAP:-25}
REMAP_FRESH=${REMAP_FRESH:-100}
KILLER=${KILLER:-kill}
DEBUG=${DEBUG:-1}
DEBUG_LOG=${DEBUG_LOG:-/data/local/tmp/farm_debug.log}

STATE=${STATE:-/data/local/tmp/farmstate}
ACC_FILE=${ACC_FILE:-/data/local/tmp/accounts.txt}
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
    local p="$1"
    local target_id="$PLACE_ID"
    local hbf=$(rv "hb_$p" "")
    
    # Doc ID game ma Lua da yeu cau truoc khi tu sat
    if [ -n "$hbf" ] && [ -f "$hbf" ]; then
        local bname=$(basename "$hbf" .txt)
        local cid=${bname#farmhb_}
        local dname=$(dirname "$hbf")
        if [ -f "$dname/target_$cid.txt" ]; then
            target_id=$(cat "$dname/target_$cid.txt" | tr -d '\r\n ')
        fi
    fi

    local OUT
    OUT=$(am start -n "$p/com.roblox.client.ActivityProtocolLaunch" -a android.intent.action.VIEW -d "roblox://experiences/start?placeId=$target_id" 2>&1)
    case "$OUT" in
        *Error*|*Exception*|*unable*)
            am start -a android.intent.action.VIEW -p "$p" -d "roblox://experiences/start?placeId=$target_id" > /dev/null 2>&1
            ;;
    esac
}

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

hb_fast_stale() {
    local I
    I=$(cut -d, -f3 "$1" 2>/dev/null | tr -cd '0-9')
    echo $(( ${I:-30} * 4 + 10 ))
}

# ==================================================
# FIX LOI KET SANH: BAT BUOC KILL TRUOC KHI DAY LINK
# ==================================================
soft_push() { 
    local N
    N=$(date +%s)
    echo "$(date +%T) [DAY LAI] Tab $2 ($1): $3 -> Kill va day lai vao game"
    dbg "ACTION soft_push tab=$2 pkg=$1 why=$3"
    
    # KILL luon de dam bao Deep Link hoat dong khi kẹt sảnh
    kill_tab "$1"
    sleep "$KILL_WAIT"

    # Goi app de doc target roi moi xoa bo nho
    launch_app "$1"

    # Xoa bo nho tam de update acc/game moi
    rm -f "$STATE/hb_$1"
    if [ -f "$ACC_FILE" ]; then
        grep -v "[[:space:]]$1$" "$ACC_FILE" > "$ACC_FILE.tmp" 2>/dev/null
        mv "$ACC_FILE.tmp" "$ACC_FILE"
    fi

    wv "launch_$1" "$((N - JOIN_GRACE + SOFT_GRACE))"
    wv "stage_$1" 1; wv "lt_$1" "$N"; wv "up_$1" "$N"
}

init_tabs() {
    local p
    for p in $LIST_CLONE; do
        wv "lt_$p" "$((START - KICK_STALE))"
        if [ -n "$(get_pid "$p")" ]; then wv "launch_$p" "$((START - JOIN_GRACE + INITIAL_WAIT))"; fi
    done
}

open_tab() {
    local N
    echo "$(date +%T) [MO] Tab $2 ($1): mo lai sau gio nghi"
    dbg "ACTION open_after_rest tab=$2 pkg=$1"
    launch_app "$1"
    N=$(date +%s)
    wv "launch_$1" "$N"; wv "up_$1" "$N"; wv "stage_$1" 0; wv "lt_$1" "$N"
    sleep "$LAUNCH_WAIT"
}

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

    # Goi app de doc target roi moi xoa bo nho
    launch_app "$1"

    # Xoa bo nho tam de update acc/game moi
    rm -f "$STATE/hb_$1"
    if [ -f "$ACC_FILE" ]; then
        grep -v "[[:space:]]$1$" "$ACC_FILE" > "$ACC_FILE.tmp" 2>/dev/null
        mv "$ACC_FILE.tmp" "$ACC_FILE"
    fi

    N=$(date +%s)
    wv "launch_$1" "$N"; wv "up_$1" "$N"; wv "stage_$1" 0; wv "lt_$1" "$N"
    sleep "$LAUNCH_WAIT"
}

# Theo doi bong bong tab
watch_visible() {
    local W A a L N S V ST BLK H KEY OLD HBF AGE TH PEND
    while true; do
        if [ ! -f "$PAUSE_FILE" ] && [ ! -f "$STATE/resting" ]; then
            W=$(dumpsys window windows 2>/dev/null)
            A=$(dumpsys activity activities 2>/dev/null)
            N=$(date +%s)
            for a in $LIST_CLONE; do
                [ -n "$(get_pid "$a")" ] || continue
                S=false
                if [ "$(echo "$W" | awk -v pat="u0 $a/" '/^ *Window #/{b=(index($0,pat)>0)} b && /mHasSurface=true/{print "true"; exit}')" = "true" ]; then S=true; fi
                BLK=$(echo "$A" | grep -A16 "ActivityRecord{[^}]* u0 $a/" | head -n 17)
                V=$(echo "$BLK" | grep -oE "visible=(true|false)" | head -n 1 | cut -d= -f2)
                ST=$(echo "$BLK" | grep -oE "state=[A-Z_]+" | head -n 1 | cut -d= -f2)
                KEY="surface=$S visible=${V:-?} state=${ST:-?}"
                OLD=$(rv "wstate_$a" "")
                if [ "$KEY" != "$OLD" ]; then
                    wv "wstate_$a" "$KEY"
                fi
                H=0
                [ "$S" = "false" ] && H=1
                [ "$V" = "false" ] && H=1
                case "$ST" in STOPPED|DESTROYED|FINISHING) H=1 ;; esac

                HBF=$(rv "hb_$a" ""); AGE=""; TH=63
                if [ -n "$HBF" ] && [ -f "$HBF" ]; then AGE=$(hb_age "$HBF"); TH=$(hb_fast_stale "$HBF"); fi
                L=$(rv "lt_$a" 0)

                PEND=$(rv "pend_$a" 0)
                if [ "$PEND" -gt 0 ] && [ $((N - PEND)) -ge "$REJOIN_CHECK" ]; then
                    wv "pend_$a" 0
                    if [ -n "$AGE" ] && [ "$AGE" -le "$TH" ]; then
                        :
                    elif [ -n "$AGE" ] && [ $((N - AGE)) -gt "$(rv "lt_$a" 0)" ] && [ $((N - $(rv "fastrj_$a" 0))) -ge 60 ]; then
                        echo "$(date +%T) [REJOIN NHANH] $a: bi an -> game da dung ${AGE}s -> vao game lai"
                        wv "fastrj_$a" "$N"
                        launch_app "$a"
                        wv "launch_$a" "$N"; wv "up_$a" "$N"; wv "stage_$a" 0; wv "lt_$a" "$N"; wv "gap_$a" 1
                    fi
                fi

                if [ "$H" = "1" ]; then
                    CD=$REOPEN_COOLDOWN
                    [ "$(rv "reopen_n_$a" 0)" -ge 5 ] && CD=60
                    if [ $((N - L)) -ge 10 ] && [ $((N - $(rv "reopen_$a" 0))) -ge "$CD" ]; then
                        wv "reopen_n_$a" "$(( $(rv "reopen_n_$a" 0) + 1 ))"
                        wv "reopen_$a" "$N"; wv "pend_$a" "$N"
                        monkey -p "$a" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1 &
                    fi
                else
                    wv "reopen_n_$a" 0
                fi
            done
        fi
        sleep "$WATCH_INTERVAL"
    done
}

trap 'kill $WATCH_PID 2>/dev/null; exit 0' INT TERM

echo "--- BAT DAU CANH TAB (tam dung: touch $PAUSE_FILE) ---"

init_tabs
WATCH_PID=""
if [ "$ENABLE_WATCH" = "1" ]; then
    watch_visible &
    WATCH_PID=$!
fi

act_ok() { [ $(( $(date +%s) - LAST_ACT )) -ge "$ACT_GAP" ]; }

LAST_ACT=0
RESUME_AT=0
CYCLE_START=$START
MODE=run
REST_UNTIL=0
LAST_REST_PRINT=0
OFFLINE_SINCE=0
OFFLINE_ALERTED=0
LAST_RAM_WARN=0

while true; do
    NOW=$(date +%s)
    LOOP=$((LOOP + 1))

    if [ -f "$PAUSE_FILE" ]; then
        echo "$(date +%T) [PAUSE] xoa $PAUSE_FILE de chay tiep"
        sleep "$CHECK_INTERVAL"
        continue
    fi

    if [ "$MODE" = "rest" ]; then
        if [ "$NOW" -ge "$REST_UNTIL" ]; then
            MODE=run; CYCLE_START=$NOW; RESUME_AT=$NOW; OFFLINE_SINCE=0; OFFLINE_ALERTED=0
            rm -f "$STATE/resting"
            for p in $LIST_CLONE; do
                wv "consec_$p" 0; wv "stage_$p" 0; wv "gap_$p" 0; wv "up_$p" "$NOW"
            done
            echo "$(date +%T) [BAT LAI] het gio nghi, mo lai $TOTAL_CLONE tab (moi tab cach nhau ${ACT_GAP}s)"
        else
            if [ $((NOW - LAST_REST_PRINT)) -ge 60 ]; then
                echo "$(date +%T) [NGHI] con $(( (REST_UNTIL - NOW) / 60 )) phut nua se mo lai"
                LAST_REST_PRINT=$NOW
            fi
            sleep "$CHECK_INTERVAL"
            continue
        fi
    elif [ "$CYCLE_RUN" -gt 0 ] && [ $((NOW - CYCLE_START)) -ge "$CYCLE_RUN" ]; then
        echo "$(date +%T) [NGHI] da treo $((CYCLE_RUN / 3600))h$(((CYCLE_RUN % 3600) / 60))m -> tat het cac tab, nghi $((CYCLE_REST / 60)) phut"
        : > "$STATE/resting"
        for p in $LIST_CLONE; do
            kill_tab "$p"
            sleep "$KILL_WAIT"
        done
        MODE=rest; REST_UNTIL=$(( $(date +%s) + CYCLE_REST )); LAST_REST_PRINT=0
        continue
    fi

    NEED=0
    for p in $LIST_CLONE; do
        f=$(rv "hb_$p" "")
        if [ -z "$f" ] || [ ! -f "$f" ]; then NEED=1; continue; fi
        a=$(hb_age "$f")
        if [ -z "$a" ] || [ "$a" -gt "$REMAP_FRESH" ]; then NEED=1; fi
    done
    if [ "$NEED" = "1" ] && { [ "$LOOP" -eq 1 ] || [ $((LOOP % 4)) -eq 0 ]; }; then
        discover_hb
        remap
        if [ "$AUTO_CAL" = "1" ]; then calibrate; fi
    fi

    NOW=$(date +%s)
    LINE="$(date +%T)"
    OK_COUNT=0
    IDX=0
    for p in $LIST_CLONE; do
        IDX=$((IDX + 1))
        PID=$(get_pid "$p")
        LAUNCHED=$(rv "launch_$p" "$START")
        SINCE=$((NOW - LAUNCHED))
        RUN=$((NOW - $(rv "up_$p" "$START")))

        if [ -z "$PID" ]; then
            if act_ok; then
                if [ "$((NOW - RESUME_AT))" -lt "$((ACT_GAP * TOTAL_CLONE + 120))" ]; then
                    open_tab "$p" "$IDX"
                    LINE="$LINE T$IDX:mo-sau-nghi"
                else
                    restart_tab "$p" "$IDX" "app bi tat / chuyen game" 0 0
                    LINE="$LINE T$IDX:vang"
                fi
                LAST_ACT=$(date +%s)
            else
                LINE="$LINE T$IDX:vang(xep-hang)"
            fi
            continue
        fi

        HBF=$(rv "hb_$p" "")
        AGE=""
        if [ -n "$HBF" ] && [ -f "$HBF" ]; then AGE=$(hb_age "$HBF"); fi

        HB_NEW=0
        if [ -n "$AGE" ] && [ $((NOW - AGE)) -gt "$(rv "lt_$p" 0)" ]; then HB_NEW=1; fi

        if [ "$HB_NEW" = "1" ] && [ "$AGE" -le "$KICK_STALE" ]; then
            OK_COUNT=$((OK_COUNT + 1))
            wv "consec_$p" 0
            wv "stage_$p" 0
            if [ "$(rv "gap_$p" 0)" = "1" ]; then
                wv "gap_$p" 0; wv "up_$p" "$NOW"; RUN=0
            fi
            LINE="$LINE T$IDX:ok(${AGE}s)"
        elif [ "$HB_NEW" = "1" ]; then
            wv "gap_$p" 1
            if act_ok; then
                soft_push "$p" "$IDX" "dang trong game roi mat heartbeat ${AGE}s"
                LAST_ACT=$(date +%s)
                LINE="$LINE T$IDX:day-lai-nhanh"
            else
                LINE="$LINE T$IDX:xep-hang"
            fi
        elif [ "$SINCE" -lt "$JOIN_GRACE" ]; then
            wv "gap_$p" 1
            LINE="$LINE T$IDX:cho(${SINCE}s)"
        elif [ -z "$HBF" ] && [ "$(unmapped_fresh)" -gt 0 ]; then
            LINE="$LINE T$IDX:chua-map"
        else
            wv "gap_$p" 1
            WHY="chua co heartbeat moi (chua vao game / loi doi acc)"
            
            if ! act_ok; then
                LINE="$LINE T$IDX:xep-hang"
            elif [ "$(rv "stage_$p" 0)" = "0" ]; then
                soft_push "$p" "$IDX" "$WHY"
                LAST_ACT=$(date +%s)
                LINE="$LINE T$IDX:day-lai"
            else
                restart_tab "$p" "$IDX" "$WHY (da day lai ma van ket)" 1 0
                LAST_ACT=$(date +%s)
                LINE="$LINE T$IDX:restart"
            fi
        fi
    done
    echo "$LINE"

    if [ "$OK_COUNT" -eq 0 ]; then
        [ "$OFFLINE_SINCE" -eq 0 ] && OFFLINE_SINCE=$NOW
        if [ $((NOW - OFFLINE_SINCE)) -ge "$OFFLINE_ALERT" ] && [ "$OFFLINE_ALERTED" -eq 0 ]; then
            OFFLINE_ALERTED=1
            echo "$(date +%T) [CANH BAO] Khong tab nao co heartbeat tu $((OFFLINE_ALERT/60)) phut."
        fi
    else
        OFFLINE_SINCE=0; OFFLINE_ALERTED=0
    fi

    MEM_NOW=$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)
    if [ -n "$MEM_NOW" ] && [ "$MEM_NOW" -lt "$MIN_RAM" ] && [ $((NOW - LAST_RAM_WARN)) -ge 1800 ]; then
        LAST_RAM_WARN=$NOW
        echo "$(date +%T) [CANH BAO] RAM trong con ${MEM_NOW}MB"
    fi

    [ $((LOOP % 60)) -eq 0 ] && dbg_trim
    sleep "$CHECK_INTERVAL"
done
