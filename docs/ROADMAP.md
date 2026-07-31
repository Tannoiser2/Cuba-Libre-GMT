# Cuba Libre Digital — Roadmap di Sviluppo

Obiettivo: realizzare una versione digitale giocabile di **Cuba Libre** (Serie COIN).

## Materiali sorgente (in `sources/`)
- `rules/Cuba_Libre_Regolamento_ITA.pdf` — regolamento italiano completo.
- `rules/Cuba_Libre_Playbook_2018_ENG.pdf` — esempio guidato, note di strategia, regole Bot.
- `vassal/Cuba_Libre_1.3.2.vmod.zip` — modulo VASSAL: immagini (mappa, carte, schede,
  segnalini) e `buildFile` (definizioni pezzi/spazi). Ottima fonte di asset grafici.

## Stack tecnologico
- **Godot 4.3** (desktop), GDScript.
- Architettura a due livelli: **motore COIN generico** (`godot/coin_engine/`) riusabile
  per altri giochi della serie, e **modulo Cuba Libre** (`godot/games/cuba_libre/`).

## Modello dati (in `godot/games/cuba_libre/data/`)
- `spaces.json` — spazi mappa (tipo, terreno, Pop/Econ, adiacenze*).
- `factions.json` — fazioni, forze, operazioni, attività speciali, vittoria.
- `setup_standard.json` — schieramento standard.
- `cards.json` — scheletro delle 52 carte (testi da completare).

\* adiacenze da verificare sulla mappa fisica.

## Fasi

### Fase 0 — Fondamenta (in corso)
- [x] Caricare i materiali sorgente nel repo.
- [x] Leggere e sintetizzare il regolamento (`docs/RULES_DIGEST.md`).
- [x] Estrarre il modello dati iniziale (spazi, fazioni, setup, lista carte).
- [x] Scegliere lo stack tecnologico (Godot 4) e impostare il progetto.
- [x] Architettura motore COIN generico + modulo Cuba Libre.
- [ ] Verificare le adiacenze della mappa.

### Fase 1 — Motore di gioco (core engine)
- [x] Modello degli spazi, forze, marker, tracciati (classi generiche).
- [x] Controllo, Supporto/Opposizione, calcolo dei tracciati di vittoria.
- [x] Caricamento dati + schieramento standard, validati da test headless.
- [x] Stato di gioco: serializzazione (save/load JSON).
- [x] Sequenza di gioco: carta Evento, Disponibilità, Passare, opzioni 1ª/2ª Fazione, Carta Finale.
- [x] Operazioni (Train/Garrison/Sweep/Assault, Rally/March/Attack/Terror/Build) + test.
- [x] Attività Speciali (tutte le 12) + test.
- [x] Sistema Denaro (Cash) — segnalini, proprietà, trasferimento, limite 4.
- [x] Riciclaggio (Launder) collegato alla sequenza di gioco (2.3.6: Denaro -> LimOp extra gratuita, UI inclusa).
- [x] Round di Propaganda (Vittoria, Risorse, Supporto, Sistemazione) + test.
- [x] Condizioni e margini di vittoria.
- [x] Test unitari del motore (147 test headless).
- [x] Spostamento (Redeploy) del Governo: automatico per il NP, interattivo per l'umano.

### Fase 2 — Carte ed Eventi
- [x] Ordine fazioni di tutte le 48 carte (dai simboli) + testo OCR in `cards.json`.
- [x] Caricamento carte nel `GameDef`.
- [x] Framework Eventi (`Events.gd`): gestori per carta + fallback "manuale".
- [x] Registrazione Capacità Insorgenti / Momentum del Governo.
- [x] Effetti automatizzati per TUTTE le 48 carte (entrambi i lati), smoke test 96/96.
- [x] Applicare nelle Operazioni i modificatori duraturi di Capacità/Momentum: tutte le 7
      Capacità (Guantánamo Bay, El Che, Pact of Caracas, Morgan, Guerrilla Life, Mafia
      Offensive, Santo Trafficante) e i Momentum (S.I.M., Sánchez Mosquera, Armored Cars,
      Rolando Masferrer, MAP, Raúl) hanno effetto operativo, con test.

