#!/bin/bash

STATE_FILE="/tmp/hypr_keyboard_layout"

if [ -f "$STATE_FILE" ]; then
  layout=$(cat "$STATE_FILE")
else
  layout="us"
fi

case "$layout" in
  us) echo "EN" ;;
  ru) echo "RU" ;;
  *) echo "?" ;;
esac
