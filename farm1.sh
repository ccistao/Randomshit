#!/system/bin/sh
echo "== farm v10 (doc log Roblox) =="

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
CHECK_INTERVAL=${CHECK_INTERVAL:-5}     # giay giua cac lan kiem tra
HB_STALE=${HB_STALE:-120}               # Lua bao hieu (FARMHB) cu hon X giay = coi la khong con chay
DISC_WAIT=${DISC_WAIT:-30}              # bi ngat ket noi ma X giay sau van chua vao game lai -> day vao game
JOIN_GRACE=${JOIN_GRACE:-240}           # dang vao game / load qua X giay ma chua co tin hieu -> day vao game
SOFT_GRACE=${SOFT_GRACE:-150}           # sau khi day vao game (chua kill), cho them X giay roi moi kill
INITIAL_WAIT=${INITIAL_WAIT:-60}        # tab da mo san luc bat script: cho X giay xem co tin hieu Lua khong
LAUNCH_WAIT=${LAUNCH_WAIT:-5}
KILL_WAIT=${KILL_WAIT:-2}
ACT_GAP=${ACT_GAP:-25}                  # cach nhau it nhat X giay giua 2 lan mo/day/restart tab (tranh het RAM)
LAUNCH_RETRY=${LAUNCH_RETRY:-20}        # sau khi gui link vao game X giay ma log khong thay "Joining game" thi gui lai 1 lan (0 = tat)
ENABLE_WATCH=${ENABLE_WATCH:-1}         # 1 = tu bat lai tab bi thu nho thanh bong bong
WATCH_INTERVAL=${WATCH_INTERVAL:-1}
REOPEN_COOLDOWN=${REOPEN_COOLDOWN:-8}
DEBUG=${DEBUG:-1}                       # 1 = ghi log chi tiet vao file
DEBUG_LOG=${DEBUG_LOG:-/data/local/tmp/farm_debug.log}
KILLER=${KILLER:-kill}

STATE=${STATE:-/data/local/tmp/farmstate}
PAUSE_FILE=${PAUSE_FILE:-/data/local/tmp/farm_pause}   # tao file nay de tam dung script
# ------------------------------

LIST_CLONE=$(pm list packages -3 | cut -d: -f2 | grep -iE "$FILTER" | tr -d '\r')
if [ -z "$LIST_CLONE" ]; then
    echo "Khong tim thay clone nao!"
    exit 1
fi
TOTAL_CLONE=$(echo "$LIST_CLONE" | wc -l | tr -cd '0-9')
echo "Da nhan dien $TOTAL_CLONE tab:"
echo "$LIST_CLONE"

# don dep tien trinh doc log cua lan chay truoc (neu co)
pkill -f "logcat -b main -v threadtime -T 1" 2>/dev/null

EV="$STATE/ev"
rm -rf "$STATE"
mkdir -p "$STATE" "$EV"
: > "$DEBUG_LOG" 2>/dev/null

START=$(date +%s)
LOOP=0

rv() { local V; V=$(cat "$STATE/$1" 2>/dev/null | tr -d '\r\n'); echo "${V:-$2}"; }
wv() { echo "$2" > "$STATE/$1"; }
ev() { local V; V=$(cat "$EV/$1_$2" 2>/dev/null | tr -d '\r\n'); echo "${V:-0}"; }   # ev <loai> <pid>

dbg() {
    [ "$DEBUG" = "1" ] || return 0
    echo "$(date +%T) $*" >> "$DEBUG_LOG" 2>/dev/null
}
dbg_trim() {
    [ -f "$DEBUG_LOG" ] || return 0
    if [ "$(wc -c < "$DEBUG_LOG" 2>/dev/null | tr -cd '0-9')" -gt 400000 ]; then
        tail -n 1500 "$DEBUG_LOG" > "$DEBUG_LOG.tmp" 2>/dev/null && mv "$DEBUG_LOG.tmp" "$DEBUG_LOG"
    fi
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

# ---------- DOC LOG ROBLOX (logcat) ----------
# Moi dong log co so PID => biet chinh xac tab nao. Ghi su kien moi nhat cua tung PID vao $EV:
#   join_PID = "Joining game"   disc_PID = "Disconnection Notification"   hb_PID = Lua in FARMHB|ten_acc
reader_loop() {
    local line pid now t n=0
    set -f
    while true; do
        logcat -b main -v threadtime -T 1 -s Roblox:I 2>/dev/null | while IFS= read -r line; do
            case "$line" in
                *"Joining game"*|*"Disconnection Notification"*|*"FARMHB|"*) ;;
                *) continue ;;
            esac
            set -- $line
            pid=$3
            case "$pid" in ''|*[!0-9]*) continue ;; esac
            now=$(date +%s)
            case "$line" in
                *"Joining game"*) echo "$now" > "$EV/join_$pid" ;;
                *"Disconnection Notification"*) echo "$now" > "$EV/disc_$pid" ;;
                *"FARMHB|"*)
                    echo "$now" > "$EV/hb_$pid"
                    t=${line#*FARMHB|}
                    echo "${t%%|*}" > "$EV/user_$pid"
                    ;;
            esac
        done
        sleep 2
    done
}
start_reader() {
    reader_loop &
    READER_PID=$!
}
reader_alive() { kill -0 "$READER_PID" 2>/dev/null; }

launch_app() { send_join "$1"; }

# $1=package $2=so tab $3=ly do $4=1 neu can kill truoc
restart_tab() {
    local C N
    C=$(( $(rv "consec_$1" 0) + 1 )); wv "consec_$1" "$C"
    echo "$(date +%T) [RESTART] Tab $2 ($1): $3 (lan $C lien tiep)"
    if [ "$C" -eq 3 ] || { [ "$C" -gt 3 ] && [ $((C % 10)) -eq 0 ]; }; then
        echo "$(date +%T) [CANH BAO] Tab $2 ($1) da restart $C lan lien tiep van chua vao duoc game. Kiem tra acc / autoexec."
    fi
    dbg "ACTION restart tab=$2 pkg=$1 kill=$4 why=$3"
    if [ "$4" = "1" ]; then
        kill_tab "$1"
        sleep "$KILL_WAIT"
    fi
    launch_app "$1"
    N=$(date +%s)
    wv "lt_$1" "$N"; wv "stage_$1" 0; wv "resent_$1" 0
    sleep "$LAUNCH_WAIT"
}

# day lai vao game bang link (KHONG kill app)
soft_push() {   # $1=package $2=so tab $3=ly do
    local N
    N=$(date +%s)
    echo "$(date +%T) [DAY LAI] Tab $2 ($1): $3 -> day lai vao game (chua kill)"
    dbg "ACTION soft_push tab=$2 pkg=$1 why=$3"
    launch_app "$1"
    wv "lt_$1" "$N"; wv "stage_$1" 1; wv "resent_$1" 0
}

# tab da mo san luc bat script thi chi cho INITIAL_WAIT giay xem co tin hieu Lua khong
init_tabs() {
    local p
    for p in $LIST_CLONE; do
        if [ -n "$(get_pid "$p")" ]; then
            wv "lt_$p" "$((START - JOIN_GRACE + INITIAL_WAIT))"
        else
            wv "lt_$p" "$START"
        fi
        wv "resent_$p" 1      # tab co san: khong gui lai link (chi gui lai sau khi chinh script gui link)
    done
}
