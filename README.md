# BluVolume

Een iPhone-app om het volume van een BluOS-speler (zoals de NAD/Bluesound **Powernode**)
in te stellen met een **draaiknop**, net als in de Denon-app.

Voor de hele schaal van 0 tot 100 % draai je de knop een paar keer rond (standaard 4 keer).
Elke procent kost dan ongeveer 14°, dus 7, 8 of 9 % stel je precies in.

## Functies

- Draaiknop met een tik (haptische feedback) bij elke procent en een stevigere tik bij 0 % en bij het maximum
- Instelbare gevoeligheid: 1 tot 10 omwentelingen voor de hele schaal
- **Maximaal volume** als veiligheidsgrens, zodat je niet per ongeluk te hard zet
- −/+ knoppen voor precies één procent, en een dempknop
- Spelers worden automatisch gevonden via Bonjour. Je kunt ook zelf een IP-adres invullen.
- Volgt wijzigingen van buitenaf (BluOS-app, Spotify, afstandsbediening) via long-polling

## Op je iPhone zetten

Je hebt een Mac met **Xcode 16 of nieuwer** nodig. Een gratis Apple ID is genoeg.

1. Open `BluVolume.xcodeproj` in Xcode.
2. Kies het project in de linkerkolom, dan target **BluVolume** › **Signing & Capabilities**.
   Kies bij *Team* je Apple ID. Voeg die eerst toe via Xcode › Settings › Accounts als hij er nog niet staat.
   Krijg je een fout over de *Bundle Identifier*? Verander die dan in iets unieks.
3. Sluit je iPhone aan en kies hem bovenin als doel.
   Zet op de iPhone **Instellingen › Privacy en beveiliging › Ontwikkelaarsmodus** aan als daarom gevraagd wordt.
4. Druk op ▶︎ (Run).
   Ga de eerste keer op de iPhone naar **Instellingen › Algemeen › VPN en apparaatbeheer** en vertrouw je ontwikkelaarscertificaat.
5. Sta **Lokaal netwerk** toe als de app daarom vraagt. Zonder die toestemming kan de app de Powernode niet bereiken.

> Met een gratis Apple ID blijft de app 7 dagen werken. Daarna druk je in Xcode gewoon weer op Run.
> Met een betaald Apple Developer-account (€ 99/jaar) is dat een jaar.

## Hoe het werkt

BluOS-spelers hebben een eenvoudige HTTP-API op poort 11000:

| Verzoek | Doet |
|---|---|
| `GET /Volume` | huidig volume opvragen |
| `GET /Volume?level=8` | volume op 8 % zetten |
| `GET /Volume?mute=1` | dempen |
| `GET /Volume?timeout=60&etag=…` | wachten tot het volume ergens anders verandert |

## Bestanden

| Bestand | Inhoud |
|---|---|
| `BluVolume/VolumeKnob.swift` | De draaiknop: gebaar, weergave en haptiek |
| `BluVolume/KnobSensitivity.swift` | Rekent draaihoek om naar volumeverandering |
| `BluVolume/VolumeModel.swift` | Synchronisatie met de speler |
| `BluVolume/BluOSClient.swift` | HTTP/XML-communicatie met BluOS |
| `BluVolume/PlayerDiscovery.swift` | Bonjour-zoeker (`_musc._tcp`) |
| `BluVolume/ContentView.swift`, `SettingsView.swift` | Schermen |
