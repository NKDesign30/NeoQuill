# NeoQuill Roadmap — "Generisch & verkaufsreif"

> Stand: 2026-06-09 · Branch-Basis: `dev` (v0.11.0)
> Ziel dieser Roadmap: NeoQuill von "läuft nur in Nikos Setup" zu einem Produkt
> machen, das ein fremder Käufer installiert, mit **seiner eigenen KI** und **seiner
> Sprache** betreibt und bei dem **kein einziger Wert mehr hartcodiert von Niko** ist.

---

## Goal Contract

**Ziel:** Jeder Käufer hängt seine eigene KI an (Claude OAuth, Anthropic-API-Key,
OpenAI / OpenAI-kompatibel, Ollama lokal), wählt seine UI- und Ausgabe-Sprache, und
aktiviert optionale Integrationen (Jira, Inbox-Bridge, Webhook) bewusst in den
Settings. Out of the box gibt es einen funktionierenden KI-Pfad ohne Nikos Konto.

**Nicht-Ziele:**
- Kein eigener gehosteter LLM-Proxy von Neon in v1 (BYOK-Modell, optional später).
- Keine vollautomatische Cloud-OAuth-Sync für Teams/Meet/Zoom in v1 (Datei-Import bleibt).
- Keine neue Audio-/Transkriptions-Engine. Die Pipeline bleibt.
- Keine Skill-Runtime im Produkt. Skills bleiben opt-in Brücken zu lokalen Tools.

**Deliverables (aus Nikos Worten):**
1. Generische KI-Provider-Auswahl: Claude OAuth, Anthropic-Key, OpenAI/-kompatibel, Ollama, freie API-Keys.
2. Mehrsprachigkeit wie NeoWispr: UI-Sprache + Transkriptions-Sprache + Zusammenfassungs-Sprache.
3. Null Hardcodes von Niko (Name, `127.0.0.1:3850`, `de_DE`, Default-Provider).
4. Skills/Integrationen werden mitgeliefert, aber der User aktiviert sie in den Settings.

**Akzeptanzkriterien (Produkt-Ebene):**
- Frischer Mac, neuer User, kein Neon-Stack: Aufnahme + lokale Transkription + KI-Summary
  laufen, sobald der User *einen* Provider konfiguriert hat. Kein "Inbox-Fehler", kein "Niko".
- App-Sprache umschaltbar (mindestens DE + EN), Neustart übernimmt alles inkl. Datumsformat.
- Zusammenfassung erscheint in der vom User gewählten Sprache.
- Alle Integrationen sind per Default **aus** und ohne sichtbare Fehlfunktion, bis aktiviert.

**Verify-Pfad:** Pro Epic eigene Tests + Live-Smoke im echten `.app`-Bundle
(`./scripts/build-app.sh`), nicht nur `swift test`. Runtime-Wahrheit vor "fertig".

---

## Epic-Reihenfolge (Abhängigkeiten)

```
E0 De-Niko-fizierung  ──►  E1 KI-Provider  ──►  E4 Onboarding-Rewrite  ──►  E5 Release 1.0
        │                       │
        └──►  E3 Integrationen  ┘
E2 Mehrsprachigkeit  (parallel zu E1, mündet in E4)
```

E0 zuerst (entgiftet, kleine Diffs). E1 und E2 sind die zwei großen Säulen und
können parallel laufen. E3 hängt an E0. E4 verdrahtet E1+E2 ins Setup. E5 schließt ab.

---

## E0 — De-Niko-fizierung (Quick Wins, kleine Diffs)

**Ziel:** Jeder sichtbare oder funktionale Niko-Hardcode raus. Nichts darf bei einem
fremden User failen oder peinlich wirken.

**Slices:**
- **E0.1** Onboarding-Platzhalter neutralisieren: `OnboardingStep06Ready` (`?? "Niko"`)
  und `OnboardingStep03Voice` (`"Niko Knez"`) → generischer Platzhalter / leer / Locale-neutral.
- **E0.2** Der vergessene Button: `TaskRow` "An Neo Inbox senden" hinter den
  `actionNeoSkillBridgeEnabled`-Toggle legen (analog `MeetingActionQueueSection`).
  `SummaryPane` + `DetailSplit` übergeben den Closure nur, wenn die Bridge aktiv ist.
- **E0.3** `NeonInboxClient`-Endpoint aus dem Hardcode lösen: `127.0.0.1:3850` wird
  konfigurierbarer Default (Settings-Feld, vorbefüllt), nicht `preconditionFailure`.
- **E0.4** Datums-/Zahl-Locale entkoppeln: `de_DE` in `MeetingTimeline`, `HeaderHero`
  etc. → `Locale.current` bzw. an die gewählte App-Sprache gebunden (greift in E2).

**Akzeptanz:** `grep -rni "niko\|127.0.0.1:3850\|de_DE" Sources/` liefert nur noch
bewusste, dokumentierte Treffer (z. B. Kommentare). Fremder User klickt keine
Funktion, die gegen Nikos Maschine läuft.

