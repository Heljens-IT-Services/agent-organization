# Skill: Code Minimization

## Zweck

Einen lokal funktionierenden Änderungssatz auf die kleinste hinreichend begründete Lösung reduzieren. Dabei bleiben erforderliches Verhalten, Acceptance-Evidenz, bekannte Invarianten, Security- und Fehlerpfade sowie belegte technische Constraints erhalten.

Minimierung bearbeitet den ausdrücklich zugewiesenen Änderungssatz. Sie entfernt oder vereinfacht vorhandene Änderungsteile, deren heutige Notwendigkeit nicht belegt ist; sie ist weder ein LOC-Wettbewerb noch eine neue fachliche Lösung.

## Verwenden

- Wenn ein Änderungssatz lokal reproduzierbar funktioniert oder belastbare lokale `PASS`-Evidenz für sein beabsichtigtes Verhalten vorliegt.
- Wenn nach Implementierung oder gezielter lokaler Konvergenz verbliebene Debug-Reste, parallele Pfade, unnötige Wrapper oder spekulative Erweiterungen auf Notwendigkeit geprüft werden sollen.
- Nicht verwenden, um fehlende fachliche Anforderungen zu klären, ein Feature zu implementieren, eine Struktur aus Schönheitsgründen zu verbessern, Tests zu schreiben oder einen Diff nur lesend zu bewerten.

## Direkter Alias

- `/minimize`

`/minimize` verwendet den aktuellen Task-, Issue- und Änderungskontext. Es akzeptiert keine zusätzlichen Positionsargumente. Wenn der zu minimierende Änderungssatz oder sein zu erhaltendes Verhalten nicht eindeutig ist, muss der fehlende Kontext vor der Mutation geklärt werden.

## Voraussetzungen und Baseline

[MUST] Minimierung darf erst auf einem Änderungssatz beginnen, dessen beabsichtigtes Verhalten lokal reproduzierbar funktioniert oder für den eine belastbare lokale `PASS`-Evidenz vorliegt.

[MUST] Der Agent muss vor der ersten Reduktion die Baseline, den aktuellen Diff, den Task-/Issue-Vertrag, bekannte Invarianten und die für den Änderungssatz relevante Verifikation bestimmen.

[MUST] Die Baseline muss belastbar und bevorzugt der eindeutig zuordenbare Task- oder Branch-Ausgangsstand sein. Ist sie nicht eindeutig auflösbar, darf kein Commit geraten werden; der Agent arbeitet nur auf eindeutig abgegrenzten Änderungsteilen oder beendet den Skill als `BLOCKED`.

[MUST] Fremde oder bereits vorhandene Änderungen müssen vom Änderungssatz getrennt und unverändert erhalten bleiben.

Vor der Mutation ist mindestens festzuhalten:

- Baseline und Begründung ihrer Auswahl,
- Scope des eigenen Änderungssatzes und nicht zu verändernde Bereiche,
- beabsichtigtes Verhalten, Acceptance-Kriterien und bekannte technische Constraints,
- relevante Security-, Validierungs-, Fehler- und Datenintegritätsinvarianten,
- fokussierte lokale Verifikation und ihre aktuelle Evidenz.

## Vorgehen

1. Task-/Issue-Vertrag, Scope, Baseline, Diff und lokale `PASS`-Evidenz lesen und die Grenzen des Änderungssatzes markieren.
2. Die Änderungsteile nach Notwendigkeit klassifizieren:
   - `REQUIRED`: direkt für Acceptance, Invariante oder erforderliches Verhalten notwendig.
   - `JUSTIFIED`: nicht direkt Acceptance-relevant, aber durch einen konkret benennbaren heutigen technischen Constraint gerechtfertigt.
   - `CANDIDATE`: aktuelle Notwendigkeit ist nicht belegt; ein begrenzter Reduktionsversuch ist zulässig.
   - `REMOVED`: Kandidat wurde entfernt und die relevante Evidenz blieb grün.
   - `RETAINED_AFTER_FAILURE`: Entfernung wurde versucht, relevante Evidenz brach; der Bestandteil bleibt mit Begründung erhalten.
3. Zuerst semantisch zusammenhängende Kandidatengruppen mit hoher Slop-Wahrscheinlichkeit prüfen: Debug-/Instrumentierungscode, verworfene Lösungsreste, parallele Pfade, ungenutzte Fallbacks, einmalige Wrapper oder Helper ohne Strukturgewinn, spekulative Konfiguration, unnötige API-Erweiterungen und Dependencies ohne aktuellen Treiber.
4. Für jede Gruppe eine konkrete Minimierungshypothese und einen zugehörigen Nachweis formulieren: welcher Bestandteil entfällt oder wird vereinfacht, welches Verhalten und welche Invariante muss danach unverändert nachweisbar sein.
5. Genau eine begrenzte, nachvollziehbare Reduktion mutieren. Keine blind zeilenweise Löschung und keine gleichzeitige fachliche Neuimplementierung.
6. Nach jeder akzeptierten Reduktion die fokussierte, für den entfernten Bestandteil relevante Verifikation erneut ausführen. Erst bei erneutem Erfolg dürfen abhängige Kandidaten bearbeitet werden.
7. Bei Erfolg den Kandidaten als `REMOVED` dokumentieren; bei einem Fehlschlag die Änderung zurücknehmen, Ursache und gebrochene Evidenz festhalten und als `RETAINED_AFTER_FAILURE` führen.
8. Nach der letzten Reduktion den verbleibenden Diff erneut gegen Vertrag, Invarianten und Baseline abgleichen und die unabhängige finale Verifikation im gesonderten Prüfauftrag als nachgelagerten Schritt ausweisen.

## Sicherheits- und Invariantenregeln

