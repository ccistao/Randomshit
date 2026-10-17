#!/system/bin/sh
PLACE_ID="2753915549"
DISCORD_USER_ID="982107241371013132"
WEBHOOK_URL="https://discord.com/api/webhooks/1560579280906489906/jK4Gj1NoNmqY-3x_7nOUHg0UQEXPgIgNqnN_8xG4u8LNqniyztRDE1DVXjl2a5k5EKSs"
FILTER="roblox|delta|aya"

CHECK_INTERVAL=15
LAUNCH_WAIT=15        
COLD_BOOT_WAIT=35     
NET_RECHECK=10
REPORT_INTERVAL=3600
MAX_UPTIME=7200
MIN_RAM=300
STATE="/data/local/tmp/farmstate"

LIST_CLONE=$(pm list packages -3 | cut -d: -f2 | grep -iE "$FILTER" | tr -d '\r')
if [ -z "$LIST_CLONE" ]; then
    echo "Khong tim thay clone nao!"
    exit 1
fi

TOTAL_CLONE=$(echo "$LIST_CLONE" | wc -l | tr -cd '0-9')
TOTAL_CLONE=${TOTAL_CLONE:-0}
echo "Da nhan dien $TOTAL_CLONE tab:"
echo "$LIST_CLONE"

rm -rf "$STATE"
mkdir -p "$STATE"

START=$(date +%s | tr -cd '0-9')
START=${START:-0}
PREV_TOT=""
PREV_IDLE=0
CPU=0
DTOT=1
TOTAL_REJOIN=0
LAST_ALERT=-100
MEM=0
UPTXT="0h0m"

IDX_INIT=1
for app in $LIST_CLONE; do
    echo "$START" > "$STATE/up_$IDX_INIT"
    echo "0" > "$STATE/min_$IDX_INIT"
    IDX_INIT=$((IDX_INIT + 1))
done

sys_stats() {
    local NOW_S U
    MEM=$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null | tr -cd '0-9')
    [ -z "$MEM" ] && MEM=$(awk '/MemFree/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null | tr -cd '0-9')
    MEM=${MEM:-0}
    NOW_S=$(date +%s | tr -cd '0-9')
    U=$(( ${NOW_S:-0} -${START:-0} ))
    [ "${U:-0}" -lt 0 ] && U=0
    UPTXT="$((U/3600))h$(((U%3600)/60))m"
}

send_discord() {
    local TIME_NOW JSON FIELDS RESP CODE CONTENT_JSON
    sys_stats
    TIME_NOW=$(date +"%H:%M:%S")
    FIELDS="[{\"name\":\"CPU\",\"value\":\"${CPU:-0}%\",\"inline\":true},{\"name\":\"RAM Trong\",\"value\":\"${MEM:-0}MB\",\"inline\":true},{\"name\":\"Uptime\",\"value\":\"$UPTXT\",\"inline\":true},{\"name\":\"Tong Rejoin\",\"value\":\"${TOTAL_REJOIN:-0}\",\"inline\":true}]"
    
    if [ -n "$1" ]; then
        CONTENT_JSON="\"content\":\"$1\","
    else
        CONTENT_JSON=""
    fi
    
    JSON="{${CONTENT_JSON}\"embeds\":[{\"title\":\"$3\",\"description\":\"$4\",\"color\":${2:-3066993},\"fields\":$FIELDS,\"footer\":{\"text\":\"$TIME_NOW\"}}]}"
    
    RESP=$(curl -s -4 --connect-timeout 5 -m 15 --retry 2 \
        -H "Content-Type: application/json" -X POST -d "$JSON" \
        -w "\n%{http_code}" "$WEBHOOK_URL" 2>&1)
    CODE=$(echo "$RESP" | tail -n 1 | tr -cd '0-9')
    case "$CODE" in
        *200*|*204*) echo "[Discord] Gui OK luc $TIME_NOW" ;;
        *) echo "[Discord] LOI HTTP $CODE" ;;
    esac
}

