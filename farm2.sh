
# Tab bi thu nho thanh bong bong -> bat len lai.
# Dung nhieu tin hieu (cua so co surface, activity visible, state). In dong [WATCH] moi khi trang thai doi.
watch_visible() {
    local W A a L N S V ST BLK MIN KEY OLD LR
    while true; do
        if [ ! -f "$PAUSE_FILE" ]; then
            W=$(dumpsys window windows 2>/dev/null)
            A=$(dumpsys activity activities 2>/dev/null)
            for a in $LIST_CLONE; do
                [ -n "$(get_pid "$a")" ] || continue
                S=false
                if [ "$(echo "$W" | awk -v pat="u0 $a/com.roblox.client.ActivityNativeMain" '/^ *Window #/{b=(index($0,pat)>0)} b && /mHasSurface=true/{print "true"; exit}')" = "true" ]; then S=true; fi
                BLK=$(echo "$A" | grep -A16 "ActivityRecord{[^}]* u0 $a/" | head -n 17)
                V=$(echo "$BLK" | grep -oE "visible=(true|false)" | head -n 1 | cut -d= -f2)
                ST=$(echo "$BLK" | grep -oE "state=[A-Z_]+" | head -n 1 | cut -d= -f2)
                KEY="surface=$S visible=${V:-?} state=${ST:-?}"
                OLD=$(rv "wstate_$a" "")
                if [ "$KEY" != "$OLD" ]; then
                    wv "wstate_$a" "$KEY"
                    echo "$(date +%T) [WATCH] $a $KEY"
                fi
                L=$(rv "launch_$a" 0); N=$(date +%s)
                [ $((N - L)) -lt 20 ] && continue
                LR=$(rv "reopen_$a" 0)
                [ $((N - LR)) -lt 45 ] && continue
                MIN=0
                [ "$S" = "false" ] && MIN=1
                [ "$V" = "false" ] && MIN=1
                case "$ST" in STOPPED|DESTROYED|FINISHING) MIN=1 ;; esac
                if [ "$MIN" = "1" ]; then
                    wv "reopen_$a" "$N"
                    echo "$(date +%T) [THU NHO] $a -> mo lai"
                    monkey -p "$a" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
                    sleep 2
                fi
            done
        fi
        sleep 3
    done
}

trap 'kill $WATCH_PID 2>/dev/null; send_discord "" 9807270 "SCRIPT DA DUNG" "Script da dung."; exit 0' INT TERM

send_discord "" 3447003 "SCRIPT KHOI DONG" "Dang canh $TOTAL_CLONE tab bang heartbeat." &
echo "--- BAT DAU CANH TAB (tam dung: touch $PAUSE_FILE) ---"

WATCH_PID=""
if [ "$ENABLE_WATCH" = "1" ]; then
    watch_visible &
    WATCH_PID=$!
fi

