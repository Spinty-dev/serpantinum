#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == */* ]]; then
    SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd -P)"
else
    SCRIPT_DIR="$(pwd -P)"
fi

source "$SCRIPT_DIR/caching.sh" 2>/dev/null || true
source "$SCRIPT_DIR/config.sh" 2>/dev/null || true
source "$SCRIPT_DIR/i18n.sh" 2>/dev/null || true

show_help() {
    echo "Usage: serpantinum autostart [OPTIONS]"
    echo ""
    echo "Execute user-configured autostart applications and background services."
    echo ""
    echo "Options:"
    echo "  -v, --verbose    Enable verbose logging"
    echo "  -h, --help       Show this help message"
}

VERBOSE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

if [ "$SERPANTINUM_VERBOSE" = true ]; then
    VERBOSE=true
fi

_config_ensure_settings

STATUS_DIR="${QS_RUN_DIR:-${XDG_RUNTIME_DIR:-/tmp}/serpantinum}/autostart"
mkdir -p "$STATUS_DIR" 2>/dev/null || true

is_enabled="$(jq -r 'if .autostart and (.autostart.enabled != null) then .autostart.enabled else true end' "$CONFIG_SETTINGS_JSON" 2>/dev/null)"
if [ "$is_enabled" = "false" ]; then
    [ "$VERBOSE" = true ] && echo "[autostart] Autostart is disabled in settings."
    exit 0
fi

entries_count="$(jq -r 'if .autostart and .autostart.entries then (.autostart.entries | length) else 0 end' "$CONFIG_SETTINGS_JSON" 2>/dev/null)"
if [ -z "$entries_count" ] || [ "$entries_count" -le 0 ]; then
    [ "$VERBOSE" = true ] && echo "[autostart] No autostart entries configured."
    exit 0
fi

[ "$VERBOSE" = true ] && echo "[autostart] Found $entries_count entries. Spawning startup tasks..."