[MUST_NOT] Fehlende Testabdeckung darf nicht als Beweis verwendet werden, dass eine Security-Prüfung, Validierung, Fehlerbehandlung, Datenintegritätsregel oder dokumentierte Invariante entbehrlich ist.

[MUST] Security-, Autorisierungs-, Mandantentrennungs-, Validierungs-, Fehler- und Datenintegritätslogik bleibt erhalten, solange kein konkreter heutiger Vertrag ihre Entfernung trägt und die relevante Verifikation dies nachweist.

[MUST] Eine bestehende klarere oder sicherere Lösung darf nicht durch kompakteren, aber schlechter verständlichen, riskanteren oder stärker gekoppelten Code ersetzt werden, nur weil der Diff kleiner wird.

[MUST_NOT] Eine Änderung darf nicht entfernt werden, wenn dadurch Acceptance-Evidenz, ein erforderlicher Fehlerpfad oder ein konkret belegter Architektur-Constraint verletzt wird.

Wenn eine Änderung nur eine hypothetische zukünftige Variante unterstützt und weder der Task noch das bestehende Repository einen realen heutigen Treiber dafür belegt, soll sie als `CANDIDATE` geprüft und gegebenenfalls entfernt werden.

## Grenzen und Abgrenzung

- `code-minimization` entfernt oder vereinfacht vorhandene, nicht hinreichend begründete Änderungsteile. Es führt keine neue fachliche Lösung, Architektur oder Anforderung ein.
- `code-refactoring` verbessert bewusst die Struktur bei erhaltenem Verhalten; es darf neue Struktur rechtfertigen, wenn sie bestehende Last reduziert. Minimierung verfolgt dagegen die Notwendigkeit des vorhandenen Diffs.
- `code-implementation` setzt geklärtes neues Verhalten, neue Logik, Features oder APIs um. Eine solche Änderung ist kein Minimierungsschritt.
- `code-diff-review` bewertet read-only Scope, Risiken und Nebenwirkungen. Es kann Kandidaten markieren, mutiert aber nicht.
- `code-testing` führt die formale oder unabhängige Build-, Test-, E2E- oder manuelle Verifikation aus. Minimierung darf fokussierte lokale Evidenz nutzen, ersetzt aber keine unabhängige finale Freigabe.
- Keine pauschale Vorgabe einer maximalen Diff-, Datei-, Klassen- oder LOC-Größe; diese Zahlen dürfen allein kein Ziel sein.
- Keine automatische Erfindung zusätzlicher Tests oder Acceptance Criteria.
- Keine Workflow-Integration und keine externen Mutationen wie Commit, Push, Merge oder Issue-Schließung.

## Abbruchregeln

[MUST] Bei unklarer Baseline, unklarem Änderungssatz, fehlender lokaler Konvergenz oder fehlendem Nachweis für das zu erhaltende Verhalten muss der Agent vor der Mutation stoppen und `BLOCKED` mit fehlendem Kontext ausgeben.

[MUST] Wenn eine Reduktion erforderliches Verhalten, eine Invariante, Security-/Fehlerlogik, Acceptance-Evidenz oder einen belegten Constraint verletzt, muss sie zurückgenommen werden; weitere davon abhängige Reduktionen werden nicht begonnen.

[MUST_NOT] Der Agent darf keinen Fehlschlag durch Abschwächen oder Entfernen der relevanten Verifikation verdecken und darf keinen Erfolg behaupten, wenn der gezielte Retest nicht erfolgreich oder nicht reproduzierbar ist.

## Verifikationsbeispiele

- Ein temporärer Debug-Hook ist `CANDIDATE`; nach Entfernung bleibt der fokussierte Fix-Test grün und der Bestandteil wird `REMOVED`.
- Ein Security-Guard ohne eigenen Regressionstest bleibt erhalten; fehlende Abdeckung ist kein Entfernungsbeweis.
- Ein einmaliger Wrapper ohne Strukturgewinn ist ein Kandidat für eine direkte Lösung.
- Ein Adapter, den eine vorhandene Schnittstelle oder Dependency-Inversion verlangt, ist `JUSTIFIED`.
- Bricht die Entfernung eines Fallbacks den definierten Fehlerpfad, wird sie zurückgenommen und als `RETAINED_AFTER_FAILURE` geführt.
- Bei fremden Vorarbeiten und unklarer Baseline wird nicht global minimiert; der Scope wird begrenzt oder der Skill als `BLOCKED` beendet.

## Output

- Status: `COMPLETED` oder `BLOCKED`.
- Baseline, eigener Scope und unveränderte Fremdänderungen.
- Pro Kandidat: Bestandteil, Klasse, Minimierungshypothese, Mutation, gezielter Retest und Evidenz sowie `REMOVED` oder `RETAINED_AFTER_FAILURE`.
- Verbleibende `REQUIRED`-/`JUSTIFIED`-Bestandteile und sichtbare Restrisiken.
- Nicht ausgeführte Verifikation und der an den Koordinator gemeldete unabhängige Prüfbedarf.

## Qualitätskriterien

- Jede Entfernung ist semantisch begründet und durch einen gezielten Retest belegt.
- Der Änderungssatz bleibt gegen Baseline, Vertrag, Security-Invarianten und Fehlerpfade nachvollziehbar.
- Kandidaten wurden gruppiert statt blind nach Zeilen oder Größenwerten bearbeitet.
- `REQUIRED`, `JUSTIFIED`, `CANDIDATE`, `REMOVED` und `RETAINED_AFTER_FAILURE` sind eindeutig unterscheidbar.
- Abgrenzung zu Implementierung, Refactoring, Testing und Diff-Review bleibt sichtbar.
- Eine unabhängige finale Freigabe im gesonderten Prüfauftrag wird weder ersetzt noch vorweggenommen.

