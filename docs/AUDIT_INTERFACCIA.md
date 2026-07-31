# Audit Interfaccia, GUI e UX — Cuba Libre Digital

Data: 31 luglio 2026. Analisi completa del progetto allo stato attuale (branch `main`,
commit `53e492f`): tutto il codice della UI (`godot/scenes/`, ~3.300 righe), il controller
(`GameController.gd`), il motore (`coin_engine/` + `games/cuba_libre/`), i dati JSON,
la roadmap e i workflow di build/export (desktop + Web/GitHub Pages).

**Giudizio d'insieme.** Il progetto è in ottima salute: motore validato da test headless,
bot Calixto integrato, mappa reale con zone poligonali, drag-and-drop, animazioni,
tracciati con coordinate estratte da VASSAL, log compatto ed espandibile. La UI però è
cresciuta "per accumulo" attorno a un'unica scena ed è arrivata al punto in cui i limiti
sono soprattutto di **struttura e rifinitura**, non di funzionalità di gioco. Le sezioni
seguenti elencano ciò che manca e come migliorare, in ordine: funzionalità assenti,
UX dei flussi, GUI/layout, grafica, touch/iPad, accessibilità, qualità del codice UI.
In fondo, una tabella di priorità consigliate.

---

## 1. Cosa manca — funzionalità

### 1.1 Regole non ancora complete (impattano ciò che la UI può offrire)

Confermate incrociando `docs/ROADMAP.md` con il codice:

| Mancanza | Stato nel codice | Impatto |
|---|---|---|
| **Riciclaggio (Launder)** non collegato alla sequenza | assente da `SequenceOfPlay`/UI | Il Sindacato umano non può riciclare Denaro nel flusso di turno |
| **Redeploy del Governo** solo automatico | `Propaganda.redeploy_phase()` decide tutto da sola | Un Governo **umano** subisce scelte di ridistribuzione che per regolamento sono sue |
| **Capacità/Momentum**: registrati ma non applicati alle Operazioni | `state.active_capabilities` mostrato sulla mappa, ma `Operations.gd` non li consulta | Le carte a effetto duraturo "esistono" solo visivamente: le Operazioni non ne risentono |
| **Adiacenze mappa da verificare** | nota in roadmap (Fase 0) | Rischio di Marce/Perlustrazioni verso spazi sbagliati |
| Bot: tie-breaker e tabella Spazi Casuali (8.2–8.3) da rifinire; ordine 1ª/2ª e scelta Evento nel loop da affinare | roadmap Fase 4 | Fedeltà del solitario |

### 1.2 Funzionalità di interfaccia assenti (il motore spesso è già pronto)

1. **Salvataggio/caricamento partita.** Il motore ha già `GameState.to_dict()/load_dict()/from_dict()`
   (usati per l'undo e per `can_special`), ma **non esiste alcun pulsante Salva/Carica**.
   Su Web basta `user://` + eventualmente download/upload JSON. È la mancanza più
   sproporzionata rispetto allo sforzo richiesto: una partita COIN dura ore e oggi si
   perde chiudendo la scheda.
2. **Nessun menu principale / schermata titolo.** `GameController._ready()` chiama
   `new_game()` e si parte subito in partita con i ruoli di default. Manca un punto dove
   scegliere scenario, ruoli, opzioni prima di iniziare.
3. **Scenari e gioco breve non esposti.** `new_game(scenario)` accetta un parametro e
   `build_deck(short := true)` esiste (mazzo da 40 carte), ma la UI non li offre mai.
   La roadmap (Fase 5) prevede Standard/Variabile/breve: il "breve" è a un pulsante di distanza.
4. **"Nuova Partita" senza conferma.** Il pulsante è nella barra, in mezzo ai comandi usati
   di frequente, e azzera tutto all'istante. Serve un dialogo di conferma (e, insieme al
   punto 1, un autosalvataggio di sicurezza).
5. **Undo a un solo livello.** `GameController._undo` è una singola istantanea e non
   attraversa il confine di carta. Con `to_dict()` già disponibile, uno stack di N
   istantanee è quasi gratis e cambierebbe la vita a chi impara il gioco.
