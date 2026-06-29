# NeoQuill Project Workspaces

Stand: 2026-06-29

## Ziel

NeoQuill soll Meetings nicht mehr nur als globale Liste behandeln. Ein Nutzer kann vor einem Call einen Arbeitskontext wählen, zum Beispiel DAT, E.ON oder Mercedes. Neue Meetings landen dann in diesem Kontext und die App kann später Zusammenfassungen, Suche, Export und Automationen projektbezogen ausführen.

## Nutzerfluss

1. Der Nutzer öffnet NeoQuill vor einem Meeting.
2. In der Sidebar wählt er oben den aktiven Workspace.
3. Bei Bedarf legt er dort direkt einen neuen Workspace an.
4. Er startet die Aufnahme.
5. Das Meeting erscheint in diesem Workspace und bleibt auch in "Alle Meetings" sichtbar.
6. Ein bestehendes Meeting kann später einem anderen Workspace zugeordnet werden.

## Begriff

Der technische Sammelbegriff ist `MeetingWorkspace`.

Ein Workspace kann drei Arten haben:

- `project`: Kundenprojekt, zum Beispiel DAT Relaunch oder Mercedes Workshop.
- `team`: wiederkehrendes Team, zum Beispiel internes Sprint-Team.
- `organization`: Kunde oder Organisation, zum Beispiel E.ON.

Für den ersten Slice ist das Verhalten identisch. Die Art ist trotzdem im Modell, damit UI, Export und spätere Sync-Regeln nicht nachgerüstet werden müssen.

## Datenmodell

Neue Tabelle `workspace`:

- `id TEXT PRIMARY KEY`
- `name TEXT NOT NULL`
- `kind TEXT NOT NULL`
- `context TEXT NOT NULL DEFAULT ''`
- `color_hex INTEGER NOT NULL`
- `archived INTEGER NOT NULL DEFAULT 0`
- `created_at REAL NOT NULL`

Neue Spalte in `meeting`:

- `workspace_id TEXT NULL REFERENCES workspace(id) ON DELETE SET NULL`

Warum nullable: bestehende Meetings bleiben gültig und erscheinen unter "Kein Workspace" sowie in "Alle Meetings".

## App-State

`MeetingStore` bleibt die lokale Source of Truth, weil Meetings bereits dort in `meetings.sqlite` liegen. Workspaces gehören in dieselbe DB, nicht in `UserDefaults`.

`AppState` hält nur UI-Zustand:

- `workspaceSelection: WorkspaceSelection`
- `visibleMeetings`
- aktiver Recording-Kontext wird vor `recorder.start()` gesetzt

`RecordingController` bekommt keinen eigenen Workspace-Store. Er kennt nur die aktuelle `workspaceId` als einfache Property und gibt sie beim Insert an `MeetingStore` weiter.

## UI-Platzierung

Sidebar oben, direkt unter Header und vor Suche:

- kompakter Workspace-Picker
- Einträge: "Alle Meetings", "Kein Workspace", alle aktiven Workspaces
- Aktion: "Neues Projekt..."

Warum dort: Der Nutzer entscheidet den Kontext unmittelbar vor dem Recording. Settings wären zu weit weg.

Workspace-Anlage als kleines Sheet:

- Name
- Art: Projekt, Team, Organisation
- Kontextnotiz

Bestehende Meetings werden im Detail-Menü über "Workspace" umgehängt. Das bleibt bewusst im vorhandenen Mehr-Menü, weil es ein nachträglicher Verwaltungsfall ist und nicht den Aufnahme-Flow stören soll.

Keine separaten Admin-Flächen im MVP.

## Summary-Kontext

`MeetingSummaryPrompt` bekommt Workspace-Kontext über den providerneutralen `PostProcessor`-Eingang:

- Name und Art des Workspace
- Kontextnotiz
- optional wiederkehrende Begriffe und Ziele

Der Provider-Vertrag bleibt gleich. Der Kontext wird vor das Transkript gesetzt, damit OpenAI-kompatible Provider, Anthropic, Ollama und Claude CLI denselben Input erhalten.

## Nicht-Ziele im MVP

- kein Account-/Team-Sharing
- kein Cloud-Sync
- keine Rollen/Rechte
- keine Workspace-Mitglieder
- keine externen CRM-Integrationen
- keine automatische Kunden-Erkennung aus Kalendern

## Akzeptanzkriterien MVP

- Nutzer kann einen Workspace lokal anlegen.
- Nutzer kann zwischen "Alle Meetings", "Kein Workspace" und konkreten Workspaces wechseln.
- Neue Aufnahmen übernehmen den aktuell aktiven Workspace.
- Bestehende Meetings ohne Workspace bleiben sichtbar.
- SQLite-Migration ist rückwärtskompatibel.
- Tests belegen Workspace-Insert, Meeting-Zuordnung und Filterlogik.

## Verifikation

- `git diff --check`
- Marker-Suche nach offenen Implementierungsmarkern
- fokussierte `MeetingStore` Tests
- `swift test`
- bei erfolgreichem Testlauf: `./scripts/build-app.sh --no-install --no-run`
