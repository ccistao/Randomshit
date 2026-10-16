#!/system/bin/sh
PLACE_ID="2753915549"
DISCORD_USER_ID="982107241371013132"
WEBHOOK_URL="https://discord.com/api/webhooks/1560579280906489906/jK4Gj1NoNmqY-3x_7nOUHg0UQEXPgIgNqnN_8xG4u8LNqniyztRDE1DVXjl2a5k5EKSs"
FILTER="roblox|delta|aya"
CHECK_INTERVAL=30
REPORT_EVERY=10
LAUNCH_WAIT=25
NET_RECHECK=15
MIN_RAM=300
STATE="/data/local/tmp/farmstate"
INPUT_FILE="/data/local/tmp/farm_input"

LIST_CLONE=$(pm list packages -3 | cut -d: -f2 | grep -iE "$FILTER")
if [ -z "$LIST_CLONE" ]; then
    echo "Không tìm thấy clone nào!"
    exit 1
fi

TOTAL_CLONE=$(echo "$LIST_CLONE" | wc -l)
echo "Đã nhận diện $TOTAL_CLONE tab:"
echo "$LIST_CLONE"

mkdir -p "$STATE"
rm -f "$STATE"/min_*
echo "continue" > "$INPUT_FILE"

START=$(date +%s)
PREV_TOT=""
PREV_IDLE=0
CPU=0
DTOT=1
TOTAL_REJOIN=0
LAST_ALERT=-100
MEM=0; UPTXT="0h0m"

sys_stats() {
    local U
    # Fix loi doc RAM tren UgPhone
    MEM=$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo)
    [ -z "$MEM" ] && MEM=$(awk '/MemFree/{printf "%d", $2/1024}' /proc/meminfo)
    MEM=${MEM:-0}
    U=$(($(date +%s) - START ))
    UPTXT="$((U/3600))h$(((U%3600)/60))m"
}

send_discord() {
    local TIME_NOW JSON FIELDS RESP CODE
    sys_stats
    TIME_NOW=$(date +"%H:%M:%S")
    FIELDS="[{\"name\":\"CPU\",\"value\":\"${CPU:-0}%\",\"inline\":true},{\"name\":\"RAM Trống\",\"value\":\"${MEM}MB\",\"inline\":true},{\"name\":\"Uptime\",\"value\":\"$UPTXT\",\"inline\":true},{\"name\":\"Tổng Rejoin\",\"value\":\"$TOTAL_REJOIN\",\"inline\":true}]"
    JSON="{\"content\":\"$1\",\"embeds\":[{\"title\":\"$3\",\"description\":\"$4\",\"color\":$2,\"fields\":$FIELDS,\"footer\":{\"text\":\"$TIME_NOW\"}}]}"
    RESP=$(curl -s -4 --connect-timeout 5 -m 15 --retry 2 \
        -H "Content-Type: application/json" -X POST -d "$JSON" \
        -w "\n%{http_code}" "$WEBHOOK_URL" 2>&1)
    CODE=$(echo "$RESP" | tail -n 1 | tr -d '\r')
    
    # Fix loi nhan dien sai ma 204 cua Discord
    if echo "$CODE" | grep -qE "200|204"; then
        echo "[Discord] Gui OK luc $TIME_NOW"
    else
        echo "[Discord] LOI HTTP $CODE"
    fi
}

send_screenshot() {
    local FILE="/data/local/tmp/screen.png"
    screencap -p "$FILE"
    curl -s -X POST "$WEBHOOK_URL" \
        -F "payload_json={\"embeds\":[{\"title\":\"📸 ẢNH CHỤP MÀN HÌNH\",\"color\":3066993,\"image\":{\"url\":\"attachment://screen.png\"}}]}" \
        -F "file=@$FILE" > /dev/null 2>&1
    rm -f "$FILE"
    echo "[Discord] Đã gửi ảnh chụp màn hình."
}