send_screenshot() {
    local FILE="/data/local/tmp/screen.png"
    screencap -p "$FILE"
    curl -s -X POST "$WEBHOOK_URL" \
        -F "payload_json={\"embeds\":[{\"title\":\"📸 ANH CHUP MAN HINH DINH KY\",\"color\":3066993,\"image\":{\"url\":\"attachment://screen.png\"}}]}" \
        -F "file=@$FILE" > /dev/null 2>&1
    rm -f "$FILE"
    echo "[Discord] Da gui anh chup man hinh."
}

get_pid() {
    local P
    P=$(pidof "$1" 2>/dev/null | awk '{print $1}')
    if [ -z "$P" ]; then
        P=$(pgrep -f "^$1" 2>/dev/null | head -n 1)
    fi
    echo "$P" | tr -cd '0-9'
}

launch_app() {
    local OUT
    if [ -z "$(get_pid "$1")" ]; then
        monkey -p "$1" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
        sleep 3
    fi
    OUT=$(am start -n "$1/com.roblox.client.ActivityProtocolLaunch" -a android.intent.action.VIEW -d "roblox://experiences/start?placeId=$PLACE_ID" 2>&1)
    case "$OUT" in
        *Error*|*Exception*|*unable*)
            am start -a android.intent.action.VIEW -p "$1" -d "roblox://experiences/start?placeId=$PLACE_ID" > /dev/null 2>&1
            ;;
    esac
}

has_net() {
    local cnt
    cnt=$(awk -v u="$1" 'NR>1 && $8==u {c++} END{print c+0}' /proc/net/udp /proc/net/udp6 2>/dev/null | tr -cd '0-9')
    [ "${cnt:-0}" -ge 2 ]
}

cpu_total() {
    read -r _ u n s i io irq sirq st _ < /proc/stat
    TOT=$((u+n+s+i+io+irq+sirq+st))
    IDLE=$((i+io))
    if [ -n "$PREV_TOT" ]; then
        DTOT=$((TOT - PREV_TOT))
        [ "${DTOT:-0}" -le 0 ] && DTOT=1
        CPU=$(( 100 * (DTOT - (IDLE - PREV_IDLE)) / DTOT ))
    else
        CPU=0
        DTOT=1
    fi
    PREV_TOT=$TOT
    PREV_IDLE=$IDLE
}

watch_visible() {
    local W a IDX C TAB_UP NOW_TS AGE
    while true; do
        W=$(dumpsys window windows 2>/dev/null)
        IDX=1
        for a in $LIST_CLONE; do
            TAB_UP=$(cat "$STATE/up_$IDX" 2>/dev/null | tr -cd '0-9')
            NOW_TS=$(date +%s | tr -cd '0-9')
            AGE=$(( ${NOW_TS:-0} -${TAB_UP:-0} ))
            if [ "${AGE:-0}" -lt 60 ]; then
                IDX=$((IDX + 1))
                continue
            fi

            if pidof "$a" >/dev/null 2>&1; then
                if ! echo "$W" \vert{} grep -A35 "$a/" | grep -q "mHasSurface=true"; then
                    echo "$(date +%T) [THU NHO] Tab $IDX ($a) -> bung cua so lai"
                    C=$(cat "$STATE/min_$IDX" 2>/dev/null | tr -cd '0-9')
                    C=${C:-0}
                    echo $(( C + 1 )) > "$STATE/min_$IDX"
                    monkey -p "$a" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
                    sleep 3
                fi
            fi
            IDX=$((IDX + 1))
        done
        sleep 3
    done
}

send_discord "" 3447003 "🚀 BAT DAU CHAY SCRIPT" "Dang canh gac $TOTAL_CLONE tab. Da xoa Force-Stop de tranh chet chum." &
echo "--- BAT DAU CANH TAB (FULL AUTO) ---"
echo "=> (Nhan CTRL + C de dung tool)"

watch_visible &
WATCH_PID=$!

LOOP_COUNT=0
LAST_REPORT=0

