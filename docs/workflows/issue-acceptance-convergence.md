# Workflow: Issue Acceptance Convergence

## Owner und Modus

`koordinator` liest diesen Ablauf ausschließlich als Delegationsplan. Issue-Graph und fachliche Kriterien delegiert er an `product_owner`; technische Kriterien und deren Umsetzungskontrolle an `softwareentwicklung_architektur`; unabhängige Regression und technische Gesamtsicherung an `softwareentwicklung_qualitaetssicherung`. Product Owner prüft fachliche Kriterien als Black Box ohne Quellcode; Architektur darf technische Kriterien mit Code- und Testevidenz prüfen. Gaps gehen an Product Owner zur fachlichen Scope-/Issue-Klärung, technische Strukturfragen an Architektur, Umsetzung an Backend/Frontend/Infra und Git-Abschluss an `softwareentwicklung_infrastruktur`. Für jede vollständige Re-Acceptance delegiert der Koordinator fachliche Prüfung an PO, technische Kriterienprüfung an Architektur und unabhängige Gesamtsicherung an QA.

## Ziel

Die Akzeptanzkriterien eines angegebenen Root-Issues und seines vollständigen nativen Child-Graphen gegen den aktuellen integrierten Stand prüfen. Die Prüfung ist graphweit und ersetzt weder lokale Task-Verifikation noch den technischen Branch-/PR-Abschluss.

## Verwenden

- Wenn ein `Epic`, eine `Story` oder ein `Task` fachlich abschließend gegen den finalen integrierten Stand geprüft werden soll.
- Wenn ein früher bereits grünes Child erneut auf Regressionen und den aktuellen Gesamtstand geprüft werden muss.
- Nicht verwenden, um Gaps innerhalb dieses Workflows automatisch zu beheben. Remediation wird kontrolliert an Planung und Umsetzung zurückgegeben.
- Nicht verwenden, um Issues automatisch zu schließen oder `/finish` fachlich umzudeuten.

## Direkter Alias

- `/acceptance <issue-number>`

Der kanonische Aufruf lautet `/workflows run issue-acceptance-convergence <issue-number>`.

`<issue-number>` muss eine positive Ganzzahl mit optional vorangestelltem `#` sein, zum Beispiel `/acceptance #123`.

## Verwendete Skills

- `issue-reading`
- `product-acceptance`
- `code-testing`
- `code-minimization` für Backend-/Frontend-Änderungssätze innerhalb der Remediation
- `code-implementation` für scoped Infrastrukturkorrekturen
- `code-analysis` bei nicht direkt prüfbaren oder widersprüchlichen Kriterien

## Ablauf

1. Der Koordinator delegiert an `product_owner`, das Root-Issue mit Body, Kommentaren, Status, nativen Type- und Relationship-Metadaten per `issue-reading` zu lesen.
2. Product Owner prüft, dass der Root-Type `Epic`, `Story` oder `Task` ist. Andere Root-Typen werden als `BLOCKED` mit konkreter Begründung ausgewiesen.
3. Product Owner verfolgt vom Root ausschließlich native Child-Beziehungen rekursiv nach unten. Parent-Issues oberhalb des Roots werden nur als Kontext gelesen und nicht in die Acceptance-Menge aufgenommen.
4. Product Owner führt für jeden Knoten eine besuchte Menge anhand stabiler Repository-/Issue-Identität. Bereits besuchte Knoten werden nicht erneut expandiert; Zyklen werden als `BLOCKED` dokumentiert.
5. Product Owner erfasst Root und jedes erreichte Child mit Nummer, Titel, Status, Type, URL sowie Acceptance-relevanten Beziehungen.
6. Product Owner und Architektur sammeln fachliche beziehungsweise technische Akzeptanzkriterien vollständig aus dem Issue-Kontext und halten sie in einer gemeinsamen Kriterienmatrix getrennt fest. QA ergänzt erforderliche unabhängige Regression- und Gesamtsicherungsprüfungen.
7. Keine Rolle leitet Kriterienerfüllung allein aus Issue-Status, früherem Testlauf, Commit oder dem Ergebnis eines anderen Issues ab.
8. Der Koordinator delegiert die Black-Box-Bewertung fachlicher Kriterien an Product Owner, die Prüfung technischer Kriterien an Architektur und die beauftragte unabhängige Regression sowie technische Gesamtsicherung an QA. Die Rollen prüfen den aktuellen finalen integrierten Stand und liefern getrennte Belege. Ein geeigneter aktueller E2E-Lauf darf denselben sichtbaren Ablauf belegen, wenn Product Owner und Architektur ihn jeweils nur gegen die eigenen Kriterien bewerten; eine identische Prüfung muss nicht allein zur Rollentrennung doppelt ausgeführt werden.

## Scope-Regeln