6. **Nessun pannello Vittoria numerico.** `GameController.victory()` espone
   valore/soglia/margine per tutte le fazioni, ma in partita si vedono solo i segnalini
   sul tracciato 0–49; i numeri compaiono nel log **a fine partita**. Un riquadro sempre
   visibile ("Govt 15/20, 26J 9/12, …" con barre colorate) è informazione centrale in un COIN.
7. **Round di Propaganda non interattivo.** `resolve_propaganda()` risolve tutte le fasi
   in automatico anche per le fazioni umane (Risorse, Supporto, Redeploy). Il giocatore
   dovrebbe almeno scegliere le proprie azioni della fase Supporto (Civica/Dimostrazioni)
   e il Redeploy (§1.1). Oggi il round è un blocco di log che scorre.
8. **Ingrandimento della carta Evento.** Le immagini carta sono 150×200 px: il testo è
   illeggibile. Manca il click-per-ingrandire (overlay a schermo intero), pattern standard
   nelle edizioni digitali di giochi di carte.
9. **Aiuto in gioco.** Le descrizioni di Operazioni/Attività Speciali vivono **solo nei
   tooltip** dei tasti (`OP_DESC`/`SA_DESC`); non c'è una schermata di riferimento
   consultabile (né il `RULES_DIGEST.md`, già scritto, è raggiungibile dal gioco). Manca
   anche il tutorial previsto in Fase 5.
10. **Impostazioni assenti**: nessuna schermata opzioni (velocità è nella barra, il resto
    non esiste), **nessun audio** (nemmeno feedback minimi su click/piazzamento/fine turno),
    nessun toggle schermo intero.
11. **Statistiche/replay.** `stats` conta le azioni ma non è mai mostrato; a fine partita
    non c'è una schermata riepilogo (solo righe di log).

---

## 2. UX — flussi e feedback

### 2.1 Il click-che-cicla è poco scopribile e fragile

Train/Rally/Build/Attack usano il pattern "riclicca lo spazio per cambiare scelta"
(`_train_click`, `_rally_click`, `_build_click`, `_attack_click`): il click cicla
cubi 1→2→3→4→Base→Civica→**deseleziona**. Problemi:

- **Scopribilità**: nulla sullo spazio indica che si può ricliccare né quale sia la scelta
  corrente; lo stato vive solo nella riga di istruzioni in alto, lontana dal punto di click.
- **Errore costoso**: superare per sbaglio il valore voluto obbliga a rifare l'intero giro
  (fino a 6 click); non c'è un "torna indietro" (es. click destro).
- **Incoerenza**: per Trasporto/Muscle il numero si cicla ricliccando la *destinazione*,
  per Train ricliccando lo *spazio*; per Garrison il click sull'EC fa una terza cosa.

**Proposte** (in ordine di costo): (a) click destro = cicla all'indietro / deseleziona
diretto; (b) badge sullo spazio selezionato con la scelta corrente ("2 Truppe", "Base",
"Civica") — oggi il selezionato ha solo il bordo giallo; (c) piccolo popup contestuale
sullo spazio con +/− e le opzioni esplicite, che eliminerebbe il ciclo alla cieca.

### 2.2 "Annulla" fa due cose diverse

`_on_cancel()` prima scarta la preparazione in corso e, se non c'era nulla da scartare,
fa l'**undo** dell'ultima azione eseguita. Stesso tasto, due semantiche opposte
(distruttiva/non distruttiva), esito scoperto solo dal messaggio dopo il click.
Meglio due tasti: "Annulla selezione" (attivo solo con `_mode != "idle"`) e
"⟲ Annulla ultima azione" (attivo solo con `can_undo()`), con etichette di stato chiare.

### 2.3 "Esegui" vs "Concludi" 

`Esegui` applica l'Operazione, `Concludi` esegue *e* chiude il turno
(`_on_execute_and_end`). Funziona, ma: il verde accentato è su **Esegui**, mentre il
tasto risolutivo è Concludi (colorato solo nel font, lime su grigio); dopo un "Esegui"
riuscito nulla dice esplicitamente "ora puoi fare l'Att.Speciale o Concludere". Un
mini-stepper visivo del turno (1 Operazione → 2 Att.Speciale (opz.) → 3 Concludi), con
lo stato corrente evidenziato, renderebbe il flusso autoesplicativo — oggi è tutto
affidato alla riga gialla di istruzioni.

