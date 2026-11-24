#!/bin/zsh
# Tar bort Panel helt. Dina mail, uppgifter och kalendrar rörs inte.
pkill -x Panel 2>/dev/null
rm -rf "$HOME/Applications/Panel.app" "$HOME/Library/LaunchAgents/se.panel.app.plist"
echo "Panel är borttagen. Vill du även ta bort inställningarna: radera ~/Library/Application Support/Panel"