launch_app() {
    am start -a android.intent.action.VIEW -p "$1" -d "roblox://experiences/start?placeId=$PLACE_ID" > /dev/null 2>&1
}

get_pid() {
    local P
    P=$(pidof "$1" 2>/dev/null | awk '{print $1}')
    if [ -z "$P" ]; then
        P=$(pgrep -f "^$1" 2>/dev/null | head -n 1)
    fi
    echo "$P"
}

has_net() {
    awk -v u="$1" 'NR>1 && $8==u {f=1} END{exit !f}' /proc/net/udp /proc/net/udp6 2>/dev/null
}

cpu_total() {
    read -r _ u n s i io irq sirq st _ < /proc/stat
    TOT=$((u+n+s+i+io+irq+sirq+st)); IDLE=$((i+io))
    if [ -n "$PREV_TOT" ]; then
        DTOT=$((TOT - PREV_TOT))
        [ "$DTOT" -le 0 ] && DTOT=1
        CPU=$(( 100 * (DTOT - (IDLE - PREV_IDLE)) / DTOT ))
    else
        CPU=0; DTOT=1
    fi
    PREV_TOT=$TOT; PREV_IDLE=$IDLE
}

get_cmd() {
    cat "$INPUT_FILE" 2>/dev/null | tr -d '\r' | head -n 1
}