- Nur Root und dessen rekursiv erreichbare Children bilden die Acceptance-Menge.
- Parent-Kontext oberhalb des Roots, Geschwister und nicht erreichbare Teilbäume bleiben außerhalb des Prüfscope.
- Ein geschlossenes Issue ist prüfbar, aber sein Status ist kein Acceptance-Nachweis.
- Parent-Kriterien werden unabhängig von Child-Ergebnissen geprüft.
- Ein Child wird bei jeder Acceptance-Runde erneut gegen den aktuellen integrierten Stand bewertet.

## Kriterienmatrix

Für jedes Kriterium wird mindestens folgende Zeile geführt:

| Issue | Kriterium und Typ | Fachliche Bewertung (PO) | Technische Bewertung (Architektur) | Unabhängige QA-Sicherung | Gesamtstatus | geprüfter Stand |
|---|---|---|---|---|---|---|
| #123 | <vollständiger Kriterientext; fachlich/technisch/beides> | <Status und sichtbarer Beleg oder nicht erforderlich> | <Status und technische Evidenz oder nicht erforderlich> | <Regression/Gesamtsicherung oder nicht erforderlich> | `PASS` / `GAP` / `BLOCKED` | <Commit, Artefakt oder Prüfzeitpunkt> |

Fehlen Kriterien, ist das als Kontextlücke zu markieren und nicht als automatischer `PASS` zu werten. Die Kriterienmatrix muss Root und alle Children voneinander getrennt ausweisen.

## Bewertungsprotokoll

Product Owner, Architektur und QA bewerten jeweils nur die Aspekte ihrer Rolle gegen den aktuellen integrierten Stand:

- Product Owner bewertet User Stories und fachliche Kriterien als Black Box über eine freigegebene Produktoberfläche oder anhand ausdrücklich bereitgestellter geeigneter E2E-Ausgaben. Product Owner liest keinen Produktiv- oder Testquellcode.
- Architektur bewertet Technical Stories und technische Kriterien anhand passender Code-, Test- und Systembelege und liest nur den eigenen technischen Scope.
- QA prüft unabhängig die ausdrücklich beauftragten Regressionen, technische Testabdeckung, Testautomatisierung und relevanten technischen Gesamtrisiken. Eine erneute Ausführung jedes bereits geeigneten Nachweises ist nicht allein wegen mehrerer zuständiger Rollen erforderlich. QA übernimmt weder fachliche Produktabnahme noch Architekturentscheidungen.
- `PASS`: Das Kriterium ist durch die dafür notwendige fachliche oder technische Evidenz erfüllt; bei Kriterien mit beiden Anteilen müssen beide Bewertungen bestehen.
- `GAP`: Das Kriterium ist im vereinbarten Scope nicht erfüllt oder die Evidenz zeigt eine Regression.
- `BLOCKED`: Eine Prüfung ist wegen eines konkreten fachlichen oder technischen Hindernisses nicht belastbar möglich; das Hindernis wird benannt.

Ein lokaler Test, ein manueller Prüfschritt oder ein vorhandenes Artefakt kann geeignete Evidenz sein, wenn es das Kriterium direkt belegt. Das Fehlen von CI-Checks ist für sich allein weder ein `GAP` noch ein `BLOCKED`; nur ein tatsächlich erforderlicher und fehlender Nachweis darf als Blocker bewertet werden. Umgekehrt ersetzt ein grüner CI-Check keine fachliche Evidenz für ein Kriterium.

Der Rundenstatus wird deterministisch abgeleitet: mindestens ein `BLOCKED` ergibt `BLOCKED`, andernfalls mindestens ein `GAP` ergibt `GAP`, andernfalls ergibt eine vollständig belegte Matrix `PASS`. Fehlende erforderliche Belege werden als `BLOCKED` mit konkretem Grund ausgewiesen. `GAP` löst Remediation aus und ist kein terminaler Konvergenzstatus.

## Terminaler Konvergenzstatus

Der übergeordnete Konvergenzzyklus endet erst mit `PASS`, einem konkret begründeten `BLOCKED` oder einer ausdrücklichen Human-Entscheidung. Ein Rundenstatus `GAP` darf den Zyklus nicht beenden, sondern führt in den definierten Remediation- und anschließenden Re-Acceptance-Schritt.

## Gap-Klassifikation und Routing

Jeder `GAP` wird vor einer Änderung eindeutig klassifiziert:

1. **Bestehender Issue-Scope:** Das Kriterium gehört zum Scope eines vorhandenen Issues, ist aber unvollständig oder regressiv. Nach gezielter technischer Planung wird derselbe Issue-Scope über `issue-implementation` auf dem vorhandenen Arbeitsbranch remediiert.
2. **Restumfang im vereinbarten Scope:** Das Kriterium liegt im freigegebenen Parent-/Story-/Epic-Scope, ist aber noch durch kein passendes Issue repräsentiert. Product Owner plant fachliche User-Children; technische Children und technische Task-Verträge weist der Koordinator separat an Architektur. Das Child wird danach in den nativen Graphen eingeordnet und umgesetzt.
3. **Neue oder unklare Anforderung:** Das Kriterium würde Zielbild, Scope, Nicht-Ziele oder wesentliche Entscheidungen erweitern oder ist widersprüchlich. Der Ablauf kehrt zu `requirements-clarification` und zum Human-Gate zurück; eine stille Umsetzung ist nicht zulässig.

