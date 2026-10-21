
# Theo doi tab bi thu nho thanh bong bong -> bat len lai ngay. Moi tab doc lap, kiem tra moi giay.
watch_visible() {
    local W a N S OLD L CD
    while true; do
        if [ ! -f "$PAUSE_FILE" ]; then
            W=$(dumpsys window windows 2>/dev/null)
            N=$(date +%s)
            for a in $LIST_CLONE; do
                [ -n "$(get_pid "$a")" ] || continue
                S=false
                if [ "$(echo "$W" | awk -v pat="u0 $a/" '/^ *Window #/{b=(index($0,pat)>0)} b && /mHasSurface=true/{print "true"; exit}')" = "true" ]; then S=true; fi
                OLD=$(rv "wstate_$a" "")
                if [ "$S" != "$OLD" ]; then wv "wstate_$a" "$S"; dbg "WATCH $a surface=$S"; fi
                if [ "$S" = "false" ]; then
                    L=$(rv "lt_$a" 0)
                    CD=$REOPEN_COOLDOWN
                    [ "$(rv "reopen_n_$a" 0)" -ge 5 ] && CD=60      # bat nhieu lan van an -> thua ra, tranh spam
                    if [ $((N - L)) -ge 10 ] && [ $((N - $(rv "reopen_$a" 0))) -ge "$CD" ]; then
                        wv "reopen_n_$a" "$(( $(rv "reopen_n_$a" 0) + 1 ))"
                        wv "reopen_$a" "$N"
                        echo "$(date +%T) [THU NHO] $a -> mo lai"
                        monkey -p "$a" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1 &
                    fi
                else
                    wv "reopen_n_$a" 0
                fi
            done
        fi
        sleep "$WATCH_INTERVAL"
    done
}

# co the mo/day/restart them 1 tab chua? (cach nhau >= ACT_GAP giay de khong het RAM)
act_ok() { [ $(( $(date +%s) - LAST_ACT )) -ge "$ACT_GAP" ]; }

trap 'kill $WATCH_PID $READER_PID 2>/dev/null; pkill -f "logcat -b main -v threadtime -T 1" 2>/dev/null; exit 0' INT TERM

echo "--- BAT DAU CANH TAB (tam dung: touch $PAUSE_FILE) ---"
LAST_ACT=0
start_reader
init_tabs
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

    # tien trinh doc log bi dung -> mo lai, bo qua vong nay (khong co du lieu thi khong hanh dong)
    if ! reader_alive; then
        echo "$(date +%T) [!] tien trinh doc log bi dung, dang mo lai"
        start_reader
        sleep "$CHECK_INTERVAL"
        continue
    fi

    LINE="$(date +%T)"
    IDX=0
    for p in $LIST_CLONE; do
        IDX=$((IDX + 1))
        PID=$(get_pid "$p")

        # 1. app bi tat han -> mo lai
        if [ -z "$PID" ]; then
            if act_ok; then
                restart_tab "$p" "$IDX" "app bi tat" 0
                LAST_ACT=$(date +%s)
                LINE="$LINE T$IDX:vang"
            else
                LINE="$LINE T$IDX:vang(xep-hang)"
            fi
            continue
        fi

        LT=$(rv "lt_$p" "$START")
        JT=$(ev join "$PID"); DT=$(ev disc "$PID"); HT=$(ev hb "$PID")
        STAGE=$(rv "stage_$p" 0)

        # ten acc trong tab (lay tu log, chi de hien thi)
        U=""; [ -f "$EV/user_$PID" ] && U=$(cat "$EV/user_$PID" 2>/dev/null | tr -d '\r\n')
        if [ -n "$U" ] && [ "$(rv "shown_$p" "")" != "$PID:$U" ]; then
            wv "shown_$p" "$PID:$U"
            echo "$(date +%T) [ACC] Tab $IDX ($p, pid $PID) = $U"
        fi

        # gui lai link 1 lan neu sau LAUNCH_RETRY giay log khong thay "Joining game" (app chi mo ma khong vao game)
        if [ "$LAUNCH_RETRY" -gt 0 ] && [ "$(rv "resent_$p" 1)" = "0" ] && [ "$JT" -lt "$LT" ] && [ $((NOW - LT)) -ge "$LAUNCH_RETRY" ]; then
            wv "resent_$p" 1
            echo "$(date +%T) [GUI LAI LINK] Tab $IDX ($p): ${LAUNCH_RETRY}s sau khi gui link van chua thay vao game -> gui lai"
            send_join "$p"
        fi

        # Lua con bao hieu khong (chi tinh la moi neu duoc in SAU lan day vao game gan nhat)
        HBAGE=""; HBOK=0
        if [ "$HT" -gt 0 ]; then
            HBAGE=$((NOW - HT))
            if [ "$HBAGE" -le "$HB_STALE" ] && { [ "$STAGE" = "0" ] || [ "$HT" -gt "$LT" ]; }; then HBOK=1; fi
        fi

        if [ "$HBOK" = "1" ]; then
            wv "consec_$p" 0; wv "stage_$p" 0
            LINE="$LINE T$IDX:ok(${HBAGE}s)"
            dbg "tab$IDX $p pid=$PID user=${U:-?} state=ok hb=${HBAGE}s"
            continue
        fi

        # khong on: bi ngat ket noi (log "Disconnection" sau lan "Joining game" cuoi) hay dang vao game / ket
        if [ "$DT" -gt "$JT" ]; then
            KIND="bi ngat ket noi"; LIM=$DISC_WAIT
            REF=$DT; [ "$LT" -gt "$REF" ] && REF=$LT
            TAG="ngat"
        else
            KIND="chua vao game duoc"; LIM=$JOIN_GRACE
            REF=$HT; [ "$JT" -gt "$REF" ] && REF=$JT; [ "$LT" -gt "$REF" ] && REF=$LT
            TAG="cho"
        fi
        [ "$STAGE" = "1" ] && LIM=$SOFT_GRACE
        WAITED=$((NOW - REF))
        dbg "tab$IDX $p pid=$PID user=${U:-?} state=$TAG waited=${WAITED}s lim=${LIM}s stage=$STAGE join=$JT disc=$DT hb=${HBAGE:-none}"

        if [ "$WAITED" -lt "$LIM" ]; then
            LINE="$LINE T$IDX:$TAG(${WAITED}s)"
        elif ! act_ok; then
            LINE="$LINE T$IDX:xep-hang"
        elif [ "$STAGE" = "0" ]; then
            soft_push "$p" "$IDX" "$KIND ${WAITED}s"
            LAST_ACT=$(date +%s)
            LINE="$LINE T$IDX:day-lai"
        else
            restart_tab "$p" "$IDX" "$KIND (da day lai ma van ket)" 1
            LAST_ACT=$(date +%s)
            LINE="$LINE T$IDX:restart"
        fi
    done
    echo "$LINE"

    [ $((LOOP % 120)) -eq 0 ] && dbg_trim
    sleep "$CHECK_INTERVAL"
done
