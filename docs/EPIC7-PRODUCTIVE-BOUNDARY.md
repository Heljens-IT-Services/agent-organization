# Epic 7: produktive Planung und verbleibende Runtimegrenze

Der technische Besitzer ist genau ein registrierter Koordinator-Rootjob mit gepinnter Launchkonfiguration, logischer Hostsession und Provider-/Prozessgeneration. Unabhängige fachliche Ziele sind Top-Level-WorkItems ohne parentId im selben Store. Koordinatorturns bleiben durch den vorhandenen Host-/Pipepfad serialisiert.

## Implementierter Anschluss

CoordinatorPlanning löst fachliche Wurzeln mit Zykluserkennung auf, verteilt bereite Arbeit über den bestehenden Prioritäts-/Root-Round-Robin und berücksichtigt deduplizierte aktive Ausführungen. Nur Agent-WorkItems mit teamleiter_* als Owner sind automatische Delegationskandidaten. Andere Owner bleiben zur Disposition des Koordinators im Wartezustand. Der Koordinator liest hierfür keine operativen Agentenindizes.

Die gepinnte Launchkonfiguration kann optional teamCapacities als Objekt mit Schlüsseln teamleiter_<team> und ganzzahligen Limits zwischen 1 und der globalen capacity enthalten. Ohne Teamlimit gilt das globale Budget. Host und Planung übernehmen ausschließlich diese expliziten Werte. CommitAdmissionReserve prüft die Teamgrenze zusätzlich unter dem vorhandenen Registrylock; Slotverbrauch wird nach der bestehenden Aliasunion dedupliziert. Unbekannte Arbeit sperrt weiterhin positive Admission.

Blockierte WorkItems bleiben bis zu einer fachlichen Resumeentscheidung blockiert. dueAt erzeugt bei erfüllter menschlicher Interaktion eine persistente Reminderdatei mit stabiler SHA256-Identität aus WorkItem, Revision und Fälligkeit. Datei-/Eventpublikation liegt vor dem Remindercursor. Wiederanlauf übernimmt die veröffentlichte Datei; terminale WorkItems erzeugen keine neuen Reminder. Der bestehende Importer und der propose_resume-/CAS-Pfad verarbeiten den Trigger, ohne bloße Fälligkeit als Startfreigabe zu behandeln. Leerlauf erzeugt keine Modellturns.

Delegation bleibt am vorhandenen SSOT-Starter: Der Job enthält dessen echten Bootstrap-Aufgabentext, während der Fachauftrag aus dem autoritativen WorkItem gelesen wird. Startbelege binden zusätzlich Startauthority und Elternkontext. Der vorbereitende Payloadhash bleibt getrennt vom späteren Authorityhash. Ein Prepared-Dispatch entsteht vor Admission; LaunchIntent entsteht erst nach tatsächlicher Reservation. Eine abgelehnte Admission wird nur bei zurückgelesener Abwesenheit einer Reservation, fehlenden Job-/Fensterbelegen und belegtem Prelaunchzustand als AdmissionDeferred mit nächstem technischen Versuch persistiert. Vorhandene LaunchIntent-/Running-/Recoveryzustände werden nicht neu gestartet. Auf Retry bleiben Authorityhash, StoreRevision und Elternkontext gepinnt; Änderungen benötigen explizite Recovery. Historische ungeklärte Intents werden nicht automatisch umgeschrieben.

## Gemeinsamer WorkItem-Dispatchvertrag

Automation und der unveränderte WorkItem-Starter verwenden denselben geordneten Dispatchinput: authorityPath, authorityHash, parentJobPath, parentJobHash, parentContextPath, parentContextHash, payloadHash, resultPath, role, workItemId, purpose, generation. Die Werte stammen aus der gepinnten Startauthority; payloadHash ist deren Bytehash. CoordinatorDispatch hasht den vollständigen kompakten JSON-Input für dieselbe WorkItem-/Purpose-/Generationidentität. Der Bootstrap-Aufgabentext ist daher kein zusätzliches task-Feld dieses Inputs.

Der Tasktextnachweis bleibt im Starteffect mit taskText/taskTextHash und im tatsächlichen Starterjob erhalten. Get-AutomationStartEvidence vergleicht den Jobtext mit dem gepinnten Effect und dem echten SSOT-Bootstrap, liest die Authoritybytes mit SHA256-Bindung erneut und rekonstruiert den vollständigen erwarteten Dispatchinput. Erwarteter Inputhash, gespeicherter Dispatchhash und zurückgelesener Input müssen übereinstimmen; Authority- und Elternkontext-/Elternjobbindungen bleiben zusätzlich erforderlich. Frühere Journale mit abweichendem Input werden nicht umgeschrieben oder unter derselben Identität neu gestartet; sie benötigen explizite Recovery.

## Verbleibende Grenze

Get-AdmissionInstalledContract liefert weiterhin completionMode=Unknown und benennt AtomicProviderCompletionMissing sowie NativeBirthFenceMissing. Initialize-CoordinatorRuntime sperrt deshalb vor thread/start bzw. thread/resume; CommitAdmissionReserve sperrt vor einer Reservation. Das ist fehlende produktive Anschlussfähigkeit und keine allein durch fehlende Probe verursachte Grenze.

Der benötigte Scope ist ausschließlich der tatsächlich gebundene technische Koordinatorbesitzer. Notwendig ist eine revisions-/generationsgebundene Runtimegarantie, die alle diesem Besitzer zugeordneten nativen Geburten vor Ausführung registriert und terminale Completion eindeutig bestätigt, zusammen mit atomarer Admissionreservation. Vorhandene Starterreservation, RegisterNative-ACK und terminaler Release decken instrumentierte Starterjobs ab; der gepinnte installierte Runtimevertrag belegt aber weder exklusive native Startkontrolle noch lückenlose Membership/Completion dieses Besitzers. Daher liefern diese lokalen Belege keinen Ersatz für die fehlende Garantie. Keine globalen Fremdthreads werden als neue Ownerverbindung erfunden; kein Boolean oder künstlicher ACK schaltet Unknown frei.

Die aktuelle Änderung liefert die unabhängigen Produktpfade, schließt #7/#17/#37 jedoch nicht vollständig. Ein realer Owner-scope Runtimeanschluss ist vor einem Erfüllungsclaim erforderlich.

## Nachweisgrenze

Nur Inhalt, Diff und Referenzreadback. Keine Tests, Parser-/Validatorläufe oder Runtime-/Native-/Browserproben. Umsetzung, unabhängiger Deltareview und Elternabnahme bleiben getrennt.

Die Aliasunion behandelt aktive Ausführungen ohne bekannte Rolle oder mit widersprüchlicher WorkItembindung konservativ als CapacityUnknown. Für Teamleiterarbeit muss genau eine autoritative WorkItembindung vorliegen. Historische unvollständige Registryeinträge werden nicht durch vermutete Zielzuordnung repariert.

AdmissionDeferred ist kein dauerhaftes Überspringen der Recoveryprüfung: Vor jeder weiteren Auswahl werden aktuelle Registry-, Dispatch- und Ergebnis-/Job-/Go-/Fensterdateien zurückgelesen. Verspätete Belege durchlaufen den regulären gepinnten Startnachweis; fehlende oder unlesbare Quellen führen zu persistiertem RecoveryRequired.
