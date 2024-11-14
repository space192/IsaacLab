#!/usr/bin/env bash

dbus-daemon --config-file=/usr/share/dbus-1/system.conf --nofork --nopidfile &
dbus_pid=$!
echo "$(dbus-launch)" > /tmp/.dbus-desktop-session.env
export $(cat /tmp/.dbus-desktop-session.env)


wait "$dbus_pid"