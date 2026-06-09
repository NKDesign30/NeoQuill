# Die `lifecycle`-Wahrheit schreibt die alte `processing`-Spalte weiter mit

Seit der typisierte `MeetingLifecycle` das alte `processing: Bool` als Single
Source of Truth ablöste (Commit 94474e0), schreibt `MeetingStore.upsertDetail`
bewusst **beide** Spalten weiter: `lifecycle` (die Wahrheit) und `processing`
(als computed `lifecycle.isBusy`). Gelesen wird `lifecycle` bevorzugt, mit
`processing` nur als Fallback für Zeilen aus der Zeit vor der Migration.

Das ist Absicht, kein Versehen: NeoQuill wird per Sparkle ausgeliefert, ein
Nutzer kann auf einen Build **vor** der Lifecycle-Migration zurückrollen. Dieser
ältere Build liest dieselbe SQLite-Datei und kennt nur die `processing`-Spalte —
fehlt sie, sieht er jedes laufende Meeting fälschlich als „fertig". Die
Doppelschreibung ist also Downgrade-Kompatibilität, kein Tech-Debt.

Ein Drift-Risiko zwischen den beiden Spalten gibt es nicht: `d.processing` ist
ein computed Property aus `d.lifecycle.isBusy` und kann per Konstruktion nie von
`lifecycle` abweichen.

## Konsequenz

Architektur-Reviews flaggen „zwei persistierte Wahrheiten für ein Konzept"
zurecht — ohne diesen Kontext. Die `processing`-Spalte bleibt, bis Support für
Builds vor der Lifecycle-Migration entfällt. Erst dann darf das `processing`-
Schreiben aus `upsertDetail` entfernt und die Spalte deprecated werden.
