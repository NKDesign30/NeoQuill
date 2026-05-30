# NeoQuill Product Release Plan

Stand: 2026-05-24

## Produktthese

NeoQuill wird als lokale macOS-Meeting-App positioniert: Aufnahme, Transkript, Sprecher, Zusammenfassung und Aufgaben laufen zuerst auf dem Mac. Der Unterschied zu bot-basierten Tools ist Kontrolle: keine Meeting-Bots, lokale Datenhaltung, eigener KI-Provider möglich.

## Professioneller Operating Standard

Spotify-Learning für NeoQuill: Professionelle Produkte gewinnen nicht durch mehr Chaos-Features, sondern durch gemeinsame Plattform-Standards, klare Ownership und reproduzierbare Releases. Für NeoQuill heißt das:

- `dev` ist der Arbeitsstand; `main` ist nur verifizierter Release-Stand.
- Jede App zeigt Version, Build, Branch, Commit, Dirty-State und Build-Datum.
- Jeder Release läuft durch Tests, Bundle-Build, Signaturcheck, ZIP/Manifest,
  signiertes + notarized DMG, EdDSA-signierten Sparkle-Appcast und
  `market-readiness.sh`.
- Kritische Produktpfade haben Regressionstests: Aufnahme, Playback, Transkript, Speaker, Export, Diagnostics.
- Support-Diagnosen bleiben privacy-safe und erklären den Build-Stand ohne Audio-/Transcript-Leak.
- Feature-Entscheidungen folgen dem Local-first-Versprechen: Cloud nur optional, nie heimlich.

Der Maßstab vor Paid Launch: Ein fremder Nutzer kann einen Fehler melden, und wir wissen sofort App-Version, Commit, Build, Signaturstatus und betroffenen Produktpfad.

## Zielkunden

- Freelancer und kleine Agenturen, die Kundengespräche protokollieren.
- Consultants, PMs und Sales-Leute, die keine Bots in Kundencalls wollen.
- Datenschutzsensible Teams, die lokale Speicherung und eigene API-Keys verlangen.

## Release-Reihenfolge

1. Private Alpha: signiertes Direkt-Bundle, 10-20 echte Meetings, Crash-/UX-Feedback.
2. Public Beta: Website-Download, Lizenz-Key, Feedback-Button, klarer Hinweis "local-first".
3. Paid v1 Direct Sale: notarisiertes macOS-Bundle, Stripe/Paddle/Lemon Squeezy, Auto-Updater.
4. Mac App Store danach: StoreKit für Kauf/Abo, Sandboxing/Entitlements prüfen, Review-Material vorbereiten.

## MVP-v1 Scope

Muss drin sein:
- Meeting aufnehmen: Mic + System-Audio mit sauberem Permission-Flow.
- Lokales Transkript mit Speaker-Zuordnung.
- Manuelles Importieren von Teams/Meet/Zoom-Transkripten.
- Export: Markdown, Copy, Share.
- Aufgaben an Neo Inbox oder generischen Webhook schicken.
- Settings für Provider, Datenpfade, Sprache, Modell, Retention.
- Mehrsprachige Meetings über Auto-Detect als Default.

Nicht v1:
- Team-Collaboration.
- Cloud-Sync.
- Mobile-App.
- Enterprise-Admin.

## User-Konfiguration

Settings müssen als normale Produktoberfläche funktionieren, nicht als Entwicklerpanel:

- Recording: Mic, System-Audio-Quelle, Auto-Start/Auto-Stop, Meeting-App-Erkennung.
- Transcription: lokal WhisperKit, lokales Whisper CLI, optional OpenAI-kompatibler STT-Endpunkt.
- Summary/AI: Provider, Modell, Base URL, API-Key, Prompt-Template, Sprache, Output-Format.
- Sprache: Auto-Detect als Default, feste Sprache nur für monolinguale Workflows.
- Speicher: lokaler Datenordner, Aufbewahrungsdauer, Audio nach Transkript löschen.
- Integrationen: Kalender, Neo Inbox, Webhook, Markdown-Ordner, später Notion/Linear/Jira.
- Datenschutz: "nie Cloud nutzen" Hard-Toggle, sichtbarer Datenfluss pro Provider.

API-Keys gehören ausschließlich in Keychain. Settings speichern nur Provider-ID, Base URL, Modellnamen und Feature-Flags.

## AI-Provider-Architektur

Ein gemeinsames Provider-Protokoll reicht für v1:

```swift
protocol MeetingAIProvider {
    var id: String { get }
    var displayName: String { get }
    func summarize(_ input: MeetingAIInput) async throws -> MeetingAIOutput
}
```

Geplante Adapter:
- Local: WhisperKit für STT, Ollama/LM Studio für Summary über lokale OpenAI-kompatible Endpoints.
- OpenAI-compatible: Base URL + API-Key + Model, damit OpenAI, OpenRouter, Groq, Together, lokale Server gehen.
- Anthropic/Gemini später nativ, wenn Prompting/Tooling eigene Vorteile bringt.
- Custom Webhook: POST Meeting JSON, erwartet Summary JSON zurück.

Wichtig: v1 nicht mit fünf nativen SDKs aufblasen. Erst OpenAI-kompatibler Adapter plus Custom Webhook, dann echte Native-Adapter nach Nachfrage.

Aktueller App-Stand:
- Claude CLI ist als Default aktiv und nutzt den lokal eingeloggten Claude-Account.
- OpenAI-kompatible Summary-Provider sind in Settings anschließbar: Base URL, Modell und API-Key in Keychain.
- Native Anthropic/Gemini-Adapter sind bewusst noch nicht drin; Claude läuft aktuell über CLI oder später über OpenAI-kompatible Router wie OpenRouter.
- "Nur lokale Verarbeitung" blockiert Cloud-Logins und KI-Provider-Aufrufe hart, lässt lokale Transkripte, Export und Review-Actions aber nutzbar.

## Datenschutz- und Kunden-Reset-Stand

Aktueller App-Stand:
- Eigener Settings-Tab "Daten" mit lokalem Datenordner, Markdown-Gesamtexport, Audio-Retention und destruktivem Kunden-Reset.
- Gesamtexport erzeugt einen Desktop-Ordner mit einer Markdown-Datei pro Meeting.
- "Audio nach fertigem Transkript löschen" entfernt gespeicherte WAV-Dateien nach erfolgreicher Verarbeitung und hält Meeting-Text weiter nutzbar.
- "Alle lokalen Meetings und Audio löschen" löscht echte Meeting-Daten ohne Demo-Re-Seed. Die alte Mock-Reset-Oberfläche ist nicht mehr die Kundenfläche.
- API-Keys bleiben in Keychain und werden durch den lokalen Daten-Reset nicht gelöscht.

## Pricing-Empfehlung

Empfohlenes Modell: Hybrid.

- NeoQuill Pro einmalig: 79-99 EUR. Lokale App, lokale Transkription, BYO-API-Key, Export, Import, eigene Provider. Das passt zum local-first Versprechen und verursacht kaum laufende Serverkosten.
- NeoQuill Cloud optional: 12-15 EUR/Monat oder 99-129 EUR/Jahr. Nur für echte laufende Kosten: gehostete KI, Sync, Auto-Backup, Team-Funktionen, Prioritäts-Support.
- Team später: 15-25 EUR/User/Monat mit Admin, shared templates, zentrale Provider-Policy, Compliance-Export.

Warum nicht reines Abo:
- BYO-Provider und lokale Modelle senken deine laufenden Kosten.
- Mac-Nutzer akzeptieren Einmalkäufe für lokale Power-Tools besser.
- Abo ist sauber begründbar, sobald du Cloud-Sync, gehostete KI oder Teams betreibst.

Warum nicht nur Einmalkauf:
- Support, Updates, App-Store-Pflege und optionale Cloud-Kosten brauchen wiederkehrenden Umsatz.
- Für Teams ist Subscription normaler als Einmallizenz.

## Wettbewerbsanker

- Granola bewegt sich in Richtung Business-Abo um 14 USD/User/Monat.
- Otter Pro liegt offiziell bei 16.99 USD/User/Monat, jährlich rabattiert.
- Fireflies Pro liegt offiziell bei 18 USD monatlich oder 10 USD/User/Monat jährlich; zusätzliche AI-Credits existieren.
- MacWhisper positioniert sich als Mac-App mit einmaligem Pro-Kauf und ohne Abo.

NeoQuill sollte deshalb nicht "noch ein Meeting-Abo" sein, sondern: lokale Mac-App kaufen, Cloud nur wenn nötig abonnieren.

## App-Store- und Payment-Plan

- Direct Sale zuerst, weil schneller und flexibler.
- Für App Store: digitale Feature-Unlocks über StoreKit planen.
- Non-consumable IAP für Pro-Einmalkauf.
- Auto-renewable Subscription nur für Cloud/Team, weil Apple dafür laufenden Wert erwartet.
- Small Business Program beantragen, wenn Account qualifiziert ist, um die reduzierte App-Store-Kommission zu bekommen.