### Fase 3 — Interfaccia utente
- [x] Mappa interattiva (schematica) con pezzi trascinabili e stato leggibile.
- [x] Pannelli Fazione, tracciati, log delle azioni.
- [x] Flusso guidato per le Operazioni (selezione spazi + drag-and-drop) + Round Propaganda.
- [x] Grafica: mappa reale di sfondo, spazi posizionati alle coordinate reali, pezzi e
      marcatori come sprite (Controllo/Supporto/Terrore/Denaro), drag-and-drop con anteprima.
- [ ] Rifinire le coordinate degli spazi e le dimensioni dei pezzi.
- [x] Flussi guidati per Attività Speciali (menu per fazione) ed Eventi (lato chiaro/ombreggiato) nella UI.
- [x] Salva/Carica partita dalla UI (menu Partita) con autosalvataggio a ogni azione.
- [x] Conferma su Nuova Partita; zoom della carta Evento; pannello Vittoria/Risorse;
      errori in rosso nella riga istruzioni (tooltip a testo pieno).
- [x] Round di Propaganda interattivo per le Fazioni umane: Azione Civica (6.3.2),
      Dimostrazioni (6.3.3), Supporto Espatriati (6.3.4) guidati sulla mappa.
- [x] Zoom con rotellina/pinch centrato sul puntatore; scala UI maggiorata su touch (iPad).
- [x] Annulla multi-livello (20 istantanee) e tasti distinti selezione/azione.
- [x] Anteprima di costo ed effetti prima di "Esegui" (simulazione su copia).
- [x] Scorciatoie da tastiera (Esc / Invio / Spazio / Ctrl+Z / +-0).
- [x] Spostamento (Redeploy) interattivo per il Governo umano (6.4: trascinamento cubi,
      destinazioni validate e obbligo 6.4.2 verificato prima di concludere).
- [x] Refactor UI (1/n): estratta `ActionFlow` (pianificazione senza dipendenze dalla
      scena, 27 test) e `CLNames` (nomi italiani condivisi).
- [ ] Refactor UI (2/n): Att.Speciali, LogView, SidePanel, MapAnimator, Theme unico.
- [ ] Hotseat multi-giocatore locale.

### Fase 4 — Bot (Non-Giocatore)
- [x] Interfaccia generica `BotBrain` nel motore.
- [x] Bot ufficiali cap. 8 (Sindacato/Directorio/26 Luglio/Governo): scelta Operazione
      + Attività Speciale secondo i flowchart, validati da test.
- [ ] Aggancio alla scelta dell'Evento (richiede gli effetti delle carte, Fase 2).
- [ ] Rifinitura tie-breaker e tabella Spazi Casuali (8.2-8.3).
- [x] Integrazione dei bot nella UI: pulsanti "Gioca Bot (fazione sel.)" e "Tutti i Bot".
- [x] Loop di gioco completo: mazzo (48 Eventi + 4 Propaganda), pesca carte, risoluzione
      automatica con i bot, fine partita; pulsanti UI "Avanza carta" e "Auto: partita".
- [ ] Affinare l'ordine 1ª/2ª Disponibile e la scelta Evento/Operazione dei bot nel loop.

### Fase 5 — Rifinitura
- [ ] Scenari (Standard / Variabile / gioco breve), opzioni (Inganno, ecc.).
- [ ] Online/multiplayer (opzionale).
- [ ] Tutorial / esempio guidato interattivo.

## Note legali
Cuba Libre © 2013 GMT Games. Questo progetto è un'implementazione amatoriale a scopo
personale/educativo; gli asset grafici originali (carte, mappa) sono protetti da copyright
GMT Games e non vanno ridistribuiti pubblicamente senza autorizzazione.
