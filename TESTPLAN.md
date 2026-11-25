# Handmatig testplan: Tailscale- en RD Gateway-routes

**Voorbereiding:**
- Alleen `RDCManagerX.exe` is nodig: `tsbridge.dll` zit erin en wordt uitgepakt naar
  `%LOCALAPPDATA%\RDCManagerX\bin\`.
- Start de app met `/debuglog`, zodat je bij problemen de logs hebt (`%LOCALAPPDATA%\RDCManagerX\`).
- Zet *Wachtwoorden onthouden* aan (Bestand > Opties) en stel een hoofdwachtwoord in. Dat is nodig voor
  opgeslagen auth keys en wachtwoorden, en voor niet-ephemeral netwerken.

**Op de doel-pc(s):**
- Tailscale draait;
- RDP staat aan;
- de firewall staat TCP 3389 toe vanaf `100.64.0.0/10`.

Noteer bij elke test: **OK / NIET OK**, en bij een fout de melding en het tijdstip.

---

## 1. Direct verbinden (regressie)

1. Open een bestaand `.rdg` met servers die je nu ook gebruikt.
2. Verbind met een paar servers, waaronder één met de gateway-instellingen uit RDCMan (tab *Gateway*), als je die
   hebt.
3. Controleer:
   - verbinden werkt zoals voorheen, inclusief dynamische resolutie;
   - Eigenschappen > Route staat op *Direct*;
   - sla het bestand op en vergelijk het `.rdg` met het origineel: het is ongewijzigd (de nieuwe gegevens staan
     alleen in de sidecar).

## 2. Tailscale met auth key

1. Maak in de Tailscale-adminconsole een auth key: reusable, ephemeral, pre-approved, met tag.
2. Bestand > Tailscale-netwerken > Nieuw: naam "Thuis", auth key plakken, Ephemeral aan.
3. Klik op **Test verbinding**. Verwacht: "Verbonden. Adres in het tailnet: 100.x…", en in de adminconsole verschijnt
   `rdpclient-<pc>` (na de test verdwijnt die weer).
4. Klik op OK. Verwacht: vraag om het hoofdwachtwoord als de kluis vergrendeld is. De lijst toont "in de kluis".
5. Bij een server: Eigenschappen > Route > *Via Tailscale-netwerk*, kies "Thuis". Vul eventueel *Adres in het
   tailnet* in, bijv. `thuis-pc` of `100.x.y.z`.
6. Verbind. Verwacht:
   - de tab toont "Verbinden met Tailscale-netwerk "Thuis"…" en daarna de normale aanmelding;
   - er volgt een certificaatwaarschuwing (naam `127.0.0.2`); accepteer die;
   - de sessie werkt, inclusief formaat wijzigen;
   - de tab en de titel tonen de echte servernaam, niet 127.0.0.2.
7. Sluit de tab. Verwacht: de node verdwijnt na korte tijd uit de adminconsole.
8. Controleer dat de auth key in geen enkel bestand staat: sidecar/`.rdcx`, `settings.json`, `debug.log` en
   `tsbridge-*.log`.

## 3. Tailscale met interactieve login

1. Nieuw netwerk zonder auth key, Ephemeral **uit**.
2. Klik op **Test verbinding**. Verwacht: de login-pagina van Tailscale opent in de browser. Na het inloggen (en zo
   nodig goedkeuren in de console) toont het venster het tailnet-adres.
3. Sluit RDCManagerX, start opnieuw en klik weer op Test verbinding. Verwacht: verbonden **zonder** opnieuw in te
   loggen.
4. Controleer dat `%LOCALAPPDATA%\RDCManagerX\tailscale\<id>\state\state.dpapi` bestaat en geen leesbare tekst bevat.
5. Verbind een server met deze route. Verwacht: dit werkt, zonder browser.

## 4. Twee Tailscale-netwerken tegelijk

1. Twee netwerken met verschillende tailnets (bijv. "Thuis" en "Klant X"), elk met een server.
2. Verbind met beide servers tegelijk. Verwacht: beide sessies werken. In beide tailnets staat een RDCManagerX-node.
3. Verbind een tweede server via hetzelfde netwerk. Verwacht: er start geen tweede node (één `rdpclient-…` in de
   console).
4. Sluit de tabs één voor één. Verwacht: een netwerk sluit pas na de laatste tab die het gebruikt.
5. Twee open bestanden (bijv. Werk en Prive), elk met een eigen netwerk. Verwacht: hetzelfde gedrag.

## 5. RD Gateway met eigen aanmeldgegevens

1. Bestand > RDP-gateways > Nieuw: server en poort, *Gebruiken: Altijd*, *Aanmeldgegevens: Eigen*, gebruiker,
   domein, wachtwoord.
2. Klik op OK. Verwacht: het wachtwoord gaat in de kluis (eventueel vraag om het hoofdwachtwoord). Het staat niet in
   het bestand.
3. Bij een server: Route > *Via RDP-gateway*, kies de gateway. Verbind. Verwacht: verbinding via de gateway, zonder
   vraag om het gateway-wachtwoord.
4. Wis het gateway-wachtwoord (knop *Wissen*, OK) en verbind opnieuw. Verwacht: Windows vraagt het
   gateway-wachtwoord.
5. Herhaal met poort 4443 (als de gateway dat ondersteunt) en met *Altijd behalve voor lokale adressen*.

## 6. RD Gateway met aanmeldgegevens gedeeld met de sessie

1. Gateway met *Aanmeldgegevens: Dezelfde als voor de sessie*.
2. Verbind. Verwacht: één keer aanmelden (sessie-wachtwoord), dat ook voor de gateway geldt.
3. Probeer ook *Vragen bij verbinden* (verwacht: een aparte vraag voor de gateway) en, als je een smartcard hebt,
   *Smartcard*.

## 7. Ingebouwde tsbridge.dll

1. Kopieer alleen `RDCManagerX.exe` naar een lege map (of laat de launcher dat doen) en start hem.
2. Gebruik Tailscale (Test verbinding). Verwacht: dit werkt, en in `%LOCALAPPDATA%\RDCManagerX\bin\` staat
   `tsbridge-<code>.dll`.
3. Sluit RDCManagerX, wijzig of vervang dat bestand (bijv. door een ander bestand met dezelfde naam), en start opnieuw.
   Verwacht: Tailscale werkt gewoon; het bestand is vervangen door de juiste versie.
4. Maak `%LOCALAPPDATA%\RDCManagerX\bin` alleen-lezen of blokkeer het (bijv. een map met die naam als bestand). Verwacht:
   een melding dat de ingebouwde tsbridge.dll niet kon worden uitgepakt; de rest van de app werkt, zonder crash.

## 8. Ongeldige of verlopen auth key

1. Netwerk met een ingetrokken of verlopen auth key (of `tskey-auth-ongeldig`), Ephemeral aan.
2. Klik op **Test verbinding**. Verwacht: binnen redelijke tijd "Niet gelukt: …" met de fout van Tailscale (bijv.
   invalid key). Er komt geen browservenster en er hangt niets.
3. Verbind een server via dit netwerk. Verwacht: de tab blijft open met de foutmelding. *Opnieuw verbinden* (na een
   geldige key) werkt.
4. Klik tijdens "Verbinden met Tailscale-netwerk…" op *Test stoppen* of sluit de tab. Verwacht: het starten wordt
   afgebroken, zonder hangen.

## 9. App afsluiten met open sessies

1. Open sessies via Direct, via Tailscale (twee netwerken) en via de gateway.
2. Sluit RDCManagerX. Verwacht: de vraag "zeker afsluiten (open sessies)". Na Ja sluit de app binnen een paar
   seconden.
3. Verwacht: ephemeral nodes verdwijnen uit de adminconsole. Er blijft geen `RDCManagerX.exe` actief in
   Taakbeheer.
4. Start opnieuw. Verwacht: niet-ephemeral netwerken verbinden zonder opnieuw in te loggen.

## 10. Beveiliging

1. **Tunnel alleen voor RDCManagerX:** zoek tijdens een Tailscale-sessie de lokale poort op (`debug.log`: "forward
   127.0.0.2:<poort>") en probeer vanuit PowerShell `Test-NetConnection 127.0.0.2 -Port <poort>`. Verwacht: de
   verbinding wordt meteen gesloten, en `tsbridge-*.log` toont "geweigerd (niet van RDCManagerX)". De RDP-sessie zelf
   blijft werken.
2. **Doel buiten het tailnet:** zet bij een server *Adres in het tailnet* op `www.example.com` of `8.8.8.8` en
   verbind. Verwacht: de verbinding mislukt, en `tsbridge-*.log` toont "geen apparaat in dit tailnet" of "niet
   bereikbaar via dit tailnet". Het verkeer gaat niet buiten Tailscale om.
3. **Gemanipuleerd bestand:** wijzig in de sidecar of `.rdcx` met de hand `localAddress` naar `0.0.0.0` en
   `controlUrl` naar `http://example.com`. Verwacht: het lokale adres wordt 127.0.0.2, en verbinden geeft een melding
   over de control URL.