LAST_SCHED=0
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

    # con tab nao chua co file heartbeat thi quet lai (moi 4 vong)
    NEED=0
    for p in $LIST_CLONE; do
        f=$(rv "hb_$p" "")
        [ -n "$f" ] && [ -f "$f" ] || NEED=1
    done
    if [ "$NEED" = "1" ] && { [ "$LOOP" -eq 1 ] || [ $((LOOP % 4)) -eq 0 ]; }; then
        discover_hb
        if [ "$AUTO_CAL" = "1" ] && [ ! -f "$STATE/cal_done" ]; then calibrate; fi
    fi

    NOW=$(date +%s)
    LINE="$(date +%T)"
    STATUS=""
    OK_COUNT=0
    IDX=0
    for p in $LIST_CLONE; do
        IDX=$((IDX + 1))
        PID=$(get_pid "$p")
        LAUNCHED=$(rv "launch_$p" "$START")
        SINCE=$((NOW - LAUNCHED))
        RUN=$((NOW - $(rv "up_$p" "$START")))

        # 1. app bi tat han -> mo lai ngay
        if [ -z "$PID" ]; then
            restart_tab "$p" "$IDX" "app bi tat" 0 0
            LINE="$LINE T$IDX:vang"
            STATUS="${STATUS}[VANG] Tab $IDX (\`$p\`): vua mo lai\\n"
            continue
        fi

        HBF=$(rv "hb_$p" "")
        AGE=""
        if [ -n "$HBF" ] && [ -f "$HBF" ]; then AGE=$(hb_age "$HBF"); fi

        if [ -n "$AGE" ] && [ "$AGE" -le "$STALE" ]; then
            # 2. dang on
            OK_COUNT=$((OK_COUNT + 1))
            wv "consec_$p" 0
            wv "stage_$p" 0
            if [ "$(rv "gap_$p" 0)" = "1" ]; then
                # vua hoi phuc sau khi mat heartbeat -> tinh lai thoi gian treo
                wv "gap_$p" 0; wv "up_$p" "$NOW"; RUN=0
            fi
            RAM=$(awk '/VmRSS/{printf "%d", $2/1024}' "/proc/$PID/status" 2>/dev/null)
            LINE="$LINE T$IDX:ok(${AGE}s)"
            STATUS="${STATUS}[OK] Tab $IDX (\`$p\`): hb ${AGE}s | RAM ${RAM:-0}MB | treo $((RUN/60))p\\n"
            # 3. treo qua MAX_RUN ma van on -> tat bat lai cho do lag (moi lan 1 tab)
            if [ "$MAX_RUN" -gt 0 ] && [ "$RUN" -ge "$MAX_RUN" ] && [ $((NOW - LAST_SCHED)) -ge "$SCHED_GAP" ]; then
                restart_tab "$p" "$IDX" "chay lien tuc $((RUN/3600))h$(((RUN%3600)/60))m -> tat bat lai de do lag" 1 1
                LAST_SCHED=$(date +%s)
                LINE="$LINE(reset-dinh-ky)"
            fi
        elif [ "$SINCE" -lt "$JOIN_GRACE" ]; then
            wv "gap_$p" 1
            LINE="$LINE T$IDX:cho(${SINCE}s)"
            STATUS="${STATUS}[CHO] Tab $IDX (\`$p\`): dang vao game (${SINCE}s)\\n"
        elif [ -z "$HBF" ] && [ "$(unmapped_fresh)" -gt 0 ]; then
            LINE="$LINE T$IDX:chua-map"
            STATUS="${STATUS}[?] Tab $IDX (\`$p\`): co heartbeat nhung chua biet file nao la cua tab nay, tam chua restart\\n"
        else
            # 4. ket sanh / mat heartbeat: lan dau day lai vao game (khong kill), van ket thi moi kill
            wv "gap_$p" 1
            if [ -z "$AGE" ]; then
                WHY="chua co heartbeat (o sanh / chua vao game)"
            else
                WHY="heartbeat dung ${AGE}s (ket / disconnect)"
            fi
            if [ "$(rv "stage_$p" 0)" = "0" ]; then
                echo "$(date +%T) [DAY LAI] Tab $IDX ($p): $WHY -> day lai vao game (chua kill)"
                launch_app "$p"
                wv "launch_$p" "$((NOW - JOIN_GRACE + SOFT_GRACE))"
                wv "stage_$p" 1
                EVENTS="${EVENTS}Tab $IDX (\`$p\`): $WHY -> day lai vao game (chua kill)\\n"
                LINE="$LINE T$IDX:day-lai"
                STATUS="${STATUS}[DAY LAI] Tab $IDX (\`$p\`): $WHY\\n"
            else
                restart_tab "$p" "$IDX" "$WHY (da day lai ma van ket)" 1 0
                LINE="$LINE T$IDX:restart"
                STATUS="${STATUS}[RESTART] Tab $IDX (\`$p\`): $WHY\\n"
            fi
        fi
    done
    echo "$LINE"

    # gui Discord: chi ping khi that su can
    if [ -n "$EVENTS" ]; then
        if [ "$PING" = "1" ]; then
            send_discord "<@$DISCORD_USER_ID>" 15158332 "CAN KIEM TRA" "${PINGMSG}${EVENTS}" &
        else
            send_discord "" 16776960 "TAB DA RESTART" "$EVENTS" &
        fi
        EVENTS=""; PINGMSG=""; PING=0
    fi

    # tat ca tab mat heartbeat lau -> ping 1 lan duy nhat cho moi dot
    if [ "$OK_COUNT" -eq 0 ]; then
        [ "$OFFLINE_SINCE" -eq 0 ] && OFFLINE_SINCE=$NOW
        if [ $((NOW - OFFLINE_SINCE)) -ge "$OFFLINE_ALERT" ] && [ "$OFFLINE_ALERTED" -eq 0 ]; then
            OFFLINE_ALERTED=1
            send_discord "<@$DISCORD_USER_ID>" 15158332 "TAT CA TAB OFFLINE" "Khong tab nao co heartbeat tu $((OFFLINE_ALERT/60)) phut. Kiem tra acc / mang / autoexec." &
        fi
    else
        OFFLINE_SINCE=0; OFFLINE_ALERTED=0
    fi

    # RAM thap: bao im lang, toi da 30 phut 1 lan
    MEM_NOW=$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)
    if [ -n "$MEM_NOW" ] && [ "$MEM_NOW" -lt "$MIN_RAM" ] && [ $((NOW - LAST_RAM_WARN)) -ge 1800 ]; then
        LAST_RAM_WARN=$NOW
        send_discord "" 15105570 "RAM THAP" "RAM trong con ${MEM_NOW}MB" &
    fi

    # bao cao dinh ky kem anh chup (khong ping)
    if [ $((NOW - LAST_REPORT)) -ge "$REPORT_EVERY" ]; then
        LAST_REPORT=$NOW
        send_discord "" 3066993 "TRANG THAI ($OK_COUNT/$TOTAL_CLONE ONLINE)" "$STATUS" &
        send_screenshot &
    fi

    sleep "$CHECK_INTERVAL"
done
