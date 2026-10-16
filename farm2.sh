watch_visible() {
    local W a IDX C
    while true; do
        W=$(dumpsys window windows 2>/dev/null)
        IDX=1
        for a in $LIST_CLONE; do
            if [ -n "$(get_pid "$a")" ]; then
                if ! echo "$W" | grep -A40 "u0 $a/com.roblox.client.ActivityNativeMain" | grep -q "mHasSurface=true"; then
                    echo "$(date +%T) [THU NHO] Tab $IDX ($a) -> mo lai"
                    C=$(cat "$STATE/min_$IDX" 2>/dev/null)
                    echo $(( ${C:-0} + 1 )) > "$STATE/min_$IDX"
                    monkey -p "$a" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
                    sleep 3
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
    cpu_total
    sys_stats

    for app in $LIST_CLONE; do
        eval "CNT=\${CNT_$INDEX:-0}"
        MINC=$(cat "$STATE/min_$INDEX" 2>/dev/null); MINC=${MINC:-0}
        PID=$(get_pid "$app")

        if [ -z "$PID" ]; then
            echo "[!] Tab $INDEX ($app) bi vang. Mo lai..."
            CNT=$((CNT + 1)); eval "CNT_$INDEX=$CNT"
            TOTAL_REJOIN=$((TOTAL_REJOIN + 1))
            eval "PT_$INDEX="
            send_discord "<@$DISCORD_USER_ID>" 15158332 "CANH BAO: TAB BI VANG" "[LOI] **Tab $INDEX** (\`$app\`): bi vang -> da mo lai (lan $CNT)" &
            STATUS_TEXT="${STATUS_TEXT}[LOI] **Tab $INDEX** (\`$app\`): vua mo lai (lan $CNT)\n"
            launch_app "$app"
            sleep $LAUNCH_WAIT
        else
            UID_APP=$(awk '/^Uid:/{print $2}' /proc/$PID/status 2>/dev/null)
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
                    am force-stop "$app"
                    sleep 3
                    launch_app "$app"
                    sleep $LAUNCH_WAIT
                    INDEX=$((INDEX + 1))
                    continue
                fi
            fi
            ONLINE_COUNT=$((ONLINE_COUNT + 1))
            APP_T=$(awk '{print $14+$15}' /proc/$PID/stat 2>/dev/null)
            APP_T=${APP_T:-0}
            eval "PV=\${PT_$INDEX:-$APP_T}"
            APP_CPU=$(( 100 * (APP_T - PV) / DTOT ))
            [ "$APP_CPU" -lt 0 ] && APP_CPU=0
            eval "PT_$INDEX=$APP_T"
            APP_RAM=$(awk '/VmRSS/{printf "%d", $2/1024}' /proc/$PID/status 2>/dev/null)
            STATUS_TEXT="${STATUS_TEXT}[OK] **Tab $INDEX** (\`$app\`): CPU ${APP_CPU}% | RAM ${APP_RAM:-0}MB | rejoin: $CNT | thu nho: $MINC\n"
        fi
        INDEX=$((INDEX + 1))
    done

    LOOP_COUNT=$((LOOP_COUNT + 1))

    WARN=""
    [ "$MEM" -lt "$MIN_RAM" ] && WARN="${WARN}RAM trong chi con ${MEM}MB\n"
    [ "$TEMP" -ge "$MAX_TEMP" ] && WARN="${WARN}May nong ${TEMP}C\n"
    [ "$BAT" -le "$BAT_LOW" ] && [ -z "$CHG" ] && WARN="${WARN}Pin yeu ${BAT}% va khong sac\n"
    if [ -n "$WARN" ] && [ $((LOOP_COUNT - LAST_ALERT)) -ge 10 ]; then
        LAST_ALERT=$LOOP_COUNT
        send_discord "<@$DISCORD_USER_ID>" 15105570 "CANH BAO HE THONG" "$WARN" &
    fi

    if [ "$ONLINE_COUNT" -eq 0 ]; then
        send_discord "<@$DISCORD_USER_ID>" 15158332 "TAT CA TAB OFFLINE" "Khong con tab nao online, dang co mo lai." &
    fi

    if [ $((LOOP_COUNT % REPORT_EVERY)) -eq 1 ]; then
        send_discord "" 3066993 "TRANG THAI ($ONLINE_COUNT/$TOTAL_CLONE ONLINE)" "$STATUS_TEXT" &
    fi

    sleep $CHECK_INTERVAL
done
