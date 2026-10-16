#!/system/bin/sh
PLACE_ID="2753915549"
DISCORD_USER_ID="982107241371013132"
WEBHOOK_URL="https://discord.com/api/webhooks/1560579280906489906/jK4Gj1NoNmqY-3x_7nOUHg0UQEXPgIgNqnN_8xG4u8LNqniyztRDE1DVXjl2a5k5EKSs"
FILTER="roblox|delta|aya"

CHECK_INTERVAL=20
LAUNCH_WAIT=18
NET_RECHECK=15
REPORT_INTERVAL=3600
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

get_cmd() {
    cat "$INPUT_FILE" 2>/dev/null | tr -cd 'a-z'
}

wait_delay() {
    local t=${1:-10}
    local c=0
    while [ "$c" -lt "$t" ]; do
        if [ "$(get_cmd)" = "stop" ]; then
            break
        fi
        sleep 1
        c=$((c + 1))
    done
}

sys_stats() {
    local U
    MEM=$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)
    [ -z "$MEM" ] && MEM=$(awk '/MemFree/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)
    MEM=$(echo "$MEM" | tr -cd '0-9')
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
    CODE=$(echo "$RESP" | tail -n 1 | tr -cd '0-9')
    
    case "$CODE" in
        *200*|*204*) echo "[Discord] Gửi OK lúc $TIME_NOW" ;;
        *) echo "[Discord] LỖI HTTP $CODE" ;;
    esac
}

send_screenshot() {
    local FILE="/data/local/tmp/screen.png"
    screencap -p "$FILE"
    curl -s -X POST "$WEBHOOK_URL" \
        -F "payload_json={\"embeds\":[{\"title\":\"📸 ẢNH CHỤP MÀN HÌNH 1 GIỜ/LẦN\",\"color\":3066993,\"image\":{\"url\":\"attachment://screen.png\"}}]}" \
        -F "file=@$FILE" > /dev/null 2>&1
    rm -f "$FILE"
    echo "[Discord] Đã tự động gửi ảnh chụp màn hình."
}

launch_app() {
    local OUT
    OUT=$(am start -n "$1/com.roblox.client.ActivityProtocolLaunch" -a android.intent.action.VIEW -d "roblox://experiences/start?placeId=$PLACE_ID" 2>&1)
    case "$OUT" in
        *Error*|*Exception*|*unable*)
            am start -a android.intent.action.VIEW -p "$1" -d "roblox://experiences/start?placeId=$PLACE_ID" > /dev/null 2>&1
            ;;
    esac
}

get_pid() {
    local P
    P=$(pidof "$1" 2>/dev/null | awk '{print $1}')
    if [ -z "$P" ]; then
        P=$(pgrep -f "^$1" 2>/dev/null | head -n 1)
    fi
    echo "$P" | tr -cd '0-9'
}