4. **Geheim aan server gebonden:** wijzig bij een gateway met opgeslagen wachtwoord de server. Verwacht: de vraag
   "het opgeslagen wachtwoord wordt gewist". Na Ja vraagt verbinden om het wachtwoord.
5. **Andere DLL:** zie test 7.3: een gewijzigde uitgepakte DLL wordt nooit geladen, maar opnieuw uitgepakt. Verwacht
   (als dat niet lukt): melding
   "controlesom klopt niet", Tailscale uitgeschakeld, de rest werkt.

## Extra controles
- **Doel offline:** sluit Tailscale op de doel-pc en verbind. Verwacht direct de melding "<naam> is offline in het tailnet (laatst gezien: …)", geen algemene RDP-fout. Start Tailscale daar weer en kies *Opnieuw verbinden*: werkt.

- **Kluis vergrendeld:** vergrendel de kluis (Bestand > Wachtwoordkluis vergrendelen) en verbind via Tailscale met
  een opgeslagen auth key, of via een gateway met een opgeslagen wachtwoord. Verwacht: vraag om het hoofdwachtwoord.
  Annuleren geeft bij Tailscale een melding in de tab, bij de gateway vraagt Windows het wachtwoord.
- **Opties > Wachtwoorden onthouden uit:** verwacht een vraag. Daarna zijn opgeslagen auth keys en
  gateway-wachtwoorden weg, en moet een niet-ephemeral netwerk opnieuw inloggen.
- **Netwerk of gateway verwijderen** terwijl een route ernaar verwijst: verwacht een weigering met het aantal
  routes.
- **Bestand meenemen naar een andere pc:** de definities zijn er, de geheimen niet. Verwacht: een vraag om de auth
  key, of de browser-login.
