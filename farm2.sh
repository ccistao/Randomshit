
# Theo doi tab bi thu nho thanh bong bong. Moi tab xu ly doc lap, kiem tra moi giay.
#  - Tab bi an va game da ngung (heartbeat cu) -> bat len ngay, 10s sau neu van chua co heartbeat -> day vao game lai.
#  - Heartbeat con tuoi thi coi la khong bi an that (tranh bat nham). In dong [WATCH] moi khi trang thai doi.
watch_visible() {
    local W A a L N S V ST BLK H KEY OLD HBF AGE TH PEND
    while true; do
        if [ ! -f "$PAUSE_FILE" ] && [ ! -f "$STATE/resting" ]; then
            W=$(dumpsys window windows 2>/dev/null)
            A=$(dumpsys activity activities 2>/dev/null)
            N=$(date +%s)
            for a in $LIST_CLONE; do
                [ -n "$(get_pid "$a")" ] || continue
                S=false
                if [ "$(echo "$W" | awk -v pat="u0 $a/" '/^ *Window #/{b=(index($0,pat)>0)} b && /mHasSurface=true/{print "true"; exit}')" = "true" ]; then S=true; fi
                BLK=$(echo "$A" | grep -A16 "ActivityRecord{[^}]* u0 $a/" | head -n 17)
                V=$(echo "$BLK" | grep -oE "visible=(true|false)" | head -n 1 | cut -d= -f2)
                ST=$(echo "$BLK" | grep -oE "state=[A-Z_]+" | head -n 1 | cut -d= -f2)
                KEY="surface=$S visible=${V:-?} state=${ST:-?}"
                OLD=$(rv "wstate_$a" "")
                if [ "$KEY" != "$OLD" ]; then
                    wv "wstate_$a" "$KEY"
                    echo "$(date +%T) [WATCH] $a $KEY"
                    dbg "RAW window lines co $a" "$(echo "$W" | grep -n "$a" | head -n 12)"
                    dbg "RAW activity record cua $a" "$BLK"
                fi
                H=0
                [ "$S" = "false" ] && H=1
                [ "$V" = "false" ] && H=1
                case "$ST" in STOPPED|DESTROYED|FINISHING) H=1 ;; esac

                HBF=$(rv "hb_$a" ""); AGE=""; TH=63
                if [ -n "$HBF" ] && [ -f "$HBF" ]; then AGE=$(hb_age "$HBF"); TH=$(hb_fast_stale "$HBF"); fi
                L=$(rv "lt_$a" 0)      # thoi diem that su mo / day vao game gan nhat

                # (1) sau khi bat lai tab: game con song khong? neu da mat thi vao game lai ngay
                PEND=$(rv "pend_$a" 0)
                if [ "$PEND" -gt 0 ] && [ $((N - PEND)) -ge "$REJOIN_CHECK" ]; then
                    wv "pend_$a" 0
                    if [ -n "$AGE" ] && [ "$AGE" -le "$TH" ]; then
                        echo "$(date +%T) [OK] $a: bat lai xong, game van song"
                    elif [ -n "$AGE" ] && [ $((N - AGE)) -gt "$(rv "lt_$a" 0)" ] && [ $((N - $(rv "fastrj_$a" 0))) -ge 60 ]; then
                        echo "$(date +%T) [REJOIN NHANH] $a: bi an -> game da dung ${AGE}s -> vao game lai"
                        dbg "ACTION fast_rejoin pkg=$a age=$AGE th=$TH"
                        wv "fastrj_$a" "$N"
                        launch_app "$a"
                        wv "launch_$a" "$N"; wv "up_$a" "$N"; wv "stage_$a" 0; wv "lt_$a" "$N"; wv "gap_$a" 1
                    fi
                fi

                # (2) bat lai tab bi an ngay (kể ca khi game van chay: may that cho thay an chi la an cua so)
                if [ "$H" = "1" ]; then
                    CD=$REOPEN_COOLDOWN
                    [ "$(rv "reopen_n_$a" 0)" -ge 5 ] && CD=60      # bat nhieu lan van an -> thua ra tranh spam
                    if [ $((N - L)) -ge 10 ] && [ $((N - $(rv "reopen_$a" 0))) -ge "$CD" ]; then
                        wv "reopen_n_$a" "$(( $(rv "reopen_n_$a" 0) + 1 ))"
                        wv "reopen_$a" "$N"; wv "pend_$a" "$N"
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

trap 'kill $WATCH_PID 2>/dev/null; exit 0' INT TERM

