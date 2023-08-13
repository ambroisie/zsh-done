# I don't care about masking `local` return value
# shellcheck disable=2155

# Exit early if non-interactive
[[ -o interactive ]] || return

if [ -z "$SSH_CLIENT" ]; then
    : # Keep executing if we're graphical
elif [ "${DONE_ALLOW_NONGRAPHICAL:-0}" -ne 0 ] && (( ${+functions[done_send_notification]} )); then
    : # Or if the user really wants us to
else
    # Exit early otherwise
    return
fi

: "${DONE_MIN_CMD_DURATION=5}"
: "${DONE_EXCLUDE=}"
: "${DONE_NOTIFY_SOUND=0}"
: "${DONE_NOTIFICATION_URGENCY_LEVEL=normal}"
: "${DONE_NOTIFICATION_URGENCY_LEVEL_FAILURE=critical}"
: "${DONE_SWAY_IGNORE_VISIBLE=0}"
# functions: done_format_title, done_format_message, done_send_notification

# EPOCHSECONDS is faster than using `date`
zmodload zsh/datetime
# Necessary to add the hooks
autoload -U add-zsh-hook

__done_get_focused_window_id() {
    if (( ${+commands[lsappinfo]} )); then
        lsappinfo info -only bundleID "$(lsappinfo front)" | cut -d '"' -f4
    elif [ -n "$SWAYSOCK" ] && (( ${+commands[jq]} )); then
        swaymsg --type get_tree | jq '.. | objects | select(.focused == true) | .id'
    elif [ "$XDG_SESSION_DESKTOP" = gnome ] && (( ${+commands[gdbus]} )); then
        gdbus call \
            --session \
            --dest org.gnome.Shell \
            --object-path /org/gnome/Shell \
            --method org.gnome.Shell.Eval 'global.display.focus_window.get_id()'
    elif (( ${+commands[xprop]} )) && [ -n "$DISPLAY" ] && xprop -grammar &>/dev/null; then
        xprop -root 32x '\t$0' _NET_ACTIVE_WINDOW | cut -f 2
    fi
}

__done_is_tmux_window_active() {
    local pid="$$"
    local tmux_pid

    while true; do
        tmux_pid="$(ps -o ppid= -p "$pid")"
        tmux_pid="$((tmux_pid))" # Trick to get rid of whitespace from `ps` output
        # Stop once `tmux_pid` is actually tmux
        case "$(basename "$(ps -o command= -p "$tmux_pid")")" in
            tmux*) break ;;
        esac
        pid="$tmux_pid"
    done

    # Window is considered active only if the session is attached
    tmux list-panes -a -F "#{session_attached} #{window_active} #{pane_pid}" |
        grep -q "1 1 $pid"
}
__done_is_screen_window_active() {
    screen -ls | grep -q -E "$STY\s+\(Attached"
}

__done_is_process_window_focused() {
    # Send notification for every command in non-graphical environment
    if [ "$DONE_ALLOW_NONGRAPHICAL" -ne 0 ]; then
        return 1
    fi

    local current_window_id="$(__done_get_focused_window_id)"
    if [ "$DONE_SWAY_IGNORE_VISIBLE" -ne 0 ] &&
        [ -n "$SWAYSOCK" ] &&
        (( ${+commands[jq]} )); then
        local is_visible="$(swaymsg -t get_tree | jq ".. | objects | select(.id == $__done_initial_window_id) | .visible")"
        [ "$is_visible" = "true" ]
        return $?
    elif [ "$current_window_id" != "$__done_initial_window_id" ]; then
        return 1
    fi

    if (( ${+commands[tmux]} )) && [ -n "$TMUX" ]; then
        __done_is_tmux_window_active
        return $?
    fi
    if (( ${+commands[screen]} )) && [ -n "$STY" ]; then
        __done_is_screen_window_active
        return $?
    fi

    return 0
}

__done_humanize_duration() {
    local seconds=$(($1 % 60))
    local minutes=$(($1 / 60))
    local hours=$(($1 / 60 / 60))

    if [ "$hours" -gt 0 ]; then
        printf '%sh ' "$hours"
    fi
    if [ "$minutes" -gt 0 ]; then
        printf '%sm ' "$minutes"
    fi
    if [ "$seconds" -gt 0 ]; then
        printf '%ss' "$seconds"
    fi
}

