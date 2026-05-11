# ClearPass-MPSK-Update

Ein Bash-Script, mit dem das RADIUS-Attribut Aruba-MPSK-Passphrase in einem ClearPass Enforcement Profile gesetzt werden kann

## Voraussetzungen

- getestet mit Debian 13
- benötigt wird:
  - curl
  - jq

## Konfiguration

### 1. API-Nutzerrolle in ClearPass anlegen

- unter `ClearPass -> Guest -> Verwaltung -> Anwenderanmeldungen -> Profile` ein neues Operator-Profil erstellen
- Konfiguration des Profils:
  - Name: `Enforcement-Profile-API-Admin`
  - Enabled: `ja` (Allow operator logins)
  - Operator Privileges:
    - überall `No Access`, außer bei:
      - API-Dienste: `Custom`
        - `Allow API Access: Allow Access`
      - Policy Manager: `Custom`
        - `Enforcement Profiles: Read, Write`

### 2. API-Nutzer anlegen

- unter `ClearPass -> Guest -> Verwaltung -> API-Dienste` einen neuen API-Client erstellen
- Konfiguration des API-Clients:
  - Client ID: `Endpoint-MPSK-Update` (wird im Script als Variable konfiguriert)
  - Operating Mode: `ClearPass REST API`
  - Operator Profile: `Enforcement-API-Admin`
  - Grant Type: `Client credentials (grant_type=client_credentials)`
  - Client Secret: _von ClearPass generiert_ (wird im Script als Variable konfiguriert)
  - Access Token Lifetime: `1 Minute`

### 3. Zugangsdaten in `update-mpsk.sh` eintragen

```bash
CLEARPASS_API_ROOT="https://clearpass-fqdn-or-ip/api"
CLEARPASS_CLIENT_ID="Endpoint-MPSK-Update" # Name des API-Clients aus 2.
CLEARPASS_CLIENT_SECRET="" # einmalig angezeigtes Secret aus 2.
```

## Nutzung

```bash
./update-mpsk.sh "Name-des-Enforcement-Profile" "Neuer-PSK"
```

Hinweis: der PSK muss mindestens 8 Zeichen lang sein, damit dieser in der Praxis genutzt werden kann. **Das Script und ClearPass validieren dies nicht!**

## Funktionsweise

1. Holt einen Bearer-Token von `POST /api/oauth`
2. Lädt das Enforcement Profile von `GET /api/enforcement-profile/name/{name}`
3. Prüft, ob das Attribut mit `type="Radius:Aruba"` und `name="Aruba-MPSK-Passphrase"` existiert
4. Ersetzt den Wert und sendet das aktualisierte Profil zurück via `PATCH /api/enforcement-profile/name/{name}`

Da die Attribute beim PATCH/PUT ersetzt werden, müssen alle Attribute des Enforcement-Profils zurückgesendet werden.

## Logging

- Alle Meldungen werden in eine Jahres-Logdatei geschrieben: `logs/update-mpsk-2026.log`
- Format: `2026-05-11T12:34:56Z INFO: ...`
- Zusätzlich Ausgabe auf STDERR

## Exit-Codes

- `0` – erfolgreich
- `1` – ungültige Nutzung oder fehlende Abhängigkeiten
- `3` – Token-Anforderung fehlgeschlagen
- `4` – Profil konnte nicht geladen werden
- `5` – kein MPSK-Attribut im Profil gefunden
- `6` – Patch-Update fehlgeschlagen

## Beispiel-Log-Ausgabe

```bash
2026-05-11T12:34:56Z INFO: requesting bearer token...
2026-05-11T12:34:57Z INFO: fetching enforcement profile 'Test-MPSK-Rolle'...
2026-05-11T12:34:58Z INFO: found Aruba-MPSK-Passphrase, updating...
2026-05-11T12:34:58Z INFO: setting Aruba-MPSK-Passphrase to: neuer-psk-wert
2026-05-11T12:34:59Z INFO: enforcement profile 'Test-MPSK-Rolle' updated successfully.
```

## Sicherheitshinweise

- Das Script ignoriert SSL-Zertifikate (`--insecure`)
- Logdateien enhalten den aktuellen und alle vorherigen PSKs
