# Luong canh bong bong thu nho: chay lien tuc moi 3 giay
watch_visible() {
    local W a IDX C PID
    while true; do
        W=$(dumpsys window windows 2>/dev/null)
        IDX=1
        for a in $LIST_CLONE; do
            PID=$(get_pid "$a")
            if [ -n "$PID" ]; then
                if ! echo "$W" \vert{} grep -A35 "$a/" | grep -q "mHasSurface=true"; then
                    echo "$(date +%T) [THU NHO] Tab $IDX ($a) -> bung lai bong bong"
                    C=$(cat "$STATE/min_$IDX" 2>/dev/null)
                    echo $((${C:-0} + 1 )) > "$STATE/min_$IDX"
                    monkey -p "$a" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
                    sleep 2
                fi
            fi
            IDX=$((IDX + 1))
        done
        sleep 3
    done
}

trap 'kill $WATCH_PID 2>/dev/null; send_discord "<@$DISCORD_USER_ID>" 9807270 "SCRIPT DA DUNG" "Script bi dung."; exit 0' INT TERM

send_discord "" 3447003 "SCRIPT KHOI DONG" "Dang canh $TOTAL_CLONE tab bang Heartbeat Lua." &
echo "--- BAT DAU CANH TAB (HEARTBEAT LUA) ---"

watch_visible &
WATCH_PID=$!

LOOP_COUNT=0

