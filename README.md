# `zsh-done`

This is a Zshell plug-in to automatically receive notifications after a
long-running process ends.

## Dependencies

* If you want notifications with icons on macOS, install `terminal-notifier`.
* If you are using `swaywm`, install `jq`.

## Settings

### Command duration threshold

```zsh
DONE_MIN_CMD_DURATION=15 # Default: 5
```

### Command deny-list regex

Uses `grep -P` (Perl syntax) to filter out commands that should never notify.

```zsh
DONE_EXCLUDE='^\sgit (?!push|pull|fetch)' # Default: ''
```

### Play a sound when sending notification

When using `terminal-notifier`, play a sound when sending the notification,
otherwise ring the terminal bell.

```zsh
DONE_NOTIFY_SOUND=1 # Default: 0
```

### Notification levels

When using `notify-send` or `notify-desktop`, use a specific urgency level for
your notifications.

```zsh
DONE_NOTIFICATION_URGENCY_LEVEL=low # Default: normal
DONE_NOTIFICATION_URGENCY_LEVEL_FAILURE=normal # Default: critical
```

### Do not show notification for visible windows (`sway` only)

```zsh
DONE_SWAY_IGNORE_VISIBLE=1 # Default: 0
```

### Allow sending notifications on non-graphical systems

This also requires you to define the `done_send_notification` function.

```zsh
DONE_ALLOW_NONGRAPHICAL=1 # Default: 0

done_send_notification() {
    local exit_status="$1"
    local title="$2"
    local message="$3"
    # Use OSC-777 to send a notification (only with compatible terminals)
    echo -ne "\e]777;notify;$title;$message\e\\"
}
```

### Customize the notification texts

You can define `done_format_title` and `done_format_message` to customize the
title and message of your notifications.

```zsh
done_format_title() {
    local exit_status="$1"
    local cmd_duration="$2"
    local last_command="$3"

    if [ "$exit_status" -eq 0 ]; then
        echo "SUCCESS (__done_humanize_duration "$cmd_duration")"
    else
        echo "FAIL (__done_humanize_duration "$cmd_duration")"
    fi
}

done_format_message() {
    local exit_status="$1"
    local cmd_duration="$2"
    local last_command="$3"

    printf '%s (%s)' "$last_command" "$exit_status"
}
```

## More information and alternatives

This plug-in was largely inspired by [the fish package of the same
name](https://github.com/franciscolourenco/done), and steals much of the "is the
shell focused" logic from it.

Unlike the `fish` plug-in, this one does not have support for Windows wired in.

Alternative plug-ins:
* [`zsh-notify`](https://github.com/marzocchi/zsh-notify)
* [`zsh-background-notify`](https://github.com/t413/zsh-background-notify)
