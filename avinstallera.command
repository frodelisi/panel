#!/bin/zsh
# Tar bort Panel och gör bakgrunden och Docken som de var innan. Dina mail, uppgifter och kalendrar rörs inte.
SUPPORT="$HOME/Library/Application Support/Panel"
pkill -x Panel 2>/dev/null
rm -rf "$HOME/Applications/Panel.app" "$HOME/Library/LaunchAgents/se.panel.app.plist"
if [ -d "$SUPPORT/backup" ]; then
  [ -f "$SUPPORT/backup/dock.plist" ] && defaults import com.apple.dock "$SUPPORT/backup/dock.plist" && killall Dock
  [ -s "$SUPPORT/backup/bakgrund.txt" ] && osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$(cat "$SUPPORT/backup/bakgrund.txt")\""
  defaults delete com.apple.WindowManager EnableStandardClickToShowDesktop 2>/dev/null
  rm -rf "$SUPPORT/backup"
fi
echo "Panel är borttagen och bakgrunden och Docken är som förut."
echo "Inställningarna ligger kvar i ~/Library/Application Support/Panel (radera mappen om du vill)."