check_condition() {
    local cond="$1"
    case "$cond" in
        "ac_only")
            if ls /sys/class/power_supply/*/online 1>/dev/null 2>&1; then
                for f in /sys/class/power_supply/*/online; do
                    if [ "$(cat "$f" 2>/dev/null)" = "1" ]; then
                        return 0
                    fi
                done
                return 1
            fi
            return 0
            ;;
        "battery_only")
            if ls /sys/class/power_supply/BAT* 1>/dev/null 2>&1; then
                for f in /sys/class/power_supply/*/online; do
                    if [ "$(cat "$f" 2>/dev/null)" = "1" ]; then
                        return 1
                    fi
                done
                return 0
            fi
            return 1
            ;;
        "multi_monitor")
            local mon_count=0
            if [ -f "$SCRIPT_DIR/monitors_detect.sh" ]; then
                mon_count="$(bash "$SCRIPT_DIR/monitors_detect.sh" 2>/dev/null | grep -c . || echo 0)"
            elif command -v serpantinum &>/dev/null; then
                mon_count="$(serpantinum monitors_detect 2>/dev/null | grep -c . || echo 0)"
            fi
            (( mon_count > 1 )) && return 0
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

write_status() {
    local id="$1" st="$2" code="$3"
    printf '{"status":"%s","exitCode":%d,"timestamp":%d,"pid":%d}\n' \
        "$st" "$code" "$(date +%s)" "$$" > "$STATUS_DIR/${id}.json" 2>/dev/null || true
}

run_task() {
    local id="$1" exec_cmd="$2" restart="$3" ws="$4" silent="$5"
    local final_cmd="$exec_cmd"

    if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && command -v hyprctl &>/dev/null && { { [ -n "$ws" ] && [ "$ws" != "0" ]; } || [ "$silent" = "true" ]; }; then
        local rules="["
        [ -n "$ws" ] && [ "$ws" != "0" ] && rules+="workspace $ws "
        [ "$silent" = "true" ] && rules+="silent "
        rules="${rules% }]"
        final_cmd="hyprctl dispatch 'hl.dsp.exec_cmd(\"$rules $exec_cmd\")' 2>/dev/null || hyprctl dispatch exec \"$rules $exec_cmd\""
    fi

    write_status "$id" "running" 0

    if [ "$restart" = "true" ]; then
        while true; do
            write_status "$id" "running" 0
            eval "$final_cmd" > "$STATUS_DIR/${id}.log" 2>&1
            local exit_code=$?
            if [ $exit_code -eq 0 ]; then
                write_status "$id" "success" 0
                break
            else
                write_status "$id" "failed" "$exit_code"
                [ "$VERBOSE" = true ] && echo "[autostart] Task '$id' crashed with exit code $exit_code, restarting in 2s..."
                sleep 2
            fi
        done
    else
        eval "$final_cmd" > "$STATUS_DIR/${id}.log" 2>&1
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            write_status "$id" "success" 0
        else
            write_status "$id" "failed" "$exit_code"
        fi
    fi
}

for ((i = 0; i < entries_count; i++)); do
    entry="$(jq -c --argjson idx "$i" '.autostart.entries[$idx]' "$CONFIG_SETTINGS_JSON" 2>/dev/null)"
    [ -z "$entry" ] && continue

    entry_enabled="$(printf '%s' "$entry" | jq -r 'if .enabled != null then .enabled else true end')"
    [ "$entry_enabled" != "true" ] && continue

    entry_exec="$(printf '%s' "$entry" | jq -r '.exec // empty')"
    [ -z "$entry_exec" ] && continue

    entry_id="$(printf '%s' "$entry" | jq -r '.id // empty')"
    entry_id="${entry_id:-auto_entry_$i}"
    entry_name="$(printf '%s' "$entry" | jq -r '.name // empty')"
    entry_delay="$(printf '%s' "$entry" | jq -r '.delay // 0')"
    entry_count="$(printf '%s' "$entry" | jq -r '.count // 1')"
    entry_repeat_delay="$(printf '%s' "$entry" | jq -r '.repeatDelay // .repeat_delay // .interval // 0')"
    entry_workspace="$(printf '%s' "$entry" | jq -r '.workspace // empty')"
    entry_silent="$(printf '%s' "$entry" | jq -r '.silent // false')"
    entry_condition="$(printf '%s' "$entry" | jq -r '.condition // "always"')"
    entry_restart="$(printf '%s' "$entry" | jq -r '.restartOnCrash // false')"

    # Validate numeric parameters
    [[ "$entry_delay" =~ ^[0-9]+$ ]] || entry_delay=0
    [[ "$entry_count" =~ ^[0-9]+$ ]] || entry_count=1
    [[ "$entry_repeat_delay" =~ ^[0-9]+$ ]] || entry_repeat_delay=0
    (( entry_count < 1 )) && entry_count=1

    # Check power / monitor execution condition
    if ! check_condition "$entry_condition"; then
        [ "$VERBOSE" = true ] && echo "[autostart] Skipping '$entry_name' ($entry_id): condition '$entry_condition' not met."
        continue
    fi

    (
        if (( entry_delay > 0 )); then
            [ "$VERBOSE" = true ] && echo "[autostart] Waiting ${entry_delay}s for '$entry_name' ($entry_exec)..."
            sleep "$entry_delay"
        fi

        for ((c = 0; c < entry_count; c++)); do
            if (( c > 0 && entry_repeat_delay > 0 )); then
                [ "$VERBOSE" = true ] && echo "[autostart] Waiting ${entry_repeat_delay}s before repeat $((c + 1))/$entry_count..."
                sleep "$entry_repeat_delay"
            fi
            [ "$VERBOSE" = true ] && echo "[autostart] Executing instance $((c + 1))/$entry_count: $entry_exec"
            run_task "$entry_id" "$entry_exec" "$entry_restart" "$entry_workspace" "$entry_silent" &
        done
    ) &
done

exit 0