__done_do_bell() {
    if [ "$DONE_NOTIFY_SOUND" -ne 0 ]; then
        printf "\a"
    fi
}

__done_is_ignored_command() {
    if [ -z "$DONE_EXCLUDE" ]; then
        return 1
    fi
    # shellcheck disable=2154
    printf '%s' "$__done_last_command" | grep -q -v -P "$DONE_EXCLUDE"
}

__done_notify() {
    local exit_status="$1"
    local title="$2"
    local message="$3"

    if (( ${+functions[done_send_notification]} )); then
        done_send_notification "$exit_status" "$title" "$message"
        __done_do_bell
    elif (( ${+commands[terminal-notifier]} )); then
        local sound=()

        if [ "$DONE_NOTIFY_SOUND" -ne 0 ]; then
            sound=(-sound default)
        fi

        terminal-notifier \
            -message "$message" \
            -title "$title" \
            -sender "$__done_initial_window_id" \
            "${sound[@]}"
    elif (( ${+commands[osascript]} )); then
        osascript -e "display notification \"$message\" with title \"$title\""
        __done_do_bell
    elif (( ${+commands[notify-send]} )); then
        local urgency="${DONE_NOTIFICATION_URGENCY_LEVEL}"

        if [ "$exit_status" -ne 0 ]; then
            urgency="${DONE_NOTIFICATION_URGENCY_LEVEL_FAILURE}"
        fi

        notify-send \
            --hint=int:transient:1 \
            --urgency="$urgency" \
            --icon=utilities-terminal \
            --app-name=zsh \
            "$title" "$message"
        __done_do_bell
    elif (( ${+commands[notify-desktop]} )); then
        local urgency="${DONE_NOTIFICATION_URGENCY_LEVEL}"

        if [ "$exit_status" -ne 0 ]; then
            urgency="${DONE_NOTIFICATION_URGENCY_LEVEL_FAILURE}"
        fi

        notify-desktop \
            --urgency="$urgency" \
            --icon=utilities-terminal \
            --app-name=zsh \
            "$title" "$message"
        __done_do_bell
    else
        # Fallback to bell when nothing else is available
        printf "\a"
    fi
}

__done_format_title() {
    local exit_status="$1"
    local cmd_duration="$2"
    local last_command="$3"

    if (( ${+functions[done_format_title]} )); then
        done_format_title "$exit_status" "$cmd_duration" "$last_command"
    else
        local humanized_duration="$(__done_humanize_duration "$cmd_duration")"
        local title="Done in $humanized_duration"
        if [ "$exit_status" -ne 0 ]; then
            title="Failed ($exit_status) after $humanized_duration"
        fi
        printf '%s' "$title"
    fi
}

__done_format_message() {
    local exit_status="$1"
    local cmd_duration="$2"
    local last_command="$3"

    if (( ${+functions[done_format_message]} )); then
        done_format_message "$exit_status" "$cmd_duration" "$last_command"
    else
        local wd="${PWD/$HOME/~}"
        local message="$wd/ $last_command"
        printf '%s' "$message"
    fi
}

__done_started() {
    __done_initial_window_id="$(__done_get_focused_window_id)"
    __done_timestamp="$EPOCHSECONDS"
    __done_last_command="${1:-$2}"
}
add-zsh-hook preexec __done_started

__done_ended() {
    : "${__done_timestamp:=$EPOCHSECONDS}" # fix the value on first source
    local exit_status="$?"
    local cmd_duration=$((EPOCHSECONDS - __done_timestamp))

    if [ "$cmd_duration" -gt "$DONE_MIN_CMD_DURATION" ] &&
        ! __done_is_process_window_focused &&
        ! __done_is_ignored_command; then
        local format_args=("$exit_status" "$cmd_duration" "$__done_last_command")

        local title="$(__done_format_title "${format_args[@]}")"
        local message="$(__done_format_message "${format_args[@]}")"

        __done_notify "$exit_status" "$title" "$message"
    fi
}
add-zsh-hook precmd __done_ended
