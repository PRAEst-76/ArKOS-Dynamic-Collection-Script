#!/usr/bin/env bash

set -o pipefail

APP_NAME="esdynocol"

# =====================================================
# CONFIG LAYER
# =====================================================
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$APP_NAME"

if [[ ! -d "$CONFIG_DIR" ]]; then
    CONFIG_DIR="$HOME/.esdynocol"
fi

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
INSTALL_MODE=0

# =====================================================
# ARG PARSER
# =====================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --diff) DIFF_MODE=1; shift ;;
        --show-ignored) SHOW_IGNORED=1; shift ;;
        --install) INSTALL_MODE=1; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# =====================================================
# INSTALL MODE
# =====================================================
install_tool() {

    echo "Installing $APP_NAME..."

    mkdir -p "$CONFIG_DIR"

    # create default configs
    [[ ! -f "$MAP_FILE" ]] && cat > "$MAP_FILE" << 'EOF'
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

    [[ ! -f "$WHITELIST_FILE" ]] && cat > "$WHITELIST_FILE" << 'EOF'
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

    [[ ! -f "$CACHE_FILE" ]] && touch "$CACHE_FILE"

    echo "Config created at: $CONFIG_DIR"

    echo ""
    echo "Optional: install auto-run on boot? (y/n)"
    read -r ans
    if [[ "$ans" == "y" ]]; then
        CRON_CMD="@reboot $PWD/esdynocol.sh >/dev/null 2>&1"
        (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
        echo "Installed boot autostart via cron."
    fi

    exit 0
}

# run install if requested
[[ "$INSTALL_MODE" -eq 1 ]] && install_tool

# =====================================================
# STARTUP MESSAGE
# =====================================================
echo "======================================"
echo "esdynocol - EmulationStation DynaCol"
echo "======================================"
echo "Config: $CONFIG_DIR"
echo "Mode: $( [[ $DRY_RUN -eq 1 ]] && echo DRY-RUN || echo NORMAL )"
echo "Diff: $( [[ $DIFF_MODE -eq 1 ]] && echo ON || echo OFF )"
echo "Ignored logging: $( [[ $SHOW_IGNORED -eq 1 ]] && echo ON || echo OFF )"
echo "======================================"

# =====================================================
# HELPERS
# =====================================================
trim() {
    local var="$1"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

decode_xml() {
    local s="$1"
    s=$(echo "$s" | sed "s/&apos;/'/g; s/&amp;/\&/g")
    echo "$s"
}

# =====================================================
# LOAD CONFIGS
# =====================================================
declare -A GENRE_MAP

while IFS="=" read -r key value; do
    key=$(trim "$key")
    value=$(trim "$value")
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    key=$(echo "$key" | tr '[:upper:]' '[:lower:]')
    GENRE_MAP["$key"]="$value"
done < "$MAP_FILE"

mapfile -t WHITELIST < "$WHITELIST_FILE"

is_allowed() {
    local g="$1"
    for w in "${WHITELIST[@]}"; do
        [[ "$g" == "$w" ]] && return 0
    done
    return 1
}

normalize_genre() {
    local input="$1"
    input=$(echo "$input" | tr '[:upper:]' '[:lower:]')

    for key in "${!GENRE_MAP[@]}"; do
        [[ "$input" == *"$key"* ]] && {
            echo "${GENRE_MAP[$key]}"
            return 0
        }
    done

    return 1
}

# =====================================================
# MAIN ENGINE
# =====================================================
declare -A GENRE_COUNT
declare -A IGNORED_UNMAPPED
declare -A IGNORED_BLOCKED

mkdir -p "$COLLECTION_DIR"
touch "$CACHE_FILE"

echo "Scanning gamelist.xml..."

while IFS= read -r gamelist; do

    current_hash=$(md5sum "$gamelist" | awk '{print $1}')
    cached_hash=$(grep "^$gamelist|" "$CACHE_FILE" | cut -d'|' -f2)

    if [[ "$current_hash" == "$cached_hash" && "$DRY_RUN" -eq 0 && "$DIFF_MODE" -eq 0 ]]; then
        echo "Skipping: $gamelist"
        continue
    fi

    echo "Processing: $gamelist"

    SYSTEM_DIR=$(dirname "$gamelist")

    TMP_OUTPUT=$(mktemp)

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

            if [[ -z "$g" ]]; then
                [[ "$SHOW_IGNORED" -eq 1 ]] && IGNORED_UNMAPPED["$raw"]=$(( ${IGNORED_UNMAPPED["$raw"]:-0} + 1 ))
                continue
            fi

            if ! is_allowed "$g"; then
                [[ "$SHOW_IGNORED" -eq 1 ]] && IGNORED_BLOCKED["$g"]=$(( ${IGNORED_BLOCKED["$g"]:-0} + 1 ))
                continue
            fi

            if [[ "$DRY_RUN" -eq 1 ]]; then
                echo "[DRY] $g -> $FULL_PATH"
                continue
            fi

            if [[ "$DIFF_MODE" -eq 1 ]]; then
                echo "$FULL_PATH" >> "$TMP_OUTPUT"
                continue
            fi

            echo "$FULL_PATH" >> "$COLLECTION_DIR/custom-$g.cfg"
            GENRE_COUNT["$g"]=$(( ${GENRE_COUNT["$g"]:-0} + 1 ))

        done

    done < <(
        xmlstarlet sel -t -m "//game[genre]" \
        -v "concat(path,'|',genre)" -n "$gamelist" 2>/dev/null
    )

    # cache update
    if [[ "$DRY_RUN" -eq 0 && "$DIFF_MODE" -eq 0 ]]; then
        grep -v "^$gamelist|" "$CACHE_FILE" > "$CACHE_FILE.tmp" 2>/dev/null || true
        mv "$CACHE_FILE.tmp" "$CACHE_FILE"
        echo "$gamelist|$current_hash" >> "$CACHE_FILE"
    fi

done < <(find "$ROM_ROOT" -type f -name "gamelist.xml")

# =====================================================
# REPORTING
# =====================================================
echo ""
echo "========== SUMMARY =========="
for g in "${!GENRE_COUNT[@]}"; do
    printf "%-15s %5d\n" "$g" "${GENRE_COUNT[$g]}"
done | sort

if [[ "$SHOW_IGNORED" -eq 1 ]]; then
    echo ""
    echo "========== IGNORED =========="
    echo "-- Unmapped --"
    for k in "${!IGNORED_UNMAPPED[@]}"; do
        printf "%-30s %5d\n" "$k" "${IGNORED_UNMAPPED[$k]}"
    done | sort

    echo ""
    echo "-- Blocked --"
    for k in "${!IGNORED_BLOCKED[@]}"; do
        printf "%-30s %5d\n" "$k" "${IGNORED_BLOCKED[$k]}"
    done | sort
fi

echo ""
echo "Done."