## Technische Slices

1. Provider-Testbutton: "Verbindung testen" + Beispielmeeting.
2. Custom Webhook Adapter: Request/Response Contract dokumentieren.
3. Paywall/Lizenz: Direct-License zuerst, StoreKit danach.
4. Privacy Export: lokaler Datenordner, Delete-All ohne Re-Seed, Markdown-Archiv, Audio-Retention.
5. Auto-Updater/Notarization: Sparkle 2, DMG-primary GitHub Release,
   ZIP-Fallback und hartes Market-Readiness-Gate.

## AI-Funktionen für v1.5

- Meeting-Briefing vor dem Call: Kalender + bekannte Teilnehmer + letzte Meetings.
- Executive Summary, technische Entscheidungen, Risiken, offene Fragen getrennt ausgeben.
- Action-Items mit Owner, Due-Date und Confidence.
- Follow-up-Mail als Draft, wählbar in "kurz", "freundlich", "knallhart".
- Ask-this-meeting Chat lokal über Transkript.
- Speaker-Qualität anzeigen: sicher, geschätzt, unklar.
- Mehrsprachige Zusammenfassung: Originalsprache behalten oder in Zielsprache normalisieren.
- CRM/Projektmodus: Sales, Discovery, Support, Sprint, Recruiting als Analyse-Templates.

## Action-Layer / Connectoren

Aktueller App-Stand:
- NeoQuill erzeugt nach fertiger Analyse eine Review-&-Execute-Action-Queue im Summary-Tab.
- Unterstützte sichere Aktionen: Follow-up Mail per `mailto:`, Follow-up Meeting als `.ics`, Jira-Draft, Neo-Inbox-Payload, Webhook-JSON.
- Connector-Settings existieren für Standard-Mail-Empfänger, Jira Base URL und Webhook URL.
- Optionaler Neo Skill-Bridge-Modus schickt Actions an die lokale Neo Action Inbox, mit Labels für `gog` oder Jira-CLI/Skill-Ausführung.
- Jira-only MCP-Slice ist als `Tools/NeonJiraMCP` angelegt: **Neon Jira MCP** erzeugt Jira-Drafts und kann bestätigte Issues über die lokale `jira` CLI erstellen.
- NeoQuill bietet im Integrationen-Tab einen Installer für den öffentlichen `github:NKDesign30/neon-jira-mcp` an und kann die lokale MCP-Config kopieren.
- Noch bewusst nicht drin: blindes Direkt-POSTing oder echte Jira/Google-OAuth-Ausführung ohne Review.

Nächste echte Connector-Slices:
1. Jira Cloud: MCP/CLI-Workflow in echten Meetings testen, danach optional native REST API mit Projekt/Issue-Type/Assignee aus Settings.
2. Google Workspace: Calendar Event + Gmail Draft über OAuth, mit Preview vor Ausführung.
3. Linear: Issue Create mit Team/Project/Cycle.
4. Notion/Confluence: Meeting Page + Action Items DB.
5. Slack/Teams: Channel Update oder DM Follow-up.
6. Webhook Direct POST: Retry, Timeout, Redaction, Response-Log.

## Launch-Checkliste

- Crash-freier 20-Meeting-Test auf Nikos Mac.
- 5 fremde Testnutzer mit echten Teams/Meet/Zoom-Calls.
- Landing Page mit 3 klaren Screens: Aufnahme, Summary, Provider-Settings.
- Demo-Video unter 90 Sekunden.
- Datenschutzseite: lokale Daten, Provider-Keys, Cloud-Toggle.
- Refund-Policy und Support-Mail.
- Signed + notarized DMG, ZIP-Fallback, EdDSA-Appcast und grünes
  `market-readiness.sh`.
- App Store erst nach Direct-Sale-Learnings.

## Quellen

- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Apple In-App Purchase types: https://apps.apple.com/us/iphone/story/id1539139213
- Apple Small Business Program: https://developer.apple.com/app-store/small-business-program/
- Spotify Engineering zu Backstage und autonomer Kultur: https://engineering.atspotify.com/2021/05/a-product-story-the-lessons-of-backstage-and-spotifys-autonomous-culture/
- Granola pricing docs: https://docs.granola.ai/help-center/update-to-granola-pricing-plans
- Otter pricing: https://otter.ai/pricing
- Fireflies pricing: https://fireflies.ai/pricing
- MacWhisper positioning: https://macwhisper.net/
