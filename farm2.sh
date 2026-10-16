# Tao file doc lenh dieu khien tu ban phim
INPUT_FILE="/data/local/tmp/farm_input"
echo "continue" > "$INPUT_FILE"

# Tien trinh chay ngam doc lenh ban phim Termux
(
    while read -r user_cmd; do
        if [ "$user_cmd" = "stop" ] \vert{}\vert{} [ "$user_cmd" = "continue" ]; then
            echo "$user_cmd" > "$INPUT_FILE"
        fi
    done
) &
INPUT_PID=$!

watch_visible() {
    local W a IDX C CMD
    while true; do
        # Kiem tra lenh dung tu ban phim
        CMD=$(cat "$INPUT_FILE" 2>/dev/null)
        if [ "$CMD" = "stop" ]; then sleep 2; continue; fi

        W=$(dumpsys window windows 2>/dev/null)
        IDX=1
        for a in $LIST_CLONE; do
            if [ -n "$(get_pid "$a")" ]; then
                if ! echo "$W" \vert{} grep -A40 "u0 $a/com.roblox.client.ActivityNativeMain" | grep -q "mHasSurface=true"; then
                    echo "$(date +%T) [THU NHO] Tab $IDX ($a) -> mo lai"
                    C=$(cat "$STATE/min_$IDX" 2>/dev/null)
                    echo $((${C:-0} + 1 )) > "$STATE/min_$IDX"
                    monkey -p "$a" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
                    sleep 3
                fi
            fi
            IDX=$((IDX + 1))
        done
        sleep 3
    done
}

# Them INPUT_PID vao danh sach tu dong kill khi tat script
trap 'kill $WATCH_PID $INPUT_PID 2>/dev/null; send_discord "<@$DISCORD_USER_ID>" 9807270 "SCRIPT DA DUNG" "Script bi dung."; exit 0' INT TERM

send_discord "" 3447003 "SCRIPT KHOI DONG" "Dang canh $TOTAL_CLONE tab." &
echo "--- BAT DAU CANH TAB ---"
echo "=> Gõ 'stop' và nhấn Enter để TẠM DỪNG."
echo "=> Gõ 'continue' và nhấn Enter để CHẠY TIẾP."

watch_visible &
WATCH_PID=$!

LOOP_COUNT=0

while true; do
    # Kiem tra lenh dung o dau moi vong lap
    CMD=$(cat "$INPUT_FILE" 2>/dev/null)
    if [ "$CMD" = "stop" ]; then
        echo "====== SCRIPT ĐANG TẠM DỪNG ======"
        echo "=> Gõ 'continue' (rồi nhấn Enter) để chạy tiếp!"
        while [ "$(cat "$INPUT_FILE" 2>/dev/null)" = "stop" ]; do
            sleep 2
        done
        echo "====== SCRIPT ĐÃ TIẾP TỤC ======"
    fi

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
            
            # Ngat sleep ngay lap tuc neu co lenh stop
            for i in $(seq 1$LAUNCH_WAIT); do
                [ "$(cat "$INPUT_FILE" 2>/dev/null)" = "stop" ] && break
                sleep 1
            done
        else
            UID_APP=$(awk '/^Uid:/{print $2}' /proc/$PID/status 2>/dev/null)
            if [ -n "$UID_APP" ] && ! has_net "$UID_APP"; then
                echo "[?] Tab $INDEX ($app) o ngoai sanh hoac mat mang. Dang day vao game..."
                # Truoc khi force-stop, thu ban lenh teleport vao thang game de cuu tab bi ket o lobby
                launch_app "$app"
                
                for i in $(seq 1$NET_RECHECK); do
                    [ "$(cat "$INPUT_FILE" 2>/dev/null)" = "stop" ] && break
                    sleep 1
                done

                # Kiem tra lai xem da vo duoc server chua
                if ! has_net "$UID_APP"; then
                    echo "[!] Xac nhan Tab $INDEX ket cung. Restart..."
                    CNT=$((CNT + 1)); eval "CNT_$INDEX=$CNT"
                    TOTAL_REJOIN=$((TOTAL_REJOIN + 1))
                    eval "PT_$INDEX="
                    send_discord "<@$DISCORD_USER_ID>" 16776960 "CANH BAO: TAB KET LOI" "[KET] **Tab $INDEX** (\`$app\`): ket 279/Disconnect -> da restart (lan $CNT)" &
                    STATUS_TEXT="${STATUS_TEXT}[KET] **Tab $INDEX** (\`$app\`): vua restart (lan $CNT)\n"
                    am force-stop "$app"
                    sleep 3
                    launch_app "$app"
                    
                    for i in $(seq 1$LAUNCH_WAIT); do
                        [ "$(cat "$INPUT_FILE" 2>/dev/null)" = "stop" ] && break
                        sleep 1
                    done
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
            STATUS_TEXT="${STATUS_TEXT}[OK] **Tab $INDEX** (\`$app\`): CPU ${APP_CPU}\% \vert{} RAM${APP_RAM:-0}MB | rejoin: $CNT \vert{} thu nho:$MINC\n"
        fi
        INDEX=$((INDEX + 1))
    done

    LOOP_COUNT=$((LOOP_COUNT + 1))

    WARN=""
    [ "$MEM" -lt "$MIN_RAM" ] && WARN="${WARN}RAM trong chi con${MEM}MB\n"
    [ "$TEMP" -ge "$MAX_TEMP" ] && WARN="${WARN}May nong${TEMP}C\n"
    [ "$BAT" -le "$BAT_LOW" ] && [ -z "$CHG" ] && WARN="${WARN}Pin yeu${BAT}% va khong sac\n"
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

    # Thay the sleep $CHECK_INTERVAL bang vong lap de nhan dien lenh stop tuc thi
    for i in $(seq 1$CHECK_INTERVAL); do
        [ "$(cat "$INPUT_FILE" 2>/dev/null)" = "stop" ] && break
        sleep 1
    done
done