### 2.4 La riga di istruzioni tronca il testo

`instr_box` è alto fisso 38 px con `clip_contents = true` (scelta fatta per non far
"ballare" la mappa): i messaggi lunghi — proprio le istruzioni dei flussi multi-passo,
o gli errori — vengono **tagliati senza ellissi né modo di leggerli**. Alternative che
non muovono il layout: tooltip/click sulla riga per il testo completo, marquee, o
spostare le istruzioni in un banner overlay semi-trasparente sopra la mappa (non nel
flusso del layout).

### 2.5 Errori e legalità

- La validazione UI è "best-effort" (`_valid_spaces`) e il motore rivalida all'esecuzione:
  giusto, ma quando il motore rifiuta, l'errore va **solo nel log** (`! ...`) mentre lo
  sguardo dell'utente è sulla mappa. Portare l'errore anche nella riga istruzioni/banner
  (in rosso) e far lampeggiare in rosso lo spazio incriminato.
- **Niente anteprima dei costi**: le Operazioni costano Risorse ma la UI non mostra
  "costo: 3 × N spazi = 9, hai 12" prima di Esegui. Con la simulazione su copia già usata
  per `can_special`, un'anteprima "cosa succederà" (costo + effetti principali) è fattibile
  e preverrebbe la maggior parte degli Esegui falliti.
- Le operazioni di movimento (`garrison/march/sweep`) evidenziano **tutti** gli spazi
  (`ok = true`): il primo click di un drag non ha guida su origini sensate. Evidenziare
  almeno gli spazi con pezzi propri trascinabili.

### 2.6 Scorciatoie da tastiera: zero

Nessun `shortcut`, nessun `_unhandled_input`. Minimo consigliato: `Esc` = annulla
selezione, `Invio` = Esegui, `Spazio` = Concludi/Avanti, `+`/`-`/rotellina = zoom,
frecce/trascinamento col tasto centrale = pan. Su desktop è la differenza tra UI fluida
e UI "tutta a mouse".

### 2.7 Turni dei bot e ritmo

Il timer `_auto_bot_tick` (1 s) + `pace_delay` funziona, ma: durante `run_full_game_paced`
non c'è un tasto **Pausa/Stop** (si può solo aspettare la fine o chiudere); il tasto
"Gioca la fazione di turno" resta abilitato anche quando è il turno di un umano.
Aggiungere: Stop dell'auto-play, e un indicatore visivo persistente "AUTO" quando attivo.

---

## 3. GUI e layout

### 3.1 La barra superiore fa troppe cose

Nella stessa barra convivono: azioni di turno (Operazioni, Att.Speciali, Evento,
Concludi/Passa/Annulla), configurazione (Ruoli 2×2, velocità), automazione (4 tasti bot),
gestione partita (Nuova Partita) e vista (3 tasti zoom). Sono **tre categorie di frequenza
d'uso** mescolate: le azioni di turno servono ogni 10 secondi, i ruoli una volta a partita,
lo zoom quasi mai (la mappa è già "sempre adattata").

Proposta di riorganizzazione, senza stravolgere:
- **Riga 1 (contestuale al turno)**: banner + Operazioni/Att.Speciali/Evento/Turno — com'è oggi.
- **Riga 2 → menu/aside**: Ruoli, velocità, auto-bot e Nuova Partita in un pannello
  "Partita ⚙" apribile (o nel futuro menu principale); zoom sostituito da rotellina +
  pinch e da un solo tasto "Adatta".
- I tasti Operazione potrebbero mostrare **icone** (già esistono gli sprite dei pezzi)
  accanto al testo: a regime si riconoscono a colpo d'occhio.

### 3.2 Pannello laterale

