#!/bin/zsh
# Öppnar Skola24-fönstret igen (om det inte redan är öppet). Logga in där och öppna ditt schema, minimera sedan.
launchctl kickstart -k gui/$UID/se.panel.skola24 2>/dev/null || ~/Panel/dashboard/skola24/installera-skola24.command
echo "Skola24-fönstret öppnas. Logga in, öppna ditt schema och minimera fönstret (stäng det inte)."
