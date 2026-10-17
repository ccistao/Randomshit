# Tab bi thu nho (mat bong bong) -> bat len lai. Bo qua tab vua moi mo < 20s de khong lam hong luc dang vao game.
watch_visible() {
    local W a L N
    while true; do
        if [ ! -f "$PAUSE_FILE" ]; then
            W=$(dumpsys window windows 2>/dev/null)
            for a in $LIST_CLONE; do
                if [ -n "$(get_pid "$a")" ]; then
                    L=$(rv "launch_$a" 0); N=$(date +%s)
                    [ $((N - L)) -lt 20 ] && continue
                    if ! echo "$W" | grep -A40 "u0 $a/com.roblox.client.ActivityNativeMain" | grep -q "mHasSurface=true"; then
                        echo "$(date +%T) [THU NHO] $a -> mo lai"
                        monkey -p "$a" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
                        sleep 3
                    fi
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

while true; do
    NOW=$(date +%s)
    LOOP=$((LOOP + 1))

    if [ -f "$PAUSE_FILE" ]; then
        echo "$(date +%T) [PAUSE] xoa $PAUSE_FILE de chay tiep"
        sleep "$CHECK_INTERVAL"
        continue
    fi

    # con tab nao chua co file heartbeat thi quet lai (moi ~1 phut)
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

        if [ -z "$PID" ]; then
            restart_tab "$p" "$IDX" "app bi tat" 0
            LINE="$LINE T$IDX:vang"
            STATUS="${STATUS}[VANG] Tab $IDX (\`$p\`): vua mo lai\\n"
            continue
        fi

        HBF=$(rv "hb_$p" "")
        AGE=""
        if [ -n "$HBF" ] && [ -f "$HBF" ]; then AGE=$(hb_age "$HBF"); fi

        if [ -n "$AGE" ] && [ "$AGE" -le "$STALE" ]; then
            OK_COUNT=$((OK_COUNT + 1))
            wv "consec_$p" 0
            LINE="$LINE T$IDX:ok(${AGE}s)"
            STATUS="${STATUS}[OK] Tab $IDX (\`$p\`): heartbeat ${AGE}s truoc | rejoin: $(rv "rj_$p" 0)\\n"
        elif [ "$SINCE" -lt "$JOIN_GRACE" ]; then
            LINE="$LINE T$IDX:cho(${SINCE}s)"
            STATUS="${STATUS}[CHO] Tab $IDX (\`$p\`): dang vao game (${SINCE}s)\\n"
        elif [ -z "$HBF" ] && [ "$(unmapped_fresh)" -gt 0 ]; then
            LINE="$LINE T$IDX:chua-map"
            STATUS="${STATUS}[?] Tab $IDX (\`$p\`): co heartbeat nhung chua biet file nao la cua tab nay, tam chua restart\n"
        else
            if [ -z "$AGE" ]; then
                WHY="chua co heartbeat (o sanh / chua vao game)"
            else
                WHY="heartbeat dung ${AGE}s (ket / disconnect)"
            fi
            restart_tab "$p" "$IDX" "$WHY" 1
            LINE="$LINE T$IDX:restart"
            STATUS="${STATUS}[RESTART] Tab $IDX (\`$p\`): $WHY\\n"
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

    if [ $((NOW - LAST_REPORT)) -ge "$REPORT_EVERY" ]; then
        LAST_REPORT=$NOW
        send_discord "" 3066993 "TRANG THAI ($OK_COUNT/$TOTAL_CLONE ONLINE)" "$STATUS" &
    fi

    sleep "$CHECK_INTERVAL"
done