Vorhandene passende Issues werden wiederverwendet. Ein neues Child darf nur nach Prüfung auf Duplikate und nur für vereinbarten Restumfang entstehen. Nach der Remediation wird nicht nur das einzelne Kriterium, sondern die vollständige ursprüngliche Acceptance-Menge erneut geprüft.

## Remediation- und Konvergenzzyklus

Für einen `GAP` gilt folgende geschlossene Runde:

1. Gap klassifizieren und den betroffenen Scope sowie die erwartete neue Evidenz festhalten.
2. Bestehenden fachlichen Scope durch Product Owner und technischen Scope durch Architektur nachplanen; vereinbarten fachlichen Restumfang als User-Child und technischen Restumfang als Technical Child erfassen. Technical Tasks einschließlich Inhalts-, Type- und Relationship-Mutationen sowie technische Task-Verträge verantwortet Architektur.
3. Betroffene Issues gezielt mit `issue-implementation` auf dem vorhandenen Arbeitsbranch umsetzen und den Impact-Scope lokal bis zum `PASS` stabilisieren. Der aufrufende Graph behält Branch, Fortschrittsanker und finalen PR; Remediation startet keinen rekursiven `issue-graph-implementation`-Lauf und erzeugt keinen eigenen Branch oder PR. Fehlt ein geeigneter Arbeitsbranch, dessen Vorbereitung vor der Umsetzung separat klären.
4. Nach lokalem `PASS` die rollenbezogene Prüfung aus `issue-implementation` belegen: Backend-/Frontend-Diffs werden vom jeweiligen Implementierungsowner mit `code-minimization` minimiert; Infrastruktur prüft Scope und unbegründete Bestandteile mit `code-analysis`, korrigiert bei Bedarf mit `code-implementation` und liefert lokale `code-testing`-Belege. Bereits für denselben Stand vorliegende Belege übernehmen.
5. Die durch die Reduktion betroffene Verifikation fokussiert erneut ausführen. Fehlgeschlagene Reduktionen zurücknehmen; echte Unklarheit über Acceptance, Invariante oder Constraint als Plan-/Kontextbruch routen.
6. Danach den vollständigen ursprünglichen Root-Child-Graph erneut traversieren und fachliche Kriterien durch Product Owner, technische Kriterien durch Architektur sowie erforderliche unabhängige Regressionen durch QA erneut bewerten. Diese Full-Acceptance ist das finale Gate der Remediation.

Der Zyklus endet ausschließlich mit `PASS`, einem konkret begründeten `BLOCKED` oder einer ausdrücklichen Human-Entscheidung. Ein weiterhin bestehender `GAP` darf nicht als Erfolg gelten.

Zur Vermeidung von Endlosschleifen wird jede Remediation an die erwartete Zustandsänderung und neue Evidenz gebunden. Bleibt derselbe Gap nach einer abgeschlossenen identischen Remediation ohne relevante Zustandsänderung bestehen, wird nicht erneut dieselbe Maßnahme ausgeführt, sondern `BLOCKED` mit den bisherigen Befunden und dem fehlenden Fortschritt dokumentiert. Neue Anforderungen starten erneut am Human-/Requirements-Gate und werden nicht in diesen Loop eingeschleust.

## Rücksprungregeln

- Bei unklarem Root-Type, widersprüchlicher Hierarchie oder nicht prüfbarem Kriterium mit konkretem Grund `BLOCKED` ausweisen.
- Bei einem `GAP` an den definierten Remediation-/Konvergenzprozess zurückgeben.
- Nach einer Remediation die vollständige ursprüngliche Root-Menge erneut traversieren und prüfen.

## Endergebnis

- vollständig und zyklussicher erfasster Root-Child-Graph
- getrennte Kriterienmatrix für Root und jedes Child
- pro Kriterium ein eindeutiger Status mit Evidenz oder konkretem Blocker
- Rundenstatus `PASS`, `GAP` oder `BLOCKED` sowie terminaler Konvergenzstatus `PASS` oder `BLOCKED`
- keine automatische Issue-Schließung und keine stille Scope-Erweiterung

## Grenzen

- Keine Parent-Issues oberhalb des Roots automatisch prüfen.
- Keine Body-Links als native Child-Beziehungen interpretieren.
- Keine Akzeptanz aus Issue-, PR-, Commit- oder Teststatus allein ableiten.
- Keine Gaps automatisch implementieren oder neue Anforderungen erfinden.
