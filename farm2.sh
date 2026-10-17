# Tab bi thu nho (thanh bong bong) -> bat len lai ngay
watch_visible() {
    local W a L N
    while true; do
        if [ ! -f "$PAUSE_FILE" ]; then
            W=$(dumpsys window windows 2>/dev/null)
            for a in $LIST_CLONE; do
                if [ -n "$(get_pid "$a")" ]; then
                    L=$(rv "launch_$a" 0); N=$(date +%s)
                    # Chi bo qua 8s dau luc vua goi launch_app de tranh xung dot
                    [ $((N - L)) -lt 8 ] && continue
                    if ! echo "$W" \vert{} grep -A40 "u0 $a/com.roblox.client.ActivityNativeMain" | grep -q "mHasSurface=true"; then
                        echo "$(date +\%T) [THU NHO]$a -> mo lai"
                        monkey -p "$a" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
                        sleep 2
                    fi
                fi
            done
        fi
        sleep 3
    done
}

trap 'kill $WATCH_PID 2>/dev/null; send_discord "" 9807270 "SCRIPT DA DUNG" "Script da dung."; exit 0' INT TERM

send_discord "" 3447003 "SCRIPT KHOI DONG" "Dang canh $TOTAL_CLONE tab (Auto reset xoa lag moi$((MAX_UPTIME/3600))h)." &
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
        echo "$(date +\%T) [PAUSE] xoa$PAUSE_FILE de chay tiep"
        sleep "$CHECK_INTERVAL"
        continue
    fi

    # Quet file heartbeat
    NEED=0
    for p in $LIST_CLONE; do
        f=$(rv "hb_$p" "")
        [ -n "$f" ] && [ -f "$f" ] || NEED=1
    done
    if [ "$NEED" = "1" ] && { [ "$LOOP" -eq 1 ] \vert{}\vert{} [ $((LOOP % 4)) -eq 0 ]; }; then
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
        LAUNCHED=$(rv "launch_$p" 0)
        SINCE=$((NOW - LAUNCHED))
        TAB_UP=$(rv "uptime_$p" "$START")
        RUN_TIME=$((NOW - TAB_UP))

        # 1. App bi tat han -> mo lai ngay lap tuc
        if [ -z "$PID" ]; then
            restart_tab "$p" "$IDX" "app bi tat" 0 0
            LINE="$LINE T$IDX:vang"
            STATUS="${STATUS}[VANG] Tab$IDX (\`$p\`): vua mo lai\\n"
            continue
        fi

        # 2. Kiem tra neu tab da treo lien tuc qua 2 tieng (7200s) ma khong bi vang/out -> tu tat bat lai xoa lag
        if [ "$RUN_TIME" -ge "$MAX_UPTIME" ]; then
            restart_tab "$p" "$IDX" "treo du $((MAX_UPTIME/3600))h lien tuc (auto reset xoa lag)" 1 1
            LINE="$LINE T$IDX:reset-2h"
            STATUS="${STATUS}[RESET 2H] Tab$IDX (\`$p\`): da tat bat lai de xoa lag\\n"
            continue
        fi

        # 3. Kiem tra heartbeat va trang thai trong game
        HBF=$(rv "hb_$p" "")
        AGE=""
        if [ -n "$HBF" ] && [ -f "$HBF" ]; then AGE=$(hb_age "$HBF"); fi

        if [ -n "$AGE" ] && [ "$AGE" -le "$STALE" ]; then
            OK_COUNT=$((OK_COUNT + 1))
            wv "consec_$p" 0
            LINE="$LINE T$IDX:ok(${AGE}s\vert{}up:$((RUN_TIME/60))m)"
            STATUS="${STATUS}[OK] Tab$IDX (\`$p\`): hb ${AGE}s \vert{} treo$((RUN_TIME/60))p | rejoin: $(rv "rj_$p" 0)\\n"
        elif [ "$LAUNCHED" -gt 0 ] && [ "$SINCE" -lt "$JOIN_GRACE" ]; then
            LINE="$LINE T$IDX:cho(${SINCE}s)"
            STATUS="${STATUS}[CHO] Tab$IDX (\`$p\`): dang vao game (${SINCE}s)\\n"
        elif [ -z "$HBF" ] && [ "$(unmapped_fresh)" -gt 0 ] && has_game_udp "$p"; then
            # Chi tam hoan restart neu tab nay THUC SU co ket noi UDP voi server game
            OK_COUNT=$((OK_COUNT + 1))
            LINE="$LINE T$IDX:online(chua-map)"
            STATUS="${STATUS}[OK] Tab$IDX (\`$p\`): dang trong game (treo $((RUN_TIME/60))p)\\n"
        elif [ -z "$HBF" ] && has_game_udp "$p"; then
            # Truong hop ban chua dung script ghi file heartbeat nhung tab van dang o trong server game
            OK_COUNT=$((OK_COUNT + 1))
            wv "consec_$p" 0
            LINE="$LINE T$IDX:online(udp\vert{}up:$((RUN_TIME/60))m)"
            STATUS="${STATUS}[OK] Tab$IDX (\`$p\`): dang farm (treo $((RUN_TIME/60))p) | rejoin: $(rv "rj_$p" 0)\\n"
        else
            if [ -z "$AGE" ]; then
                WHY="dang o ngoai sanh / mat ket noi"
            else
                WHY="heartbeat dung ${AGE}s (ket / disconnect)"
            fi
            restart_tab "$p" "$IDX" "$WHY" 1 0
            LINE="$LINE T$IDX:restart"
            STATUS="${STATUS}[RESTART] Tab$IDX (\`$p\`): $WHY\\n"
        fi
    done
    echo "$LINE"

    # Gui Discord khi co su kien
    if [ -n "$EVENTS" ]; then
        if [ "$PING" = "1" ]; then
            send_discord "<@$DISCORD_USER_ID>" 15158332 "CAN KIEM TRA" "${PINGMSG}${EVENTS}" &
        else
            send_discord "" 16776960 "THONG BAO RESTART TAB" "$EVENTS" &
        fi
        EVENTS=""; PINGMSG=""; PING=0
    fi

    if [ $((NOW - LAST_REPORT)) -ge "$REPORT_EVERY" ]; then
        LAST_REPORT=$NOW
        send_discord "" 3066993 "TRANG THAI ($OK_COUNT/$TOTAL_CLONE ONLINE)" "$STATUS" &
    fi

    sleep "$CHECK_INTERVAL"
done
