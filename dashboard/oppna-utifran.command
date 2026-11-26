#!/bin/zsh
# Gör dashboarden nåbar utifrån (skoldatorn, mobilen på 4G) via Tailscale Funnel, med en säker https-adress.
# Kräver appen Tailscale på DEN HÄR datorn (Mac minin), inloggad. Inget behöver installeras där du öppnar den.
# Stäng av igen med:  ~/Panel/dashboard/oppna-utifran.command av
TS="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
[ -x "$TS" ] || TS="$(command -v tailscale)"
if [ -z "$TS" ] || [ ! -x "$TS" ]; then
  echo "Tailscale saknas. Installera appen Tailscale (tailscale.com/download eller App Store),"
  echo "logga in i den och kör det här skriptet igen."
  open "https://tailscale.com/download/mac"
  exit 1
fi

if [ "$1" = "av" ]; then
  "$TS" funnel --https=443 off && echo "Dashboarden går inte längre att nå utifrån."
  exit 0
fi

PW="$HOME/Library/Application Support/Panel/dashboard/losenord"
if [ ! -s "$PW" ]; then echo "Kör installera-dashboard.command först."; exit 1; fi
if [ "$(wc -c < "$PW" | tr -d ' ')" -lt 13 ]; then
  echo "Lösenordet är för kort för att öppna dashboarden mot internet (minst 12 tecken)."
  echo "Kör ~/Panel/dashboard/installera-dashboard.command och välj ett längre, kör sedan det här igen."
  exit 1
fi

echo "Öppnar dashboarden utifrån…"
echo "(Första gången kan Tailscale visa en länk för att slå på Funnel – öppna den, godkänn och kör skriptet igen.)"
"$TS" funnel --bg 8765 || exit 1
echo ""
"$TS" funnel status
echo ""
echo "Klart! Adressen ovan (https://…ts.net) fungerar i vilken webbläsare som helst."
echo "Logga in med dashboardens lösenord. Efter 8 felaktiga försök spärras inloggningen i 15 minuter."
echo "På skoldatorn: använd ett privat fönster och spara inte lösenordet."