# Đếm số cổng UDP: Ngoài sảnh Menu chỉ có 0-1 cổng, vào trong Blox Fruits sẽ có >= 2 cổng
has_net() {
    local cnt
    cnt=$(awk -v u="$1" 'NR>1 && $8==u {c++} END{print c+0}' /proc/net/udp /proc/net/udp6 2>/dev/null | tr -cd '0-9')
    [ "${cnt:-0}" -ge 2 ]
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

# Đã trả lại nguyên vẹn hàm monkey bung bong bóng chuẩn của bạn
watch_visible() {
    local W a IDX C
    while true; do
        if [ "$(get_cmd)" = "stop" ]; then sleep 2; continue; fi

        W=$(dumpsys window windows 2>/dev/null)
        IDX=1
        for a in $LIST_CLONE; do
            if [ -n "$(get_pid "$a")" ]; then
                if ! echo "$W" \vert{} grep -A40 "u0 $a/com.roblox.client.ActivityNativeMain" | grep -q "mHasSurface=true"; then
                    echo "$(date +%T) [THU NHO] Tab $IDX ($a) -> mo lai"
                    C=$(cat "$STATE/min_$IDX" 2>/dev/null | tr -cd '0-9')
                    C=${C:-0}
                    echo $(( C + 1 )) > "$STATE/min_$IDX"
                    monkey -p "$a" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
                    sleep 2
                fi
            fi
            IDX=$((IDX + 1))
        done
        sleep 3
    done
}

(
    while read -r user_cmd 2>/dev/null; do
        user_cmd=$(echo "$user_cmd" | tr -cd 'a-z')
        if [ "$user_cmd" = "stop" ] \vert{}\vert{} [ "$user_cmd" = "continue" ]; then
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

watch_visible &
WATCH_PID=$!

LOOP_COUNT=0
LAST_REPORT=0

while true; do
    if [ "$(get_cmd)" = "stop" ]; then
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
        MINC=$(cat "$STATE/min_$INDEX" 2>/dev/null \vert{} tr -cd '0-9'); MINC=${MINC:-0}
        PID=$(get_pid "$app")

        if [ -z "$PID" ]; then
            echo "[!] Tab $INDEX ($app) bị văng. Đang mở lại..."
            CNT=$((CNT + 1)); eval "CNT_$INDEX=$CNT"
            TOTAL_REJOIN=$((TOTAL_REJOIN + 1))
            
            send_discord "" 15158332 "THÔNG BÁO: TAB BỊ VĂNG" "🔴 **Tab $INDEX** (\`$app\`): Bị văng -> Đã mở lại (Lần $CNT)" &
            STATUS_TEXT="${STATUS_TEXT}🔴 **Tab $INDEX** (\`$app\`): Vừa mở lại (Lần $CNT)\n"
            launch_app "$app"
            
            # Đợi 18s để tab kịp load vào game, tránh mở 5 tab dồn dập gây tràn RAM văng dây chuyền
            wait_delay $LAUNCH_WAIT
        else
            UID_APP=$(awk '/^Uid:/{print $2}' /proc/$PID/status 2>/dev/null | tr -cd '0-9')
            if [ -n "$UID_APP" ] && ! has_net "$UID_APP"; then
                echo "[?] Tab $INDEX ($app) đang ở ngoài Menu Sảnh hoặc mất kết nối! Đang đẩy vào Blox Fruits..."
                launch_app "$app"
                
                wait_delay $NET_RECHECK

                if ! has_net "$UID_APP"; then
                    echo "[!] Tab $INDEX vẫn kẹt cứng. Tiến hành Force-Stop và mở lại..."
                    CNT=$((CNT + 1)); eval "CNT_$INDEX=$CNT"
                    TOTAL_REJOIN=$((TOTAL_REJOIN + 1))
                    
                    send_discord "" 16776960 "THÔNG BÁO: TAB KẸT MENU/LỖI" "🟡 **Tab $INDEX** (\`$app\`): Kẹt ở Menu/Lỗi 279 -> Đã restart (Lần $CNT)" &
                    STATUS_TEXT="${STATUS_TEXT}🟡 **Tab $INDEX** (\`$app\`): Vừa restart (Lần $CNT)\n"
                    am force-stop "$app"
                    sleep 2
                    launch_app "$app"
                    
                    wait_delay $LAUNCH_WAIT
                    INDEX=$((INDEX + 1))
                    continue
                else
                    echo "[OK] Đã đẩy Tab $INDEX từ Menu vào Blox Fruits thành công!"
                fi
            fi
            
            ONLINE_COUNT=$((ONLINE_COUNT + 1))
            APP_T=$(awk '{print $14+$15}' /proc/$PID/stat 2>/dev/null | tr -cd '0-9')
            APP_T=${APP_T:-0}
            eval "PV=\${PT_$INDEX:-0}"
            APP_CPU=$(( 100 * (APP_T - PV) / DTOT ))
            [ "$APP_CPU" -lt 0 ] && APP_CPU=0
            eval "PT_$INDEX=$APP_T"
            APP_RAM=$(awk '/VmRSS/{printf "%d", $2/1024}' /proc/$PID/status 2>/dev/null | tr -cd '0-9')
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

    CURRENT_TIME=$(date +%s | tr -cd '0-9')
    if [ $((CURRENT_TIME - LAST_REPORT)) -ge "$REPORT_INTERVAL" ]; then
        send_discord "" 3066993 "📊 TRẠNG THÁI ($ONLINE_COUNT/$TOTAL_CLONE ONLINE)" "$STATUS_TEXT" &
        send_screenshot &
        LAST_REPORT=$CURRENT_TIME
    fi

    wait_delay $CHECK_INTERVAL
done
