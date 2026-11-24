# Panel

För musen upp till kameran, så fälls en panel ner med dina senaste mail, Slack, deadlines och att göra.
På Mac mini (ingen kamera i skärmen) för du musen till mitten av skärmens överkant.

Första installationen ger också Macen det ljusa utseendet: mjuk ljus bakgrund och en Docka som syns
längst ner med bara dina egna appar. Widgetar lägger du till som vanligt (högerklicka på skrivbordet →
Redigera widgetar…).

Allt annat på Macen fungerar som vanligt. Menyraden, Docken, Spotlight och Kontrollcenter rörs inte,
och panelen lägger sig under menyraden.

## Installera (gör det på båda Macarna)

Öppna **Terminal** (Cmd + mellanslag, skriv Terminal) och klistra in:

```
git clone https://github.com/frodelisi/panel ~/Panel && ~/Panel/installera.command
```

- Första gången kan Macen behöva Apples utvecklarverktyg. En ruta öppnas: tryck Installera,
  vänta tills det är klart och klistra in raden igen.
- Panel startar och inställningarna öppnas. Sedan når du dem med reglageknappen i panelen.
- Panel startar av sig själv när du loggar in, och **hämtar nya versioner själv** en gång i timmen.
  Låt mappen `~/Panel` ligga kvar.

Om bygget misslyckas skapas filen `~/Panel/build-fel.txt`. Skicka den till Claude.

## Koppla in dina saker (en gång)

**Gmail och inbjudningar** – när du lagt till Google-konton (se nedan) visas de viktigaste mailen från
alla konton (Gmails egen "viktigt"-markering i Primär), och kalenderinbjudningar du inte svarat på, med
Ja / Kanske / Nej. Klick på ett mail öppnar det i Gmail i rätt konto. Utan Google-konto läses Mail-appen.

**Mail-appen (om inget Google-konto)** – läses från Mail-appen. Se till att ditt mailkonto finns i Mail. Första gången frågar macOS
om Panel får styra Mail: svara OK. Klickar du på ett mail öppnas det i Mail.

**Deadlines** – läses från Kalender-appen. Lägg till ditt Google-konto i Systeminställningar →
Internetkonton och slå på Kalendrar. Svara OK när macOS frågar om Panel får se kalendern.

**Google Tasks** – kräver en egen nyckel från Google (gratis, cirka 5 minuter):
1. Gå till console.cloud.google.com och skapa ett projekt (t.ex. "Panel").
2. Aktivera tre API:er (sök upp dem och tryck Aktivera): **Google Tasks API**, **Gmail API** och **Google Calendar API**.
3. Under **OAuth-samtyckesskärm**: välj Extern, fyll i namn och din e-post, lägg till dig själv som testanvändare.
   Byt sedan publiceringsstatus till **I produktion**. Annars loggas du ut efter 7 dagar.
4. Under **Inloggningsuppgifter**: Skapa → OAuth-klient-ID → Typ: **Skrivbordsapp**.
5. Kopiera Client ID och Client secret in i Panels inställningar och tryck **Lägg till Google-konto**.
   Gör det en gång per konto (t.ex. privat och jobb). Välj sedan vilket konto att göra-listan ligger i.
   Google varnar att appen inte är verifierad. Det är din egen app, så tryck Avancerat → Fortsätt.

**Slack** – kräver en token:
1. Gå till api.slack.com/apps → Create New App → From scratch, välj ditt Slack.
2. OAuth & Permissions → **User Token Scopes** → lägg till `search:read`.
3. Install to Workspace. Kopiera **User OAuth Token** (börjar med `xoxp-`) in i Panels inställningar → Spara.

## Ändra panelen

**Kugghjulet** öppnar chatten med Claude. Skriv vad du vill ändra, så lägger Claude upp en ny version här,
och panelen hämtar den själv inom en timme (eller direkt med "Sök efter ny version nu" i inställningarna).

**Reglagen** (knappen bredvid kugghjulet) öppnar inställningarna, där du kopplar konton och kan ändra själv:
- slå på och av delar, byt namn, ändra ordning och hur många rader som visas
- lägg till **Genvägar** (webbsidor eller appar) och **Anteckningar**
- **Väder** (välj stad) och **Musik** (Spotify eller Musik-appen, med spela/pausa/nästa)
- ljus eller mörk panel, hur många dagar framåt deadlines visas, och ord som döljer kalenderhändelser
- **viktigaste mailen**: olästa, flaggade och avsändare du väljer kommer först; kvitton, nyhetsbrev och no-reply sorteras bort

Alla val sparas i `~/Library/Application Support/Panel/config.json`. Nycklar och tokens sparas i
`secrets.json` i samma mapp, som bara ditt konto på Macen kan läsa (inte i nyckelringen, som annars
frågar om lösenord efter varje uppdatering).


## Ta bort

Kör `~/Panel/avinstallera.command`. Bakgrunden och Docken blir som de var innan.