---

## E1 — Generische KI-Provider-Architektur (Herzstück)

**Ziel:** Ein sauberes Provider-Protokoll, an das beliebige Backends andocken. Der
Summary-/Action-Pfad kennt nur das Protokoll, nicht den konkreten Anbieter.

**Architektur:**
- Neues Protokoll `SummaryProvider` (`func complete(prompt:) async throws -> String`,
  plus `displayName`, `requiresKey`, `modelCatalog()`), `Sendable`.
- `PostProcessor` / `MeetingSummarizer` rufen das Protokoll. Heutige Clients werden
  zu Implementierungen dahinter.
- Keys/Tokens immer in der Keychain (`AIProviderSecretStore`-Muster, schon vorhanden).

**Provider-Tiers:**
- **E1.1 OpenAI-kompatibel (deckt das meiste, ist fast fertig):** OpenAI, OpenRouter,
  Groq, Together, lokale Server. `baseURL` + Key + Model-Picker statt Freitext-Modell.
  Aufbauend auf `OpenAICompatibleSummaryClient`.
- **E1.2 Ollama (lokal, kein Key):** Preset `http://localhost:11434/v1`, Model-Discovery
  über `/api/tags`, Erkennung "läuft Ollama?". Nutzt den OpenAI-kompatiblen Transport.
- **E1.3 Anthropic-API (eigener Key):** Eigener Client gegen `/v1/messages`
  (`x-api-key`, `anthropic-version`-Header, anderes Body-Format als OpenAI). Model-Picker.
- **E1.4 Claude CLI (lokaler Login):** Bestehender `ClaudeCLIClient` bleibt als
  "Power-User / Dev"-Option, aber **nicht mehr Default**.
- **E1.5 Default-Strategie:** Kein Provider erzwingt Nikos Setup. Erststart → der User
  *muss* einen Provider wählen, bevor KI-Features greifen (klarer Empty-State statt
  stiller Fehlschlag). `AIProviderSettings.defaultProvider` wird neutral.
- **E1.6 Verbindungstest:** "Testen"-Button pro Provider (1 Mini-Call), zeigt Erfolg
  oder konkreten Fehler. Verhindert "ich hab gekauft und nichts passiert".

**Claude OAuth ("Claude AuthO"):** Eigene Stufe **E1.7 (nach v1)** — echter Anthropic
OAuth-Flow für Login mit Claude-Account ohne API-Key. Komplex (Client-Registrierung,
Token-Refresh). Bis dahin decken Anthropic-Key + Claude CLI den Claude-Pfad ab.

**Akzeptanz:** Auf einem Mac ohne Neon-Stack lässt sich jeder der vier v1-Provider
auswählen, testen und produziert eine echte Zusammenfassung. Provider-Wechsel zur
Laufzeit ohne Neustart. Tests: ein Contract-Test pro Implementierung gegen ein Fake-Transport.

---

## E2 — Mehrsprachigkeit (wie NeoWispr)

**Ziel:** UI-Sprache, Transkriptions-Sprache und Zusammenfassungs-Sprache sind
unabhängig wählbar. Keine deutsche Zeichenkette mehr fest verdrahtet.

**Slices:**
- **E2.1 String Catalog einführen:** `.xcstrings` in den SPM-Resources,
  `defaultLocalization` in `Package.swift`. Start mit DE + EN.
- **E2.2 Strings extrahieren:** Alle sichtbaren Texte (Views, Onboarding, Settings,
  Notifications) auf `LocalizedStringKey` / String-Catalog-Keys umstellen. Größter Slice,
  am besten Bereich für Bereich (Onboarding → Settings → Detail → Sidebar).
- **E2.3 UI-Sprachwahl:** Settings-Picker "App-Sprache" (System / DE / EN / …),
  greift via `Locale`-Override; Datumsformatter ziehen die gewählte Sprache (löst E0.4 final).
- **E2.4 Transkriptions-Sprache als First-Class-Setting:** `AppSettings.language`
  ("auto" + Liste) sichtbar im Onboarding und Settings, Default `"auto"` statt `"de"`.
  WhisperKit kann das bereits, nur UI + Default fehlen.
- **E2.5 Zusammenfassungs-Sprache:** `MeetingSummaryPrompt` bekommt eine Ziel-Sprache
  ("antworte auf {language}"), gesteuert vom User (Default = UI-Sprache). Sonst kommt
  bei englischem Meeting eine deutsche Summary.

**Akzeptanz:** App auf EN umstellen → komplette Oberfläche EN inkl. Datumsformat.
Englisches Meeting → englisches Transkript + englische Zusammenfassung. Keine
sichtbare hartcodierte deutsche Zeichenkette mehr (Stichprobe + Lokalisierungs-Lint).

---

## E3 — Integrationen / Skills als bewusstes Opt-in

**Ziel:** Jira, Inbox-Bridge, Webhook, Gmail werden mitgeliefert, sind aber per Default
inaktiv und werden in den Settings einzeln aktiviert. Mitgeliefert ist nicht aufgedrängt.

