#!/system/bin/sh
FILTER="roblox|delta|aya"
LIST_CLONE=$(pm list packages -3 | cut -d: -f2 | grep -iE "$FILTER" | tr -d '\r')

get_pid() {
    local P
    P=$(pidof "$1" 2>/dev/null | cut -d' ' -f1 | tr -cd '0-9')
    [ -z "$P" ] && P=$(pgrep -f "^$1" 2>/dev/null | head -n 1 | tr -cd '0-9')
    echo "$P"
}

echo "--- BAT DAU CANH BONG BONG (FARM 3) ---"
while true; do
    W=$(dumpsys window windows 2>/dev/null)
    IDX=1
    for a in $LIST_CLONE; do
        P=$(get_pid "$a")
        if [ -n "$P" ]; then
            # Dung dung bo loc package=$a cua ban Debug da work
            if ! echo "$W" | grep -A35 "package=$a" | grep -q "mHasSurface=true"; then
                echo "$(date +%T) [BONG BONG] Tab $IDX ($a) bi thu nho -> Bung len!"
                monkey -p "$a" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
                sleep 2
            fi
        fi
        IDX=$((IDX + 1))
    done
    sleep 3
done