while true; do
    ONLINE_COUNT=0
    STATUS_TEXT=""
    LINE="$(date +%T)"
    INDEX=1
    cpu_total
    sys_stats

    for app in $LIST_CLONE; do
        eval "CNT=\${CNT_$INDEX:-0}"
        CNT=${CNT:-0}
        MINC=$(cat "$STATE/min_$INDEX" 2>/dev/null | tr -cd '0-9')
        MINC=${MINC:-0}
        TAB_UP=$(cat "$STATE/up_$INDEX" 2>/dev/null | tr -cd '0-9')
        TAB_UP=${TAB_UP:-$START}
        NOW_TS=$(date +%s | tr -cd '0-9')
        NOW_TS=${NOW_TS:-0}
        RUN_TIME=$(( NOW_TS - TAB_UP ))
        [ "${RUN_TIME:-0}" -lt 0 ] && RUN_TIME=0

        PID=$(get_pid "$app")

        # 1. Kiem tra tab bi vang
        if [ -z "$PID" ]; then
            echo "[!] Tab $INDEX ($app) chua bat/bi vang. Dang mo lai..."
            CNT=$((CNT + 1))
            eval "CNT_$INDEX=$CNT"
            TOTAL_REJOIN=$((TOTAL_REJOIN + 1))
            echo "$(date +%s | tr -cd '0-9')" > "$STATE/up_$INDEX"

            send_discord "" 15158332 "THONG BAO: TAB BI VANG" "🔴 **Tab $INDEX** (\`$app\`): Bi vang -> Da mo lai (Lan $CNT)" &
            STATUS_TEXT="${STATUS_TEXT}🔴 **Tab $INDEX** (\`$app\`): Vua mo lai tu dau\n"
            LINE="$LINE T$INDEX:vang"
            launch_app "$app"

            sleep $COLD_BOOT_WAIT
            INDEX=$((INDEX + 1))
            continue
        fi

        # 2. Reset 2 tieng chong lag (DUNG KILL -9 THAY CHO FORCE-STOP)
        TAB_MAX_UPTIME=$(( MAX_UPTIME + (INDEX * 300) ))
        if [ "${RUN_TIME:-0}" -ge "$TAB_MAX_UPTIME" ]; then
            echo "[🔄] Tab $INDEX ($app) da den gio reset xoa lag..."
            CNT=$((CNT + 1))
            eval "CNT_$INDEX=$CNT"
            TOTAL_REJOIN=$((TOTAL_REJOIN + 1))

            send_discord "" 3447003 "🔄 AUTO RESET XOA LAG" "🔵 **Tab $INDEX** (\`$app\`): Da treo $RUN_TIME giay -> Tu dong tat bat lai de xoa lag." &
            STATUS_TEXT="${STATUS_TEXT}🔵 **Tab $INDEX** (\`$app\`): Vua reset xoa lag\n"
            LINE="$LINE T$INDEX:reset2h"

            # Ban tia dung tab do bang kill -9
            kill -9 "$PID" 2>/dev/null
            sleep 2
            launch_app "$app"
            echo "$(date +%s | tr -cd '0-9')" > "$STATE/up_$INDEX"

            sleep $COLD_BOOT_WAIT
            INDEX=$((INDEX + 1))
            continue
        fi

        # 3. Kiem tra kẹt loi 279 / Sanh Menu (DUNG KILL -9 THAY CHO FORCE-STOP)
        UID_APP=$(awk '/^Uid:/{print $2}' /proc/$PID/status 2>/dev/null | tr -cd '0-9')
        if [ -n "$UID_APP" ] && ! has_net "$UID_APP"; then
            if [ "${RUN_TIME:-0}" -lt 60 ]; then
                INDEX=$((INDEX + 1))
                continue
            fi

            echo "[?] Tab $INDEX o ngoai Menu Sanh hoac mat ket noi! Dang day vao game..."
            launch_app "$app"
            sleep $NET_RECHECK

            if ! has_net "$UID_APP"; then
                echo "[!] Tab $INDEX ket cung. Tien hanh Kill va mo lai..."
                CNT=$((CNT + 1))
                eval "CNT_$INDEX=$CNT"
                TOTAL_REJOIN=$((TOTAL_REJOIN + 1))

                send_discord "" 16776960 "THONG BAO: TAB KET MENU/LOI" "🟡 **Tab $INDEX** (\`$app\`): Ket Menu/Loi 279 -> Da kill mo lai (Lan $CNT)" &
                STATUS_TEXT="${STATUS_TEXT}🟡 **Tab $INDEX** (\`$app\`): Vua restart do ket\n"
                LINE="$LINE T$INDEX:restart"

                # Ban tia dung tab do bang kill -9
                kill -9 "$PID" 2>/dev/null
                sleep 2
                launch_app "$app"
                echo "$(date +%s | tr -cd '0-9')" > "$STATE/up_$INDEX"

                sleep $COLD_BOOT_WAIT
                INDEX=$((INDEX + 1))
                continue
            else
                echo "[OK] Da day Tab $INDEX vao game thanh cong!"
            fi
        fi

        ONLINE_COUNT=$((ONLINE_COUNT + 1))
        APP_T=$(awk '{print $14+$15}' /proc/$PID/stat 2>/dev/null | tr -cd '0-9')
        APP_T=${APP_T:-0}
        eval "PV=\${PT_$INDEX:-0}"
        PV=${PV:-0}
        APP_CPU=$(( 100 * (APP_T - PV) /${DTOT:-1} ))
        [ "${APP_CPU:-0}" -lt 0 ] && APP_CPU=0
        eval "PT_$INDEX=$APP_T"
        APP_RAM=$(awk '/VmRSS/{printf "%d", $2/1024}' /proc/$PID/status 2>/dev/null | tr -cd '0-9')
        APP_RAM=${APP_RAM:-0}
        UP_MIN=$(( RUN_TIME / 60 ))
        LINE="$LINE T$INDEX:ok(${UP_MIN}m)"
        STATUS_TEXT="${STATUS_TEXT}🟢 **Tab $INDEX** (\`$app\`): Treo ${UP_MIN}p | CPU ${APP_CPU}\% \vert{} RAM${APP_RAM}MB | Rejoin: $CNT \vert{} Bung nho:$MINC\n"
        INDEX=$((INDEX + 1))
    done

    echo "$LINE"
    LOOP_COUNT=$((LOOP_COUNT + 1))

    WARN=""
    if [ "${MEM:-0}" -lt "${MIN_RAM:-300}" ]; then
        WARN="${WARN}RAM trong chi con${MEM}MB. May ao co nguy co vang toan bo tab!\n"
    fi
    if [ -n "$WARN" ] && [ $(( ${LOOP_COUNT:-0} -${LAST_ALERT:-0} )) -ge 10 ]; then
        LAST_ALERT=$LOOP_COUNT
        send_discord "<@$DISCORD_USER_ID>" 15105570 "⚠️ CANH BAO HE THONG" "$WARN" &
    fi

    if [ "${ONLINE_COUNT:-0}" -eq 0 ]; then
        send_discord "<@$DISCORD_USER_ID>" 15158332 "🚨 TAT CA TAB DEU OFFLINE" "Khong con tab nao dang farm, he thong dang co keo lai." &
    fi

    CURRENT_TIME=$(date +%s | tr -cd '0-9')
    CURRENT_TIME=${CURRENT_TIME:-0}
    if [ $(( CURRENT_TIME - ${LAST_REPORT:-0} )) -ge "${REPORT_INTERVAL:-3600}" ]; then
        send_discord "" 3066993 "📊 TRANG THAI ($ONLINE_COUNT/$TOTAL_CLONE ONLINE)" "$STATUS_TEXT" &
        send_screenshot &
        LAST_REPORT=$CURRENT_TIME
    fi

    sleep $CHECK_INTERVAL
done