**Slices:**
- **E3.1 Integrations-Konzept:** Settings-Bereich "Integrationen" mit einheitlichen
  Toggles (jeweils Aus by default), Status-Anzeige und Kurz-Erklärung pro Integration.
- **E3.2 Sichtbarkeits-Gating:** Jeder Integrations-Button/-Menüpunkt erscheint nur,
  wenn die Integration aktiv ist (zieht E0.2 sauber durch alle Stellen).
- **E3.3 Jira-Brücke generisch:** `actionJiraBaseURL` + lokale `jira`-CLI / Neon-Jira-MCP
  bleiben, aber als klar beschriebenes Opt-in. Keine Neon-spezifische Sprache im UI-Text.
- **E3.4 Inbox-Bridge generisch:** Endpoint aus E0.3 als Feld, Label neutral
  ("Action-Inbox-Endpoint") statt "Neo". Default aus.
- **E3.5 Webhook:** bestehender JSON-Webhook-Pfad als generische Automation-Integration
  (Make / Zapier / n8n / eigene API) sauber dokumentiert.

**Akzeptanz:** Frischer User sieht keine aktive Integration und keinen Integrations-Fehler.
Aktiviert er Jira/Inbox/Webhook, erscheinen die zugehörigen Aktionen und funktionieren
gegen *seine* konfigurierten Ziele.

---

## E4 — Onboarding-Rewrite (verdrahtet E1 + E2)

**Ziel:** Das Setup führt den fremden User zu einem funktionierenden Zustand: Name,
Sprache, KI-Provider inkl. Test. Kein "Bereit, Niko".

**Slices:**
- **E4.1 Sprach-Schritt:** Früher Schritt für UI- + Transkriptions-Sprache.
- **E4.2 KI-Provider-Schritt:** Provider wählen, Key/Endpoint eingeben, Verbindung
  testen (E1.6). Ohne grünen Test kein "fertig", aber überspringbar (KI später einrichten).
- **E4.3 Texte lokalisiert + neutral:** Alle Onboarding-Strings über E2, Platzhalter aus E0.

**Akzeptanz:** Neuer User durchläuft das Setup in EN, richtet OpenAI **oder** Ollama ein,
sieht grünen Verbindungstest, und die erste Aufnahme liefert eine englische Zusammenfassung.

---

## E5 — Release 1.0 (Paywall scharf schalten)

**Ziel:** Aus dem freien Beta-Build wird ein verkaufbares 1.0 mit greifender Lizenz.

**Slices:**
- **E5.1 Version → `1.0.0`**, Changelog-Sektion, Tag.
- **E5.2 `NeoQuillLicenseEnforcement=enforced`** in der Info.plist (sonst ist ab 1.0
  zwar `.enforced` Default, aber explizit setzen = klarer Kontrakt). Trial/Grace prüfen.
- **E5.3 Paywall-Flow Ende-zu-Ende testen:** Trial-Ablauf → `LicenseGate` → Lemon-Squeezy
  Checkout → Aktivierung → Pro-Features frei. Mit echtem (Test-)Key.
- **E5.4 `./scripts/market-readiness.sh`** grün: signiert, notarized, stapled, Appcast,
  GitHub-Release, Manifest synchron.

**Akzeptanz:** Frischer Käufer: Trial → Kauf → Aktivierung → KI-Summary/Speaker-ID/Import
freigeschaltet, alles in seiner Sprache, mit seinem Provider. `market-readiness.sh` ohne FAIL.

---

## Risiken & offene Produktentscheidungen (brauchen Niko)

1. **BYOK vs. gehosteter Endpoint:** v1 ist Bring-Your-Own-Key. Wenn ein Käufer ohne
   eigenen LLM-Zugang das Pro-Feature trotzdem sofort nutzen soll, braucht es später
   einen Neon-Proxy hinter der Lizenz. Eigene Entscheidung, eigene Kosten.
2. **Claude OAuth (E1.7):** Echter Anthropic-OAuth-Flow ist Aufwand + Client-Registrierung.
   v1 deckt Claude über API-Key + CLI ab. OAuth als Folge-Stufe.
3. **Sprach-Umfang:** Start DE + EN. Weitere Sprachen sind danach nur noch Übersetzungs-Arbeit
   im String Catalog, keine Architektur mehr.
4. **Cloud-OAuth-Sync (Teams/Meet/Zoom):** In v1 ausgeblendet/als "kommt später" gelabelt,
   weil pro User eigene Client-IDs nötig wären. Datei-Import bleibt der generische Pfad.

---

## Erste Slice (sofort startbar)

**E0.1 + E0.2 + E0.3** in einem Schnitt: Niko-Platzhalter raus, vergessenen Inbox-Button
gaten, Inbox-Endpoint entschärfen. Kleiner Diff, sofort verifizierbar, entfernt die drei
peinlichsten "fremder User"-Stolperfallen. Danach E1 als große Säule.
