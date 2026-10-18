#!/system/bin/sh
# DEBUG rieng: tat THU 1 tab roi xem co tab khac / Termux bi tat theo khong, va ghi lai ly do (logcat).
export PATH="$PATH:/data/data/com.termux/files/usr/bin"
echo "== debug kill v1 =="

PLACE_ID="2753915549"
FILTER="roblox|delta|aya"
OUT=${OUT:-/data/local/tmp/debug_kill_report.txt}
COPY_TO=${COPY_TO:-/sdcard/Download/debug_kill_report.txt}
LOGC=${LOGC:-/data/local/tmp/debug_kill_logcat.txt}
WATCH_SECS=${WATCH_SECS:-45}
METHOD=${METHOD:-kill}            # kill = kill -9 theo PID (nhu farm) | force = am force-stop
KILLER=${KILLER:-kill}
PATTERN='lmkd|lowmemory|am_kill|am_proc_died|am_low_memory|Killing|has died|force.?stop|Force finishing|SIGKILL|signal 9|FATAL|ANR|termux|og\.launcher|Slow operation|am_crash'

# che do doc lai sau khi Termux bi dong: POST=1 sh debug_kill.sh
if [ "$POST" = "1" ]; then
    echo "--- (doc lai logcat da luu) ---" >> "$OUT"
    grep -aE "$PATTERN" "$LOGC" 2>/dev/null | tail -n 250 >> "$OUT"
    cp "$OUT" "$COPY_TO" 2>/dev/null
    echo "Da ghi them vao $COPY_TO. Hay gui file nay cho Claude."
    exit 0
fi

if pgrep -f "farm.sh" > /dev/null 2>&1 && [ "$FORCE" != "1" ]; then
    echo "[!] Script farm dang chay. Bam Ctrl+C o cua so Termux dang chay farm de tat, roi chay lai."
    exit 1
fi

: > "$OUT"
say() { echo "$*"; echo "$*" >> "$OUT"; }
rep() { echo "$*" >> "$OUT"; }

LIST=$(pm list packages -3 | cut -d: -f2 | grep -iE "$FILTER" | tr -d '\r')
[ -n "$LIST" ] || { say "Khong tim thay clone nao!"; exit 1; }

meminfo_line() { echo "MemAvailable=$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo)MB SwapFree=$(awk '/SwapFree/{printf "%d", $2/1024}' /proc/meminfo)MB"; }
snap() {   # snap "nhan" -> ghi pid cua Termux va moi tab
    local p line
    line="termux=$(pidof com.termux 2>/dev/null | cut -d' ' -f1)"
    for p in $LIST; do line="$line ${p#aya.}=$(pidof "$p" 2>/dev/null | cut -d' ' -f1)"; done
    echo "$1 | $line | $(meminfo_line)"
}

rep "===== 0. THONG TIN BAN DAU ====="
rep "$(snap "luc dau")"
rep "MemTotal=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)MB ro.config.low_ram=$(getprop ro.config.low_ram) zram=$(grep -c zram /proc/swaps 2>/dev/null)"
rep "--- dumpsys meminfo (tom tat):"; dumpsys meminfo 2>/dev/null | grep -E "Total RAM|Free RAM|Used RAM|Lost RAM|ZRAM" >> "$OUT"
rep "--- oom_score_adj / RSS cua tung tien trinh (adj cang thap cang kho bi giet):"
for p in com.termux $LIST; do
    pid=$(pidof "$p" 2>/dev/null | cut -d' ' -f1)
    [ -n "$pid" ] && rep "$p pid=$pid adj=$(cat /proc/$pid/oom_score_adj 2>/dev/null) rss=$(awk '/VmRSS/{printf "%d", $2/1024}' /proc/$pid/status 2>/dev/null)MB"
done
rep "--- chuoi tien trinh cua script nay (su -> sh): pid=$$ adj=$(cat /proc/$$/oom_score_adj 2>/dev/null) ppid=$(awk '/PPid/{print $2}' /proc/$$/status)"
PP=$(awk '/PPid/{print $2}' /proc/$$/status)
rep "   cha: $(cat /proc/$PP/cmdline 2>/dev/null | tr '\0' ' ' | cut -c1-80)"

# chon tab de tat thu: TARGET=aya.xxx hoac tab cuoi cung dang chay
if [ -z "$TARGET" ]; then
    for p in $LIST; do [ -n "$(pidof "$p" 2>/dev/null)" ] && TARGET=$p; done
fi
[ -n "$TARGET" ] || { say "[!] Khong co tab nao dang chay."; exit 1; }
TPIDS=$(pidof "$TARGET" 2>/dev/null)
say ""
say "[BUOC 1] Se tat thu DUNG 1 tab: $TARGET (pid $TPIDS), cach: $METHOD"
say "         Tab nay se duoc mo lai vao game sau khi xong. Bam Ctrl+C trong 6 giay neu muon huy."
sleep 6

logcat -b all -c 2>/dev/null
if command -v setsid > /dev/null 2>&1; then
    setsid logcat -b all -v threadtime > "$LOGC" 2>/dev/null &
else
    logcat -b all -v threadtime > "$LOGC" 2>/dev/null &
fi
LCPID=$!
sleep 1
rep ""; rep "===== 1. TAT TAB $TARGET ($METHOD) luc $(date +%T) ====="
rep "$(snap "truoc khi tat")"
if [ "$METHOD" = "force" ]; then
    am force-stop "$TARGET"
else
    for P in $TPIDS; do rep "$KILLER -9 $P"; $KILLER -9 "$P" 2>/dev/null; done
fi

say "[BUOC 2] Theo doi ${WATCH_SECS}s xem ai bi tat theo (neu Termux dong luon thi mo lai Termux va chay: POST=1 sh debug_kill.sh)"
rep ""; rep "===== 2. THEO DOI ====="
LAST=""; T0=$(date +%s)
while true; do
    EL=$(( $(date +%s) - T0 ))
    S=$(snap "+${EL}s")
    CMP=$(echo "$S" | cut -d'|' -f2)
    if [ "$CMP" != "$LAST" ]; then
        say "   $S"
        LAST=$CMP
    else
        rep "$S"
    fi
    [ "$EL" -ge "$WATCH_SECS" ] && break
    sleep 2
done
kill $LCPID 2>/dev/null

rep ""; rep "===== 3. LOGCAT LIEN QUAN (lmkd / am_kill / died / termux ...) ====="
grep -aE "$PATTERN" "$LOGC" 2>/dev/null | tail -n 250 >> "$OUT"
rep ""; rep "===== 4. SO SANH PID: truoc va sau ====="
rep "$(snap "luc cuoi")"

say ""
say "[BUOC 3] Mo lai tab $TARGET vao game..."
am start -n "$TARGET/com.roblox.client.ActivityProtocolLaunch" -a android.intent.action.VIEW -d "roblox://experiences/start?placeId=$PLACE_ID" > /dev/null 2>&1

cp "$OUT" "$COPY_TO" 2>/dev/null
say ""
say "===== XONG ====="
say "Bao cao: $COPY_TO"
say "Hay gui file nay cho Claude va cho biet: co tab nao khac / Termux bi dong theo khong?"