while true; do
    ONLINE_COUNT=0
    STATUS_TEXT=""
    INDEX=1
    NOW=$(date +%s)
    cpu_total
    sys_stats

    for app in $LIST_CLONE; do
        eval "CNT=\${CNT_$INDEX:-0}"
        MINC=$(cat "$STATE/min_$INDEX" 2>/dev/null); MINC=${MINC:-0}
        PID=$(get_pid "$app")
        TAB_START=$(cat "$STATE/up_$INDEX" 2>/dev/null); TAB_START=${TAB_START:-$START}
        RUN_TIME=$((NOW - TAB_START))
        LAUNCHED=$(rv "launch_$app" 0)
        SINCE=$((NOW - LAUNCHED))

        # 1. Tab bi tat han -> Mo lai
        if [ -z "$PID" ]; then
            echo "[!] Tab $INDEX ($app) bi tat. Mo lai..."
            CNT=$((CNT + 1)); eval "CNT_$INDEX=$CNT"
            TOTAL_REJOIN=$((TOTAL_REJOIN + 1))
            echo "$NOW" > "$STATE/up_$INDEX"
            send_discord "<@$DISCORD_USER_ID>" 15158332 "CANH BAO: TAB BI VANG" "[LOI] **Tab $INDEX** (\`$app\`): bi vang -> da mo lai (lan $CNT)" &
            STATUS_TEXT="${STATUS_TEXT}[LOI] **Tab $INDEX** (\`$app\`): mo lai tu dau\n"
            launch_app "$app"
            sleep $LAUNCH_WAIT
            INDEX=$((INDEX + 1))
            continue
        fi

        # 2. Tu reset sau 2h xoa lag bang kill -9
        if [ "$RUN_TIME" -ge "$MAX_UPTIME" ]; then
            echo "[2H RESET] Tab $INDEX ($app) da treo$RUN_TIME giay -> kill restart xoa lag"
            send_discord "" 3447003 "🔄 AUTO RESET 2H" "🔵 **Tab $INDEX** (\`$app\`): Treo 2h lien tuc -> restart xoa lag" &
            STATUS_TEXT="${STATUS_TEXT}[RESET 2H] **Tab $INDEX** (\`$app\`): da restart 2h\n"
            kill_tab "$app"
            sleep 2
            launch_app "$app"
            echo "$NOW" > "$STATE/up_$INDEX"
            sleep $LAUNCH_WAIT
            INDEX=$((INDEX + 1))
            continue
        fi

        # 3. CHECK HEARTBEAT TU LUA (Kiem tra co dang farm hay ket Menu sảnh)
        HBF=$(find_hb "$app")
        AGE=999
        if [ -n "$HBF" ] && [ -f "$HBF" ]; then AGE=$(hb_age "$HBF"); fi

        if [ "$AGE" -le "$STALE" ]; then
            # Lua gui Heartbeat deu dan duoi 45s -> Dang farm ngon lanh
            ONLINE_COUNT=$((ONLINE_COUNT + 1))
            APP_T=$(awk '{print $14+$15}' "/proc/$PID/stat" 2>/dev/null); APP_T=${APP_T:-0}
            eval "PV=\${PT_$INDEX:-$APP_T}"
            APP_CPU=$(( 100 * (APP_T - PV) / DTOT )); [ "$APP_CPU" -lt 0 ] && APP_CPU=0
            eval "PT_$INDEX=$APP_T"
            APP_RAM=$(awk '/VmRSS/{printf "%d", $2/1024}' "/proc/$PID/status" 2>/dev/null)
            STATUS_TEXT="${STATUS_TEXT}[OK] **Tab $INDEX** (\`$app\`): hb ${AGE}s \vert{} CPU${APP_CPU}% | RAM ${APP_RAM:-0}MB \vert{} treo$((RUN_TIME/60))p\n"
        elif [ "$LAUNCHED" -gt 0 ] && [ "$SINCE" -lt "$JOIN_GRACE" ]; then
            # Vua moi mo app duoi 45s -> Cho game load
            echo "[CHO] Tab $INDEX ($app): dang load vao game (${SINCE}s)..."
        else
            # QUA 45s KHONG CO HEARTBEAT -> KET MENU SANH HOAC KET LOI 279
            echo "[KET SANH] Tab $INDEX ($app) khong co Heartbeat (${AGE}s). Dang day vao Blox Fruits..."
            # Nhip 1: Ban lenh day tu Menu vao game
            am start -a android.intent.action.VIEW -p "$app" -d "roblox://experiences/start?placeId=$PLACE_ID" > /dev/null 2>&1
            sleep 10
            
            # Kiem tra lai, neu van kẹt ngoai Menu thi kill -9 mo lai tu dau
            HBF=$(find_hb "$app")
            NEW_AGE=999
            [ -n "$HBF" ] && NEW_AGE=$(hb_age "$HBF")
            if [ "$NEW_AGE" -gt "$STALE" ]; then
                echo "[!] Tab $INDEX kẹt cứng ngoài sảnh. Kill -9 và mở lại..."
                CNT=$((CNT + 1)); eval "CNT_$INDEX=$CNT"
                TOTAL_REJOIN=$((TOTAL_REJOIN + 1))
                send_discord "<@$DISCORD_USER_ID>" 16776960 "CANH BAO: KET SANH" "[KET] **Tab $INDEX** (\`$app\`): kẹt sảnh/mất heartbeat -> restart (lan $CNT)" &
                STATUS_TEXT="${STATUS_TEXT}[KET] **Tab $INDEX** (\`$app\`): ket sanh -> restart\n"
                kill_tab "$app"
                echo "$NOW" > "$STATE/up_$INDEX"
                sleep 2
                launch_app "$app"
                sleep $LAUNCH_WAIT
                INDEX=$((INDEX + 1))
                continue
            fi
        fi

        INDEX=$((INDEX + 1))
    done

    LOOP_COUNT=$((LOOP_COUNT + 1))

    WARN=""
    [ "$MEM" -lt "$MIN_RAM" ] && WARN="${WARN}RAM trong chi con${MEM}MB\n"
    if [ -n "$WARN" ] && [ $((LOOP_COUNT - LAST_ALERT)) -ge 10 ]; then
        LAST_ALERT=$LOOP_COUNT
        send_discord "<@$DISCORD_USER_ID>" 15105570 "CANH BAO HE THONG" "$WARN" &
    fi

    if [ "$ONLINE_COUNT" -eq 0 ]; then
        send_discord "<@$DISCORD_USER_ID>" 15158332 "TAT CA TAB OFFLINE" "Khong con tab nao online, dang co mo lai." &
    fi

    if [ $((NOW - LAST_REPORT)) -ge "$REPORT_EVERY" ]; then
        LAST_REPORT=$NOW
        send_discord "" 3066993 "TRANG THAI ($ONLINE_COUNT/$TOTAL_CLONE ONLINE)" "$STATUS_TEXT" &
        send_screenshot &
    fi

    sleep $CHECK_INTERVAL
done
