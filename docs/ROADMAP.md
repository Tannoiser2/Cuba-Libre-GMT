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
- [ ] Attività Speciali (tutte le 12).
- [ ] Sistema Denaro (Cash) e Riciclaggio.
- [ ] Round di Propaganda (Vittoria, Risorse, Supporto, Spostamento, Sistemazione).
- [ ] Condizioni e margini di vittoria.
- [ ] Test unitari del motore (incl. l'esempio guidato del Playbook come scenario di test).

### Fase 2 — Carte ed Eventi
- [ ] Trascrivere testo e ordine fazioni delle 48 carte (da `images/Card_*.png`).
- [ ] Implementare gli effetti degli eventi (motore a regole/handler per carta).
- [ ] Capacità Insorgenti e Momentum Governo.

### Fase 3 — Interfaccia utente
- [ ] Mappa interattiva con pezzi trascinabili e stato leggibile.
- [ ] Pannelli Fazione, tracciati, mazzo/carta corrente, log delle azioni.
- [ ] Flussi guidati per Operazioni/Attività Speciali/Eventi.
- [ ] Hotseat multi-giocatore locale.

### Fase 4 — Bot (Non-Giocatore)
- [ ] Formalizzare i flowchart Bot per fazione (cap. 8 + schede `Chart_*.jpg`).
- [ ] Implementare l'IA deterministica e l'opzione gioco in solitario.

### Fase 5 — Rifinitura
- [ ] Scenari (Standard / Variabile / gioco breve), opzioni (Inganno, ecc.).
- [ ] Online/multiplayer (opzionale).
- [ ] Tutorial / esempio guidato interattivo.

## Note legali
Cuba Libre © 2013 GMT Games. Questo progetto è un'implementazione amatoriale a scopo
personale/educativo; gli asset grafici originali (carte, mappa) sono protetti da copyright
GMT Games e non vanno ridistribuiti pubblicamente senza autorizzazione.