watch_visible() {
    local W a IDX C CMD
    while true; do
        CMD=$(get_cmd)
        if [ "$CMD" = "stop" ] \vert{}\vert{} [ "$CMD" = "chup" ]; then sleep 2; continue; fi

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

(
    while read -r user_cmd; do
        user_cmd=$(echo "$user_cmd" | tr -d '\r')
        if [ "$user_cmd" = "stop" ] || [ "$user_cmd" = "continue" ] \vert{}\vert{} [ "$user_cmd" = "chup" ]; then
            echo "$user_cmd" > "$INPUT_FILE"
        fi
    done
) &
INPUT_PID=$!

trap 'kill $WATCH_PID$INPUT_PID 2>/dev/null; send_discord "" 9807270 "SCRIPT ĐÃ DỪNG" "Người dùng hoặc hệ thống đã tắt script."; exit 0' INT TERM

send_discord "" 3447003 "🚀 BẮT ĐẦU CHẠY SCRIPT" "Đang canh gác $TOTAL_CLONE tab." &
echo "--- BẮT ĐẦU CANH TAB ---"
echo "=> Gõ 'stop' và nhấn Enter để TẠM DỪNG."
echo "=> Gõ 'continue' và nhấn Enter để CHẠY TIẾP."
echo "=> Gõ 'chup' và nhấn Enter để CHỤP MÀN HÌNH GỬI DISCORD."

watch_visible &
WATCH_PID=$!

LOOP_COUNT=0

while true; do
    CMD=$(get_cmd)
    
    if [ "$CMD" = "chup" ]; then
        echo "📸 Đang chụp màn hình gửi lên Discord..."
        send_screenshot &
        echo "continue" > "$INPUT_FILE"
    fi

    if [ "$CMD" = "stop" ]; then
        echo "====== SCRIPT ĐANG TẠM DỪNG ======"
        echo "=> Gõ 'continue' (rồi nhấn Enter) để chạy tiếp!"
        while [ "$(get_cmd)" = "stop" ]; do
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
            
            send_discord "" 15158332 "THÔNG BÁO: TAB BỊ VĂNG" "[LOI] **Tab $INDEX** (\`$app\`): Bị văng -> Đã mở lại (Lần $CNT)" &
            STATUS_TEXT="${STATUS_TEXT}🔴 **Tab $INDEX** (\`$app\`): Vừa mở lại (Lần $CNT)\n"
            launch_app "$app"
            
            for i in $(seq 1$LAUNCH_WAIT); do
                [ "$(get_cmd)" = "stop" ] && break
                sleep 1
            done
        else
            UID_APP=$(awk '/^Uid:/{print $2}' /proc/$PID/status 2>/dev/null)
            if [ -n "$UID_APP" ] && ! has_net "$UID_APP"; then
                echo "[?] Tab $INDEX ($app) o ngoai sanh hoac mat mang. Dang day vao game..."
                launch_app "$app"
                
                for i in $(seq 1$NET_RECHECK); do
                    [ "$(get_cmd)" = "stop" ] && break
                    sleep 1
                done

                if ! has_net "$UID_APP"; then
                    echo "[!] Xac nhan Tab $INDEX ket cung. Restart..."
                    CNT=$((CNT + 1)); eval "CNT_$INDEX=$CNT"
                    TOTAL_REJOIN=$((TOTAL_REJOIN + 1))
                    
                    send_discord "" 16776960 "THÔNG BÁO: TAB KẸT SẢNH/LỖI" "[KET] **Tab $INDEX** (\`$app\`): Kẹt 279/Sảnh -> Đã restart (Lần $CNT)" &
                    STATUS_TEXT="${STATUS_TEXT}🟡 **Tab $INDEX** (\`$app\`): Vừa restart (Lần $CNT)\n"
                    am force-stop "$app"
                    sleep 3
                    launch_app "$app"
                    
                    for i in $(seq 1$LAUNCH_WAIT); do
                        [ "$(get_cmd)" = "stop" ] && break
                        sleep 1
                    done
                    INDEX=$((INDEX + 1))
                    continue
                fi
            fi
            
            ONLINE_COUNT=$((ONLINE_COUNT + 1))
            APP_T=$(awk '{print $14+$15}' /proc/$PID/stat 2>/dev/null)
            APP_T=${APP_T:-0}
            eval "PV=\${PT_$INDEX:-0}"
            APP_CPU=$(( 100 * (APP_T - PV) / DTOT ))
            [ "$APP_CPU" -lt 0 ] && APP_CPU=0
            eval "PT_$INDEX=$APP_T"
            APP_RAM=$(awk '/VmRSS/{printf "%d", $2/1024}' /proc/$PID/status 2>/dev/null)
            APP_RAM=${APP_RAM:-0}
            STATUS_TEXT="${STATUS_TEXT}🟢 **Tab $INDEX** (\`$app\`): CPU ${APP_CPU}% | RAM ${APP_RAM}MB \vert{} Rejoin:$CNT | Thu nhỏ: $MINC\n"
        fi
        INDEX=$((INDEX + 1))
    done

    LOOP_COUNT=$((LOOP_COUNT + 1))

    WARN=""
    [ "$MEM" -lt "$MIN_RAM" ] && WARN="${WARN}RAM trống chỉ còn ${MEM}MB. Máy ảo có nguy cơ văng toàn bộ tab!\n"
    if [ -n "$WARN" ] && [ $((LOOP_COUNT - LAST_ALERT)) -ge 10 ]; then
        LAST_ALERT=$LOOP_COUNT
        send_discord "<@$DISCORD_USER_ID>" 15105570 "⚠️ CẢNH BÁO HỆ THỐNG" "$WARN" &
    fi

    if [ "$ONLINE_COUNT" -eq 0 ]; then
        send_discord "<@$DISCORD_USER_ID>" 15158332 "🚨 TẤT CẢ TAB ĐỀU OFFLINE" "Không còn tab nào đang farm, hệ thống đang cố kéo lại." &
    fi

    if [ $((LOOP_COUNT % REPORT_EVERY)) -eq 1 ]; then
        send_discord "" 3066993 "📊 TRẠNG THÁI ($ONLINE_COUNT/$TOTAL_CLONE ONLINE)" "$STATUS_TEXT" &
        send_screenshot &
    fi

    for i in $(seq 1$CHECK_INTERVAL); do
        CMD=$(get_cmd)
        if [ "$CMD" = "stop" ] \vert{}\vert{} [ "$CMD" = "chup" ]; then
            break
        fi
        sleep 1
    done
done
