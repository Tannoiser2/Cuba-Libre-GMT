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
- [ ] Riciclaggio (Launder) collegato alla sequenza di gioco.
- [x] Round di Propaganda (Vittoria, Risorse, Supporto, Sistemazione) + test.
- [x] Condizioni e margini di vittoria.
- [x] Test unitari del motore (147 test headless).
- [ ] Spostamento (Redeploy) del Governo automatizzato.

### Fase 2 — Carte ed Eventi
- [x] Ordine fazioni di tutte le 48 carte (dai simboli) + testo OCR in `cards.json`.
- [x] Caricamento carte nel `GameDef`.
- [x] Framework Eventi (`Events.gd`): gestori per carta + fallback "manuale".
- [x] Registrazione Capacità Insorgenti / Momentum del Governo.
- [~] Effetti automatizzati: 6 carte (Election, Batista Flees, Larrazábal, Carlos Prío,
      US Speaking Tour, Sinatra). Le restanti sono giocabili in modalità manuale.
- [ ] Rifinire `unshaded`/`shaded` per ogni carta (dal testo OCR) e automatizzare i restanti eventi.

### Fase 3 — Interfaccia utente
- [x] Mappa interattiva (schematica) con pezzi trascinabili e stato leggibile.
- [x] Pannelli Fazione, tracciati, log delle azioni.
- [x] Flusso guidato per le Operazioni (selezione spazi + drag-and-drop) + Round Propaganda.
- [ ] Flussi guidati per le Attività Speciali ed Eventi nella UI.
- [ ] Grafica della mappa reale (sprite) e rifinitura visiva.
- [ ] Hotseat multi-giocatore locale.

### Fase 4 — Bot (Non-Giocatore)
- [x] Interfaccia generica `BotBrain` nel motore.
- [x] Bot ufficiali cap. 8 (Sindacato/Directorio/26 Luglio/Governo): scelta Operazione
      + Attività Speciale secondo i flowchart, validati da test.
- [ ] Aggancio alla scelta dell'Evento (richiede gli effetti delle carte, Fase 2).
- [ ] Rifinitura tie-breaker e tabella Spazi Casuali (8.2-8.3).
- [ ] Integrazione dei bot nella UI (turni automatici) e gioco in solitario.

### Fase 5 — Rifinitura
- [ ] Scenari (Standard / Variabile / gioco breve), opzioni (Inganno, ecc.).
- [ ] Online/multiplayer (opzionale).
- [ ] Tutorial / esempio guidato interattivo.

## Note legali
Cuba Libre © 2013 GMT Games. Questo progetto è un'implementazione amatoriale a scopo
personale/educativo; gli asset grafici originali (carte, mappa) sono protetti da copyright
GMT Games e non vanno ridistribuiti pubblicamente senza autorizzazione.
