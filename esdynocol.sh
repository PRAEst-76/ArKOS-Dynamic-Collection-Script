#!/usr/bin/env bash

set -o pipefail

APP_NAME="esdynocol"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$APP_NAME"
mkdir -p "$CONFIG_DIR"

MAP_FILE="$CONFIG_DIR/genre_map.cfg"
WHITELIST_FILE="$CONFIG_DIR/whitelist.cfg"
CACHE_FILE="$CONFIG_DIR/cache.txt"

ROM_ROOT="${ROM_ROOT:-/roms}"
COLLECTION_DIR="${COLLECTION_DIR:-$HOME/.emulationstation/collections}"

AUDIT_MODE=0
DRY_RUN=0

for arg in "$@"; do
    case "$arg" in
        --audit) AUDIT_MODE=1 ;;
        --dry-run) DRY_RUN=1 ;;
    esac
done

bootstrap_config() {

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$COLLECTION_DIR"

    # Genre map (with your theme fix)
    [[ -f "$MAP_FILE" ]] || cat > "$MAP_FILE" << 'EOF'
rpg=rpgs
role playing=rpgs
jrpg=rpgs
dungeon crawler=rpgs
platform=platformers
shooter=shooter
action=action
action-adventure=action
adventure=adventure
arcade=arcade
fighting=btmups
beat em up=btmups
beat'em up=btmups
brawlers=btmups
sports=sports
puzzle=puzzle
strategy=strategy
simulation=simulation
EOF

    # Whitelist
    [[ -f "$WHITELIST_FILE" ]] || cat > "$WHITELIST_FILE" << 'EOF'
action
adventure
arcade
btmups
platformers
puzzle
racing
rpgs
shooter
sports
strategy
simulation
horror
music
party
pinball
EOF

    # Cache
    [[ -f "$CACHE_FILE" ]] || touch "$CACHE_FILE"
}

# =====================================================
# LOAD CONFIG
# =====================================================
declare -A GENRE_MAP
declare -A SEEN
declare -A SEEN_RUN
declare -A AUDIT
declare -A IGNORED

trim() {
    local v="$1"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    echo -n "$v"
}

load_config() {

    [[ -f "$CACHE_FILE" ]] || touch "$CACHE_FILE"

    while IFS= read -r line; do
        SEEN["$line"]=1
    done < "$CACHE_FILE"

    while IFS="=" read -r k v; do
        k=$(trim "$k")
        v=$(trim "$v")
        [[ -z "$k" || "$k" =~ ^# ]] && continue
        GENRE_MAP["$(echo "$k" | tr '[:upper:]' '[:lower:]')"]="$v"
    done < "$MAP_FILE"

    mapfile -t WHITELIST < "$WHITELIST_FILE"
}

is_allowed() {
    local g="$1"
    for w in "${WHITELIST[@]}"; do
        [[ "$g" == "$w" ]] && return 0
    done
    return 1
}

normalize_genre() {
    local in="$1"
    in=$(echo "$in" | tr '[:upper:]' '[:lower:]')

    for k in "${!GENRE_MAP[@]}"; do
        [[ "$in" == *"$k"* ]] && {
            echo "${GENRE_MAP[$k]}"
            return 0
        }
    done
    return 1
}

decode_xml() {
    echo "$1" | sed "s/&apos;/'/g; s/&amp;/\&/g"
}

# =====================================================
# ENGINE
# =====================================================
run() {

    bootstrap_config
    load_config

    echo "Scanning gamelists..."

    while IFS= read -r gamelist; do

        SYSTEM_DIR=$(dirname "$gamelist")
        SYSTEM_NAME=$(basename "$SYSTEM_DIR")

        echo "Processing: $SYSTEM_NAME"

        xmlstarlet sel -t -m "//game" \
            -v "concat(path,'|',genre)" -n "$gamelist" 2>/dev/null |

        while IFS="|" read -r path genre; do

            CLEAN_PATH="${path#./}"
            FULL_PATH="$SYSTEM_DIR/$CLEAN_PATH"

            genre=$(decode_xml "$genre")

            IFS=',' read -ra GENRES <<< "$genre"

            for raw in "${GENRES[@]}"; do

                raw="$(trim "$raw")"
                [[ -z "$raw" ]] && continue

                AUDIT["$raw"]=$(( ${AUDIT["$raw"]:-0} + 1 ))

                g="$(normalize_genre "$raw")"

                # STRICT: no mapping → ignore
                if [[ -z "$g" ]]; then
                    IGNORED["$raw"]=$(( ${IGNORED["$raw"]:-0} + 1 ))
                    continue
                fi

                # STRICT whitelist enforcement
                is_allowed "$g" || continue

                key="$g|$FULL_PATH"

                # DUPLICATE FIX (run + cache)
                if [[ -z "${SEEN[$key]}" && -z "${SEEN_RUN[$key]}" ]]; then

                    if [[ "$DRY_RUN" -eq 0 ]]; then
                        echo "$FULL_PATH" >> "$COLLECTION_DIR/custom-$g.cfg"
                        echo "$key" >> "$CACHE_FILE"
                    else
                        echo "[DRY] $g -> $FULL_PATH"
                    fi

                    SEEN["$key"]=1
                    SEEN_RUN["$key"]=1
                fi

            done
        done

    done < <(find "$ROM_ROOT" \
        -type d -name ".*" -prune -o \
        -type f -name "gamelist.xml" -print)

    # =====================================================
    # AUDIT OUTPUT
    # =====================================================
    if [[ "$AUDIT_MODE" -eq 1 ]]; then

        echo ""
        echo "===== RAW GENRES ====="
        for k in "${!AUDIT[@]}"; do
            printf "%-30s %5d\n" "$k" "${AUDIT[$k]}"
        done | sort

        echo ""
        echo "===== IGNORED (NOT MAPPED) ====="
        for k in "${!IGNORED[@]}"; do
            printf "%-30s %5d\n" "$k" "${IGNORED[$k]}"
        done | sort
    fi

    echo ""
    echo "Done."
    read -r -p "Press ENTER..."
}

run
