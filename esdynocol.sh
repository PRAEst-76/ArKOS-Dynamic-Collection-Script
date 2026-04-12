#!/usr/bin/env bash

set -o pipefail

APP_NAME="esdynocol"

# =====================================================
# CONFIG (XDG + fallback)
# =====================================================
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$APP_NAME"
[[ -d "$CONFIG_DIR" ]] || CONFIG_DIR="$HOME/.esdynocol"

mkdir -p "$CONFIG_DIR"

MAP_FILE="$CONFIG_DIR/genre_map.cfg"
WHITELIST_FILE="$CONFIG_DIR/whitelist.cfg"
CACHE_FILE="$CONFIG_DIR/cache.txt"

ROM_ROOT="${ROM_ROOT:-/roms}"
COLLECTION_DIR="${COLLECTION_DIR:-$HOME/.emulationstation/collections}"

# =====================================================
# MODES
# =====================================================
DRY_RUN=0
DIFF_MODE=0
SHOW_IGNORED=0

# =====================================================
# ARG PARSER
# =====================================================
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --diff) DIFF_MODE=1 ;;
        --show-ignored) SHOW_IGNORED=1 ;;
    esac
done

# =====================================================
# BOOTSTRAP CONFIG
# =====================================================
bootstrap_config() {

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$COLLECTION_DIR"

    [[ -f "$MAP_FILE" ]] || cat > "$MAP_FILE" << 'EOF'
rpg=rpgs
role playing=rpgs
platform=platformers
shooter=shooter
action=action
adventure=adventure
arcade=arcade
fighting=fighting
sports=sports
puzzle=puzzle
strategy=strategy
simulation=simulation
EOF

    [[ -f "$WHITELIST_FILE" ]] || cat > "$WHITELIST_FILE" << 'EOF'
action
adventure
arcade
brawlers
fighting
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

    [[ -f "$CACHE_FILE" ]] || touch "$CACHE_FILE"
}

# =====================================================
# HELPERS
# =====================================================
trim() {
    local v="$1"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    echo -n "$v"
}

decode_xml() {
    local s="$1"
    s=$(echo "$s" | sed "s/&apos;/'/g; s/&amp;/\&/g")
    echo "$s"
}

declare -A GENRE_MAP

load_config() {
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

# =====================================================
# ENGINE
# =====================================================
run_engine() {

    bootstrap_config
    load_config

    declare -A GENRE_COUNT
    declare -A IGNORED_UNMAPPED
    declare -A IGNORED_BLOCKED

    # 🧠 DEDUP FIX (runtime protection)
    declare -A SEEN

    mkdir -p "$COLLECTION_DIR"
    touch "$CACHE_FILE"

    echo "Scanning gamelist.xml files..."

    while IFS= read -r gamelist; do

        echo "Processing: $gamelist"

        current_hash=$(md5sum "$gamelist" | awk '{print $1}')
        cached_hash=$(grep "^$gamelist|" "$CACHE_FILE" | cut -d'|' -f2)

        if [[ "$current_hash" == "$cached_hash" && "$DRY_RUN" -eq 0 && "$DIFF_MODE" -eq 0 ]]; then
            echo "Skipping unchanged"
            continue
        fi

        SYSTEM_DIR=$(dirname "$gamelist")

        while IFS="|" read -r path genre; do

            CLEAN_PATH="${path#./}"
            FULL_PATH="$SYSTEM_DIR/$CLEAN_PATH"

            genre=$(decode_xml "$genre")
            genre=$(echo "$genre" | sed 's/action-adventure/action,adventure/Ig')
            genre=$(echo "$genre" | sed 's/ *, */,/g')

            IFS=',' read -ra GENRES <<< "$genre"

            for raw in "${GENRES[@]}"; do

                raw=$(trim "$raw")
                [[ -z "$raw" ]] && continue

                g=$(normalize_genre "$raw")

                [[ -z "$g" ]] && continue
                is_allowed "$g" || continue

                # =================================================
                # 🧠 DEDUP FIX (per-run protection)
                # =================================================
                key="${g}|${FULL_PATH}"

                if [[ -z "${SEEN[$key]}" ]]; then

                    if [[ "$DRY_RUN" -eq 1 ]]; then
                        echo "[DRY] $g -> $FULL_PATH"
                    elif [[ "$DIFF_MODE" -eq 1 ]]; then
                        echo "$FULL_PATH"
                    else
                        echo "$FULL_PATH" >> "$COLLECTION_DIR/custom-$g.cfg"
                        GENRE_COUNT["$g"]=$(( ${GENRE_COUNT[$g]:-0} + 1 ))
                    fi

                    SEEN["$key"]=1
                fi

            done

        done < <(
            xmlstarlet sel -t -m "//game[genre]" \
            -v "concat(path,'|',genre)" -n "$gamelist" 2>/dev/null
        )

        # cache update
        grep -v "^$gamelist|" "$CACHE_FILE" > "$CACHE_FILE.tmp" 2>/dev/null || true
        mv "$CACHE_FILE.tmp" "$CACHE_FILE"
        echo "$gamelist|$current_hash" >> "$CACHE_FILE"

    done < <(find "$ROM_ROOT" -type f -name "gamelist.xml")

    # =================================================
    # FINAL FILE CLEANUP (IMPORTANT)
    # =================================================
    echo ""
    echo "Deduplicating output files..."

    for f in "$COLLECTION_DIR"/custom-*.cfg; do
        [[ -f "$f" ]] || continue
        sort -u "$f" -o "$f"
    done

    # =================================================
    # SUMMARY
    # =================================================
    echo ""
    echo "===== GENRE STATS ====="
    for g in "${!GENRE_COUNT[@]}"; do
        printf "%-15s %5d\n" "$g" "${GENRE_COUNT[$g]}"
    done | sort

    echo ""
    echo "Done."
    read -r -p "Press ENTER..."
}

# =====================================================
# ENTRY
# =====================================================
run_engine
