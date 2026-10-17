watch_visible() {
    local W a IDX C
    while true; do
        W=$(dumpsys window windows 2>/dev/null)
        IDX=1
        for a in $LIST_CLONE; do
            if [ -n "$(get_pid "$a")" ]; then
                # Bo loc grep da test work 100% tren may ao
                if ! echo "$W" \vert{} grep -A35 "$a/" | grep -q "mHasSurface=true"; then
                    echo "$(date +%T) [THU NHO] Tab $IDX ($a) -> mo lai"
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

send_discord "" 3447003 "SCRIPT KHOI DONG" "Dang canh $TOTAL_CLONE tab." &
echo "--- BAT DAU CANH TAB ---"

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

        # 1. Kiem tra tab bi vang hoac chua mo
        if [ -z "$PID" ]; then
            echo "[!] Tab $INDEX ($app) bi vang. Mo lai..."
            CNT=$((CNT + 1)); eval "CNT_$INDEX=$CNT"
            TOTAL_REJOIN=$((TOTAL_REJOIN + 1))
            eval "PT_$INDEX="
            echo "$(date +%s)" > "$STATE/up_$INDEX"
            send_discord "<@$DISCORD_USER_ID>" 15158332 "CANH BAO: TAB BI VANG" "[LOI] **Tab $INDEX** (\`$app\`): bi vang -> da mo lai (lan $CNT)" &
            STATUS_TEXT="${STATUS_TEXT}[LOI] **Tab $INDEX** (\`$app\`): vua mo lai (lan $CNT)\n"
            launch_app "$app"
            sleep $LAUNCH_WAIT
            INDEX=$((INDEX + 1))
            continue
        fi

        # 2. Tu dong kill va mo lai sau 2 tieng lien tuc de xoa lag
        if [ "$RUN_TIME" -ge "$MAX_UPTIME" ]; then
            echo "[2H RESET] Tab $INDEX ($app) da treo$RUN_TIME giay -> restart xoa lag"
            send_discord "" 3447003 "🔄 AUTO RESET 2H" "🔵 **Tab $INDEX** (\`$app\`): Da treo $((RUN_TIME/60))p lien tuc -> restart xoa lag" &
            STATUS_TEXT="${STATUS_TEXT}[RESET 2H] **Tab $INDEX** (\`$app\`): vua restart xoa lag\n"
            kill_tab "$app"
            sleep 2
            launch_app "$app"
            echo "$(date +%s)" > "$STATE/up_$INDEX"
            sleep $LAUNCH_WAIT
            INDEX=$((INDEX + 1))
            continue
        fi

        # 3. Kiem tra mat mang / loi 279
        UID_APP=$(awk '/^Uid:/{print $2}' "/proc/$PID/status" 2>/dev/null)
        if [ -n "$UID_APP" ] && ! has_net "$UID_APP"; then
            echo "[?] Nghi Tab $INDEX ($app) mat ket noi. Doi ${NET_RECHECK}s..."
            sleep $NET_RECHECK
            if ! has_net "$UID_APP"; then
                echo "[!] Xac nhan Tab $INDEX ket. Restart..."
                CNT=$((CNT + 1)); eval "CNT_$INDEX=$CNT"
                TOTAL_REJOIN=$((TOTAL_REJOIN + 1))
                eval "PT_$INDEX="
                send_discord "<@$DISCORD_USER_ID>" 16776960 "CANH BAO: TAB KET LOI" "[KET] **Tab $INDEX** (\`$app\`): ket 279/Disconnect -> da restart (lan $CNT)" &
                STATUS_TEXT="${STATUS_TEXT}[KET] **Tab $INDEX** (\`$app\`): vua restart (lan $CNT)\n"
                kill_tab "$app"
                echo "$(date +%s)" > "$STATE/up_$INDEX"
                sleep 2
                launch_app "$app"
                sleep $LAUNCH_WAIT
                INDEX=$((INDEX + 1))
                continue
            fi
        fi

        ONLINE_COUNT=$((ONLINE_COUNT + 1))
        APP_T=$(awk '{print $14+$15}' "/proc/$PID/stat" 2>/dev/null)
        APP_T=${APP_T:-0}
        eval "PV=\${PT_$INDEX:-$APP_T}"
        APP_CPU=$(( 100 * (APP_T - PV) / DTOT ))
        [ "$APP_CPU" -lt 0 ] && APP_CPU=0
        eval "PT_$INDEX=$APP_T"
        APP_RAM=$(awk '/VmRSS/{printf "%d", $2/1024}' "/proc/$PID/status" 2>/dev/null)
        STATUS_TEXT="${STATUS_TEXT}[OK] **Tab $INDEX** (\`$app\`): CPU ${APP_CPU}% | RAM ${APP_RAM:-0}MB \vert{} treo$((RUN_TIME/60))p | rejoin: $CNT \vert{} thu nho:$MINC\n"
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

    # Bao cao dinh ky moi 1 gio kem anh chup man hinh
    if [ $((NOW - LAST_REPORT)) -ge "$REPORT_EVERY" ]; then
        LAST_REPORT=$NOW
        send_discord "" 3066993 "TRANG THAI ($ONLINE_COUNT/$TOTAL_CLONE ONLINE)" "$STATUS_TEXT" &
        send_screenshot &
    fi

    sleep $CHECK_INTERVAL
done
