#!/bin/bash
# Check for new GitHub notifications
NOTIFS=$(gh api notifications --jq '.[0] | "New Activity in \(.repository.full_name): \(.subject.title)"')

if [ ! -z "$NOTIFS" ]; then
  # Tell PicoClaw to send the message to your Telegram
  picoclaw agent -m "Send a Telegram message to me saying: $NOTIFS"
fi
# e.g: check githup activity every 10m
# crontab -e
# */10 * * * * /home/yourusername/git-notify.sh