echo "--- BAT DAU CANH TAB (tam dung: touch $PAUSE_FILE) ---"

init_tabs
WATCH_PID=""
if [ "$ENABLE_WATCH" = "1" ]; then
    watch_visible &
    WATCH_PID=$!
fi

# co the mo/restart them 1 tab chua? (cach nhau >= ACT_GAP giay de khong het RAM)
act_ok() { [ $(( $(date +%s) - LAST_ACT )) -ge "$ACT_GAP" ]; }

LAST_ACT=0
RESUME_AT=0
CYCLE_START=$START
MODE=run
REST_UNTIL=0
LAST_REST_PRINT=0
OFFLINE_SINCE=0
OFFLINE_ALERTED=0
LAST_RAM_WARN=0

while true; do
    NOW=$(date +%s)
    LOOP=$((LOOP + 1))

    if [ -f "$PAUSE_FILE" ]; then
        echo "$(date +%T) [PAUSE] xoa $PAUSE_FILE de chay tiep"
        sleep "$CHECK_INTERVAL"
        continue
    fi

    # ---- chu ky: treo CYCLE_RUN giay -> tat het cac tab -> nghi CYCLE_REST giay -> mo lai ----
    if [ "$MODE" = "rest" ]; then
        if [ "$NOW" -ge "$REST_UNTIL" ]; then
            MODE=run; CYCLE_START=$NOW; RESUME_AT=$NOW; OFFLINE_SINCE=0; OFFLINE_ALERTED=0
            rm -f "$STATE/resting"
            for p in $LIST_CLONE; do
                wv "consec_$p" 0; wv "stage_$p" 0; wv "gap_$p" 0; wv "up_$p" "$NOW"
            done
            echo "$(date +%T) [BAT LAI] het gio nghi, mo lai $TOTAL_CLONE tab (moi tab cach nhau ${ACT_GAP}s)"
            dbg "CYCLE resume"
        else
            if [ $((NOW - LAST_REST_PRINT)) -ge 60 ]; then
                echo "$(date +%T) [NGHI] con $(( (REST_UNTIL - NOW) / 60 )) phut nua se mo lai"
                LAST_REST_PRINT=$NOW
            fi
            sleep "$CHECK_INTERVAL"
            continue
        fi
    elif [ "$CYCLE_RUN" -gt 0 ] && [ $((NOW - CYCLE_START)) -ge "$CYCLE_RUN" ]; then
        echo "$(date +%T) [NGHI] da treo $((CYCLE_RUN / 3600))h$(((CYCLE_RUN % 3600) / 60))m -> tat het cac tab, nghi $((CYCLE_REST / 60)) phut"
        dbg "CYCLE rest start"
        : > "$STATE/resting"
        for p in $LIST_CLONE; do
            kill_tab "$p"
            sleep "$KILL_WAIT"
        done
        MODE=rest; REST_UNTIL=$(( $(date +%s) + CYCLE_REST )); LAST_REST_PRINT=0
        continue
    fi

    # con tab nao chua co file heartbeat thi quet lai (moi 4 vong)
    NEED=0
    for p in $LIST_CLONE; do
        f=$(rv "hb_$p" "")
        if [ -z "$f" ] || [ ! -f "$f" ]; then NEED=1; continue; fi
        a=$(hb_age "$f")
        if [ -z "$a" ] || [ "$a" -gt "$REMAP_FRESH" ]; then NEED=1; fi
    done
    if [ "$NEED" = "1" ] && { [ "$LOOP" -eq 1 ] || [ $((LOOP % 4)) -eq 0 ]; }; then
        discover_hb
        remap
        if [ "$AUTO_CAL" = "1" ]; then calibrate; fi
    fi

    NOW=$(date +%s)
    LINE="$(date +%T)"
    OK_COUNT=0
    IDX=0
    for p in $LIST_CLONE; do
        IDX=$((IDX + 1))
        PID=$(get_pid "$p")
        LAUNCHED=$(rv "launch_$p" "$START")
        SINCE=$((NOW - LAUNCHED))
        RUN=$((NOW - $(rv "up_$p" "$START")))

        # 1. app bi tat han -> mo lai ngay
        if [ -z "$PID" ]; then
            if act_ok; then
                if [ "$((NOW - RESUME_AT))" -lt "$((ACT_GAP * TOTAL_CLONE + 120))" ]; then
                    open_tab "$p" "$IDX"
                    LINE="$LINE T$IDX:mo-sau-nghi"
                else
                    restart_tab "$p" "$IDX" "app bi tat" 0 0
                    LINE="$LINE T$IDX:vang"
                fi
                LAST_ACT=$(date +%s)
            else
                LINE="$LINE T$IDX:vang(xep-hang)"
            fi
            continue
        fi

        HBF=$(rv "hb_$p" "")
        AGE=""
        if [ -n "$HBF" ] && [ -f "$HBF" ]; then AGE=$(hb_age "$HBF"); fi

        # heartbeat chi tinh la "moi" khi duoc ghi SAU lan mo/day vao game gan nhat
        HB_NEW=0
        if [ -n "$AGE" ] && [ $((NOW - AGE)) -gt "$(rv "lt_$p" 0)" ]; then HB_NEW=1; fi

        dbg "tab$IDX $p pid=$PID hb=$(basename "${HBF:-none}") age=${AGE:-none} new=$HB_NEW since=$SINCE stage=$(rv "stage_$p" 0) run=$RUN"
        if [ "$HB_NEW" = "1" ] && [ "$AGE" -le "$KICK_STALE" ]; then
            # 2. dang on
            OK_COUNT=$((OK_COUNT + 1))
            wv "consec_$p" 0
            wv "stage_$p" 0
            if [ "$(rv "gap_$p" 0)" = "1" ]; then
                # vua hoi phuc sau khi mat heartbeat -> tinh lai thoi gian treo
                wv "gap_$p" 0; wv "up_$p" "$NOW"; RUN=0
            fi
            LINE="$LINE T$IDX:ok(${AGE}s)"
        elif [ "$HB_NEW" = "1" ]; then
            # dang trong game roi mat heartbeat (bi day ra sanh / disconnect) -> khong can cho het JOIN_GRACE
            wv "gap_$p" 1
            if act_ok; then
                soft_push "$p" "$IDX" "dang trong game roi mat heartbeat ${AGE}s"
                LAST_ACT=$(date +%s)
                LINE="$LINE T$IDX:day-lai-nhanh"
            else
                LINE="$LINE T$IDX:xep-hang"
            fi
        elif [ "$SINCE" -lt "$JOIN_GRACE" ]; then
            wv "gap_$p" 1
            LINE="$LINE T$IDX:cho(${SINCE}s)"
        elif [ -z "$HBF" ] && [ "$(unmapped_fresh)" -gt 0 ]; then
            LINE="$LINE T$IDX:chua-map"
        else
            # 4. ket sanh / mat heartbeat: lan dau day lai vao game (khong kill), van ket thi moi kill
            wv "gap_$p" 1
            WHY="chua co heartbeat moi sau khi mo (o sanh / chua vao game)"
            if ! act_ok; then
                LINE="$LINE T$IDX:xep-hang"
            elif [ "$(rv "stage_$p" 0)" = "0" ]; then
                soft_push "$p" "$IDX" "$WHY"
                LAST_ACT=$(date +%s)
                LINE="$LINE T$IDX:day-lai"
            else
                restart_tab "$p" "$IDX" "$WHY (da day lai ma van ket)" 1 0
                LAST_ACT=$(date +%s)
                LINE="$LINE T$IDX:restart"
            fi
        fi
    done
    echo "$LINE"

    # tat ca tab mat heartbeat lau -> in canh bao 1 lan cho moi dot
    if [ "$OK_COUNT" -eq 0 ]; then
        [ "$OFFLINE_SINCE" -eq 0 ] && OFFLINE_SINCE=$NOW
        if [ $((NOW - OFFLINE_SINCE)) -ge "$OFFLINE_ALERT" ] && [ "$OFFLINE_ALERTED" -eq 0 ]; then
            OFFLINE_ALERTED=1
            echo "$(date +%T) [CANH BAO] Khong tab nao co heartbeat tu $((OFFLINE_ALERT/60)) phut. Kiem tra acc / mang / autoexec."
        fi
    else
        OFFLINE_SINCE=0; OFFLINE_ALERTED=0
    fi

    # RAM thap: bao im lang, toi da 30 phut 1 lan
    MEM_NOW=$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)
    if [ -n "$MEM_NOW" ] && [ "$MEM_NOW" -lt "$MIN_RAM" ] && [ $((NOW - LAST_RAM_WARN)) -ge 1800 ]; then
        LAST_RAM_WARN=$NOW
        echo "$(date +%T) [CANH BAO] RAM trong con ${MEM_NOW}MB"
    fi

    [ $((LOOP % 60)) -eq 0 ] && dbg_trim
    sleep "$CHECK_INTERVAL"
done