- Le due carte (corrente/prossima) a 150×200 sono giuste come *presenza*, illeggibili come
  *contenuto* (→ §1.8 click-to-zoom). La sintesi italiana `it` esiste per tutte le 48 carte
  e viene mostrata: bene; ma i testi `unshaded`/`shaded` strutturati sono vuoti nel JSON
  (c'è solo `text_raw` OCR) — completarli permetterebbe di mostrare i due lati separati
  accanto ai tasti "- chiaro / - ombr." (che oggi sono etichette criptiche: rinominarle
  "Evento (chiaro)" / "Evento (ombreggiato)", o meglio due zone cliccabili sull'anteprima carta).
- **Log**: la compattazione recente è buona. Mancano: filtro per fazione/tipo (chip
  cliccabili), ricerca, e "copia/esporta log" (utile anche per segnalare bug). Il taglio a
  300 righe è silenzioso: aggiungere una riga "… (N righe precedenti omesse)".
- Il pannello non ha un riquadro **Vittoria** (§1.6) né un riquadro "stato fazioni"
  (Risorse/Aiuti in numero): oggi i numeri si leggono solo contando le celle del
  tracciato sulla mappa. Nota: `_faction_label` è dichiarato in `Main.gd` ma mai
  costruito — probabile residuo del vecchio pannello fazioni.

### 3.3 Layout hardcoded

`_layout_board()` usa costanti cablate: aspect `2040.0/2640.0` (che è il rapporto
dell'immagine mappa: andrebbe letto da `CLAssets.map()`), pannello 360–470 px, soglie
varie. Sotto ~1100 px di larghezza la mappa scende sotto i 700 px e i tasti della barra
vanno su 3+ righe. Definire un breakpoint esplicito (pannello sotto la mappa, o a
scomparsa) renderebbe il layout prevedibile su finestre piccole e su iPad.

---

## 4. Grafica

- **Stile**: la palette scura (#12161c, bordi #4a5666, accenti giallo/verde) è coerente e
  sobria; i colori fazione sono quelli canonici. Buona base.
- **Pezzi piccoli e affollamento**: token 23–27 px con passo che scende fino a 8 px
  (`MIN_STEP`): negli spazi pieni i pezzi si sovrappongono per ~2/3 e diventano difficili
  sia da leggere sia da **trascinare** (bersagli minuscoli e coperti). Alternativa robusta:
  oltre N pezzi per gruppo, mostrare **un token con badge numerico** ("×4") invece di 4
  sprite sovrapposti — riduce l'affollamento e il churn di nodi (v. §7).
- **Nessun feedback hover sugli spazi**: solo il tooltip col nome. Un leggero glow del
  contorno al passaggio del mouse (già c'è `_draw` con outline) chiarirebbe cosa è
  cliccabile, soprattutto per i poligoni delle province.
- **Evidenziazione valida ma monotona**: il giallo è usato per highlight, istruzioni,
  divisori log e Directorio. Differenziare: highlight degli spazi validi in
  azzurro/bianco pulsante, selezione confermata in verde, bersagli SA in viola — oggi
  "valido" e "selezionato" hanno lo stesso identico bordo giallo (si distinguono solo
  per il flash momentaneo).
- **Animazioni**: l'effetto cometa è piacevole; il salto sopra i 24 movimenti
  (`ghosts.size() > 24 → return`) però fa sparire *tutte* le animazioni proprio nei
  momenti spettacolari (Propaganda/Redeploy). Meglio animare i primi ~24 e teletrasportare
  il resto, o scalare la durata.
- **Testo**: font di default di Godot a 9–12 px ovunque. Caricare un font con più peso
  (es. una sans con bold vera — il log "inclina i glifi" per simulare il corsivo) e
  alzare la taglia base a 13–14 px migliorerebbe molto la percezione di qualità.
- **Identità**: manca un'icona/splash dell'app (export con icona di default Godot) e un
  titolo/logo nella (futura) schermata iniziale.

---

## 5. Touch, iPad e Web

Il README promette esplicitamente "apribile anche da Safari su iPad", quindi il touch va
trattato come primo cittadino. Oggi:

1. **Le descrizioni di Op/SA esistono solo nei tooltip** → su touch non compaiono mai
   (niente hover). Le sintesi già scritte in `OP_DESC`/`SA_DESC` andrebbero mostrate
   anche nella riga istruzioni al primo tap sul tasto (tap = seleziona e mostra, secondo
   tap = conferma), o in un pannellino "?".
2. **Niente pinch-zoom né doppio-tap**; lo zoom è solo a pulsanti. Il pan via
   ScrollContainer col dito funziona ma **confligge col drag dei pezzi** (stesso gesto:
   trascinare); serve la distinzione canonica: drag su un pezzo = pezzo, drag sul fondo
   = pan.
3. **Bersagli minuscoli**: tasti alti ~22 px e pezzi 23 px sono molto sotto i ~44 pt
   raccomandati per il touch. Una "modalità touch" (rilevabile da
   `DisplayServer.is_touchscreen_available()`) con font/tasti/pezzi scalati ~1.5×
   risolverebbe senza toccare il layout desktop.
4. Dettagli export Web ok (canvas resize, no-thread per compatibilità Safari); valutare
   `progressive_web_app/enabled = true` per l'installazione su home screen dell'iPad.

---

## 6. Accessibilità

- **Solo il colore distingue le fazioni** (cubi/tondi colorati, log a fondino colorato).
  Rosso M26 vs verde Sindacato è la coppia critica per deuteranopia. Mitigazioni a basso
  costo: i pezzi hanno già forme diverse per *tipo* ma non per fazione — aggiungere
  sigla (26J/DR/SYN/GOV) nel tooltip c'è già; nel log la sigla è nel testo: bene;
  valutare un contorno/pattern distintivo sui token e testare la palette con un
  simulatore di daltonismo.
- Font 9–12 px non scalabili: aggiungere un'impostazione "dimensione testo" (Godot:
  basta un `theme.default_font_size` moltiplicato).
- Nessuna navigazione da tastiera/focus visibile (i Button hanno focus stylebox vuota
  in `PieceToken`, e non c'è tab-order pensato). Priorità bassa per un gioco da mappa,
  ma le scorciatoie di §2.6 coprono l'essenziale.

---

## 7. Qualità del codice UI (manutenibilità)

1. **`Main.gd` è un monolite da 1.755 righe**: costruzione UI, theming, layout, log,
   animazioni e *tutta* la macchina a stati dei flussi (`_mode` con 8+ valori, 15 variabili
   di stato transitorio azzerate a mano in `_clear_pending`). È il rischio n.1 di
   regressioni. Refactor suggerito, senza cambiare comportamento:
   - `ActionFlow.gd` (macchina a stati di Op/SA con i dizionari di scelta),
   - `ActionBar.gd` / `SidePanel.gd` (costruzione e refresh),
   - `LogView.gd` (rendering + espansione logica),
   - un `Theme` **risorsa unica** al posto dei 4 punti che duplicano gli stessi StyleBox
     (`_mk_btn`, `_mk_menu_btn`, `_mk_btn_restyle`, `_accent_btn`).
2. **Codice morto**: `SpaceView.gd` intero (sostituito da `RegionView`, nessun riferimento),
   la costante `LAYOUT` in `Main.gd` (sostituita da `regions.json`), `_faction_label`
   (dichiarata, mai usata). Da rimuovere per non confondere i prossimi interventi.
3. **Refresh distruttivo**: `RegionView.refresh()` fa `queue_free()` di tutti i token e li
   ricrea a ogni `state_changed` (e `_render_log` ricostruisce l'intera BBCode string).
   Su desktop è invisibile, sull'export Web con molte animazioni è churn evitabile:
   aggiornare solo gli spazi cambiati (il fingerprint `_space_fp` esiste già e può fare
   da diff) e appendere al log invece di rigenerarlo.
4. **Duplicazioni motore/UI**: `OP_NAMES`/`_OP_IT` e `SA_NAMES`/`_SA_IT` sono due coppie di
   dizionari identici in file diversi; le regole di validità di `_valid_spaces` duplicano
   in forma semplificata la logica del motore (accettabile come best-effort, ma da
   commentare come tale in un punto solo).
5. `Main.tscn` è un nodo vuoto + script: va bene, ma spostare la costruzione in scene
   `.tscn` composte renderebbe l'editing visuale possibile (facoltativo, gusto personale).

---

## 8. Priorità consigliate

| # | Intervento | Impatto | Sforzo |
|---|---|---|---|
| 1 | Salva/Carica partita (+ autosave, motore già pronto) | Alto | Basso |
| 2 | Conferma su "Nuova Partita" | Alto | Minimo |
| 3 | Click-to-zoom della carta Evento | Alto | Basso |
| 4 | Pannello Vittoria/Risorse numerico sempre visibile | Alto | Basso |
| 5 | Riga istruzioni non troncata (overlay/tooltip) + errori in rosso fuori dal log | Alto | Basso |
| 6 | Touch di base per iPad: descrizioni senza hover, pinch-zoom, target 1.5× | Alto | Medio |
| 7 | Propaganda interattiva per fazioni umane (Supporto + Redeploy) | Alto | Medio |
| 8 | Capacità/Momentum applicati alle Operazioni + Launder in sequenza (regole) | Alto | Medio |
| 9 | Undo multi-livello | Medio | Basso |
| 10 | Scorciatoie tastiera (Esc/Invio/rotellina) | Medio | Basso |
| 11 | Separare "Annulla selezione" da "Annulla ultima azione" | Medio | Minimo |
| 12 | Anteprima costi/effetti prima di "Esegui" | Medio | Medio |
| 13 | Menu principale + scenari/gioco breve + impostazioni | Medio | Medio |
| 14 | Badge numerici sui pezzi impilati + hover sugli spazi + palette highlight differenziata | Medio | Medio |
| 15 | Refactor `Main.gd` (ActionFlow/Theme/viste) e rimozione codice morto | Medio (abilitante) | Medio |
| 16 | Filtro/copia log, riepilogo di fine partita, statistiche | Basso | Basso |
| 17 | Audio minimo, icona app, font migliore | Basso | Basso |
| 18 | Tutorial interattivo / aiuto regole in gioco | Alto (nuovi utenti) | Alto |

Le voci 1–5 sono il "pacchetto qualità percepita": tutte a basso sforzo perché
l'infrastruttura (serializzazione, texture carte, `victory()`, simulazione su copia)
esiste già; insieme cambierebbero sensibilmente l'esperienza quotidiana di gioco.

> **Aggiornamento** — le voci **1–5** sono state implementate insieme a questo audit:
> menu "Partita…" con Salva/Carica/Riprendi autosalvataggio (autosave a ogni azione,
> incluso l'ordine del mazzo Calixto dei bot), conferma su Nuova Partita, click sulle
> carte per ingrandirle a schermo intero, pannello **Vittoria** numerico
> (valore/soglia/margine + Risorse, Aiuti, Alleanza USA) nel pannello laterale, riga
> istruzioni con tooltip a testo pieno ed errori mostrati **in rosso** (compresi i
> rifiuti del motore su Esegui/Attività Speciali, che ora non chiudono il turno).
> Rimosso anche il codice morto `_faction_label`.

> **Aggiornamento 2** — implementate anche le voci **6–8**:
> **(6)** zoom con rotellina del mouse e pinch a due dita, centrato sul puntatore;
> scala UI maggiorata (~25%) sugli schermi touch (iPad). **(7)** Round di Propaganda
> **interattivo** per le Fazioni umane: Azione Civica, Dimostrazioni e Supporto
> Espatriati si giocano cliccando gli spazi evidenziati (i bot mantengono il loro
> comportamento automatico; il Redeploy resta automatico, voce aperta in roadmap).
> **(8)** Riciclaggio (2.3.6) collegato alla sequenza con pulsante dedicato e LimOp
> extra gratuita; completati i Momentum operativi mancanti (Armored Cars, Rolando
> Masferrer, MAP, Raúl) — le 7 Capacità Insorgenti risultavano già applicate nelle
> Operazioni. Tutto coperto da test (250 headless).

> **Aggiornamento 3** — implementate le voci **9–12**:
> **(9)** Annulla **multi-livello** (pila di 20 istantanee, ripetibile fino all'inizio
> della carta; il tasto mostra quante azioni restano e quale sarà disfatta; un'azione
> fallita non sporca la pila; lo stato del Riciclaggio viene ripristinato con essa).
> **(11)** I due significati di "Annulla" sono ora **due tasti distinti**: *Annulla sel.*
> (scarta la preparazione, mai distruttivo) e *Annulla azione* (disfa l'eseguito),
> ciascuno attivo solo quando ha senso. **(10)** Scorciatoie da tastiera: `Esc` annulla
> la selezione, `Invio` esegue, `Spazio` conclude il turno, `Ctrl+Z` disfa, `+`/`-`/`0`
> regolano la vista (i tasti non trattengono più il focus). **(12)** **Anteprima**
> accanto a "Esegui": costo in Risorse rapportato a quelle disponibili (verde/rosso),
> `GRATIS` per la LimOp del Riciclaggio, `⚠ non eseguibile` con il motivo *prima* di
> premere, e l'elenco degli effetti previsti nel tooltip — il tutto simulando
> l'Operazione su una copia dello stato, senza toccare la partita.
> Copertura: **262 test headless**.

> **Aggiornamento 4** — **Spostamento (Redeploy) interattivo** per il Governo umano,
> ultimo pezzo di regole che restava automatico. La fase 6.4 si gioca trascinando i
> cubi sulla mappa con le destinazioni validate dal regolamento: la Polizia può andare
> in qualsiasi EC o spazio a Controllo del Governo (6.4.1), le Truppe solo in Città o
> spazi con Base a Controllo del Governo (6.4.2/6.4.3). Gli spazi che le Truppe DEVONO
> lasciare (EC e Province senza Base) sono evidenziati e "Concludi" li rifiuta finché
> restano occupati. Con il Governo affidato al NP resta la procedura automatica di
> Calixto. Copertura: **277 test headless**.
>
> Nota di regolamento emersa dai test: lo schieramento standard mette 3 Truppe a
> Las Villas, Provincia priva di Base del Governo — vanno quindi ricollocate già al
> primo Round di Propaganda.

> **Aggiornamento 5** — avviato il **refactor** (voce 15), prima fetta: estratta
> `ActionFlow` (`godot/scenes/ActionFlow.gd`), la pianificazione dell'Operazione in
> preparazione — spazi scelti, ciclo delle varianti (cubi/Base/Civica, bersaglio
> dell'Attacco, Casinò), coda degli spostamenti, `build_params()` e `valid_spaces()`.
> È un `RefCounted` **senza dipendenze dalla scena**: non tocca viste né etichette,
> espone stato, `highlights()` e `message`, e la scena si limita a disegnare. Il punto
> non era accorciare il file (`Main.gd` 2.214 → 1.920 righe) ma **rendere collaudabile
> la logica di flusso**, che prima non aveva un solo test: ora ne ha 27.
> Creato anche `CLNames` (`games/cuba_libre/CLNames.gd`) come unica fonte dei nomi
> italiani di Operazioni, Attività Speciali e pezzi, al posto dei dizionari duplicati
> tra `Main.gd` e `GameController.gd` (`_OP_IT`/`_SA_IT` rimossi).
> L'estrazione ha fatto emergere una guardia mancante: `start()` ora rifiuta
> un'Operazione che la Fazione non possiede (prima ci si affidava al fatto che la
> scena non costruisse quel tasto). Copertura: **304 test headless**.
>
> Restano da estrarre, nell'ordine previsto: flussi delle Attività Speciali, `LogView`,
> `SidePanel`, `MapAnimator` e il `Theme` come risorsa unica; poi la rimozione del
> codice morto (`SpaceView.gd`, costante `LAYOUT`).

> **Aggiornamento 6** — refactor, seconda fetta: estratta **`SpecialFlow`**
> (`godot/scenes/SpecialFlow.gd`), la macchina a stati delle Attività Speciali —
> la parte più intrecciata della scena, con cinque passi diversi (bersaglio singolo,
> spostamento del secondo passo della Rappresaglia, origine → destinazione → numero
> di cubi per Trasporto/Muscle, selezione dei Casinò per il Profitto) e le varianti
> di Sequestro/Profitto/Corruzione. Come `ActionFlow` non conosce la scena e **non
> tocca la partita**: `click()`/`confirm()` restituiscono `{ok, error, run}` dove
> `run` dice al chiamante *quale* Attività eseguire e con quali parametri, così la
> scena resta un disegnatore e il flusso è collaudabile headless (30 test nuovi).
> Rimosso il codice morto segnalato dall'audit: `SpaceView.gd` (128 righe mai
> referenziate) e la costante `LAYOUT`, superata da `regions.json`.
> `Main.gd` scende da 2.214 a **1.624 righe**; copertura **334 test headless**.
>
> Restano da estrarre: `LogView`, `SidePanel`, `MapAnimator` e il `Theme` unico.

> **Aggiornamento 7** — refactor, terza fetta: estratti **`LogView`** (registro che si
> impagina da sé: la scena chiama `add_line()`/`add_decision()` e non tocca più il
> BBCode), **`MapAnimator`** (scie dei pezzi e lampeggi, calcolati per differenza sui
> conteggi) e **`CLTheme`**, unico posto dove vivono colori e riquadri dei comandi —
> prima gli stessi StyleBox erano ricostruiti a mano in quattro funzioni diverse, con
> il rischio che un ritocco ne raggiungesse solo una parte. Risolta lungo la strada
> anche la segnalazione dell'audit sul **taglio silenzioso del log**: superate le 300
> righe, ora compare "… N righe precedenti omesse".
> `Main.gd` scende a **1.370 righe** (da 2.214 di partenza, −38%).
>
> Stato del refactor: fatti `ActionFlow`, `SpecialFlow`, `LogView`, `MapAnimator`,
> `CLTheme`, `CLNames` e la rimozione del codice morto. Resta `SidePanel` (carte +
> pannello Vittoria), l'ultima estrazione prevista.

> **Aggiornamento 8** — refactor completato: estratto **`SidePanel`** (carte corrente e
> prossima, sintesi dell'Evento, pannello Vittoria e registro). Si aggiorna da sé con
> `refresh()` ed emette `card_zoom_requested` invece di costruire l'overlay, che è a
> schermo intero e non gli appartiene. Le sigle delle Fazioni finiscono in `CLNames`,
> ultimo dizionario che era duplicato.
>
> Aggiunto `tests/scene_smoke.gd`, che **istanzia davvero la scena principale** in
> headless e la esercita (montaggio dei componenti, segnali del log, aggiornamento
> completo, tre turni bot, salva/carica con la UI viva): è la rete che mancava, perché
> i test unitari non catturano gli errori di montaggio. Ora gira anche in CI a ogni push.
>
> **Bilancio del refactor**: `Main.gd` da **2.214 a 1.212 righe** (−45%), con la logica
> distribuita in `ActionFlow` (487), `SpecialFlow` (388), `MapAnimator` (181),
> `SidePanel` (137), `LogView` (111), `CLTheme` (72) e `CLNames`. La logica di flusso,
> che all'inizio non aveva un solo test, ne ha 57. Totale: **334 test headless**
> più lo smoke test di scena.

> **Aggiornamento 9** — **schermata iniziale e scenari** (voce 13 dell'audit).
> `MainMenu` è ora la scena principale: titolo sulla mappa attenuata, scelta dello
> **scenario** (Standard o Schieramento Variabile), interruttore **partita breve**,
> assegnazione dei ruoli Giocatore/Bot per tutte e quattro le Fazioni, ripresa
> dell'autosalvataggio e voce **"Gioca online"** predisposta ma disattivata, in attesa
> dell'implementazione. Dalla partita si torna al menu dal menu "Partita…", e a fine
> partita compare da sé un riepilogo con i punteggi e la proposta di rientrare.
>
> Lato motore, `apply_setup` ignorava il parametro scenario: ora implementa lo
> **Schieramento Variabile** (regolamento p.30) sorteggiando le posizioni entro i
> vincoli — Casinò e Basi mai negli EC, al massimo 1 Guerriglia 26J per Città, forze
> del Governo nelle Città più una sola Provincia. Il regolamento lascia la scelta ai
> giocatori: qui è casuale, e serve a variare l'apertura. Lo Standard resta
> riproducibile identico. Scenario e partita breve entrano nel salvataggio.
> Copertura: **348 test headless** (14 nuovi sugli scenari) più lo smoke test di scena,
> esteso al menu e al passaggio menu → partita.

