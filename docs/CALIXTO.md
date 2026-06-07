# Calixto Bot — piano di implementazione

Sistema Non-Giocatore a carte (di Kevin Crooks) che **sostituisce il cap. 8** del
regolamento base. Materiali sorgente nel repo:
- `sources/rules/Calixto_Bot_Regole.pdf` (+ `Calixto_Bot_OCR.txt`)
- `sources/rules/Carte_Calixto.pdf` (+ `Calixto_Carte_OCR.txt`) — 24 carte (6 per fazione)
- `sources/rules/Tabelle_Calixto.pdf` (+ `Calixto_Tabelle_OCR.txt`) — Priorità, Disponibilità, Eventi, Propaganda

## Come funziona (dalle regole)
- Ogni fazione NP ha **6 carte Calixto** fronte/retro (mazzo unico mescolato a faccia in su).
  Nel PDF carte: pagine **dispari = fronti**, **pari = retri** delle stesse carte.
- **Lettura di una carta** (regola "Reading Calixto Cards"): si parte dal **primo box blu** in
  alto. Condizione **vera → freccia verde (✓)**, **falsa → freccia rossa (✗)**. Una freccia può
  puntare a:
  - icona **"pesca nuova carta"** → abbandona la carta e pescane un'altra della fazione attiva;
  - icona **"gira la carta"** → passa al retro e continua a leggere;
  - il **box successivo** (scendi), oppure direttamente al blocco **Operazione**.
- Le condizioni in alto sono **filtri**: se la carta non è adatta, si pesca/gira per trovare
  l'azione giusta. In fondo: blocco **Operazione** (istruzioni numerate) + **lista Attività Speciali** → STOP.
- **Operazione**: esegui le istruzioni ①②… in ordine, il più possibile. **Grassetto** = colonna
  della tabella Priorità Selezione Spazi da usare. ★ = eseguita subito, niente tiro AN. Freccia
  → = promemoria. Un'istruzione dopo una condizione rossa si esegue solo se la condizione è vera.
  Se non ci sono spazi legali per l'Operazione, **pesca una nuova carta**.
- **Attività Speciale**: esegui la **prima fattibile** in ordine di lettera (Ⓐ, Ⓑ, …). Salta
  quelle non eseguibili o con condizione rossa falsa. Mai eseguirla in una **Operazione Limitata**.
- **Activation Number (AN)**: in alto a destra (dado). Per il **Governo = livello Alleanza USA**.
  Dopo ogni spazio: tira 1d6; ≤ AN → stop (più eventuali ★); > AN → seleziona un altro spazio.
  Eccezioni (niente tiro): Guarnigione GOV, March insorti su EC, Terror insorti su EC.
- Regole d'oro: gli NP non rimuovono pezzi per pagare; **solo il Sindacato NP traccia le
  Risorse** (Governo/26L/DR le ignorano); le istruzioni si eseguono "il più possibile", saltando
  l'illegale. Se tutte le carte di una fazione vengono pescate senza un'Operazione legale, si
  passa alla riga successiva della tabella Idoneità (o Pass se in fondo).

## Architettura prevista
- `coin_engine/`: estendere `BotBrain` con un'interfaccia per i "priority/condition" generici.
### Motore generico riusabile (Calixto è usato da molti giochi COIN)
Calixto va costruito come **componente generico in `coin_engine/`**, indipendente dal gioco, così
da poter essere riusato da altri titoli COIN fornendo solo i propri dati e implementazioni.

- `coin_engine/calixto/CalixtoEngine.gd` (game-agnostic): legge la struttura carta
  (`flow`/`ops`/`special`), valuta le condizioni tramite un **registro di predicati pluggable**,
  esegue Operazioni/Attività Speciali tramite un **registro di azioni pluggable**, gestisce il
  tiro **AN**, pesca/gira, e il fallback sulla tabella **Idoneità**.
- `coin_engine/calixto/CalixtoDeck.gd`: mazzo (pesca con rotazione fino alla fazione attiva,
  rimescolo solo a inizio partita e nel Reset di Propaganda).
- Interfacce che il gioco implementa: `CalixtoPredicates` (condizioni come
  `city_not_active_support`, `enemy_space_4plus_or_underground`, …) e `CalixtoActions`
  (operazioni `sweep/train/rally/march/attack/terror/assault/garrison/construct` e attività
  speciali) + le tabelle Priorità.

Strato specifico Cuba Libre:
- `games/cuba_libre/rules/CLCalixto.gd`: implementa predicati/azioni mappandoli sulle operazioni
  CL esistenti, e carica le tabelle Priorità.
- `games/cuba_libre/data/calixto_cards.json`: le 24 carte (fronte/retro) come dati. ✔ FATTO
- `games/cuba_libre/data/calixto_tables.json`: Priorità Spazi/Movimento/Pezzi, Disponibilità, Eventi.
- Selezionabile in alternativa ai bot cap. 8 esistenti.

### Stato trascrizione carte
✔ Governo (U,Y,Z,X,W,V) · ✔ 26 Luglio (G,H,J,K,L,M) · ✔ Directorio (A,B,C,D,E,F) ·
✔ Sindacato (N,P,Q,R,S,T) — tutte fronte/retro con valori AN. Resta: tabelle + interprete.

### Modello dati carta (esempio GOV-U / GOV-UU)
```json
"U": {
  "an": "us_alliance",
  "front": {
    "flow": [
      {"cond": "city_not_active_support",        "true": "next", "false": "draw"},
      {"cond": "underground_guerrilla_at_support","true": "op",  "false": "flip"}
    ],
    "op": {"type": "sweep",
           "instructions": [{"n":1, "priorities":"move"},
                            {"note":"Sweep per attivare Guerriglie anche senza muovere Truppe"}],
           "special": ["air_strike_vuln_remove",
                       {"cond":"coin_control_at_opposition","do":"reprisal"},
                       "transport_move", "air_strike_remove"]}
  },
  "back": {  // GOV-UU: incondizionata
    "op": {"type": "train",
           "instructions": [{"n":1, "do":"place_cubes_sets_of_4"}],
           "special": ["transport_move"],
           "post": [{"star":true, "do":"civic_action_shift_active_support", "max":"1d3"},
                    {"do":"place_base_province_without_gov_base"}]}
  }
}
```
Target dei rami: `next` (scendi), `draw` (pesca), `flip` (retro), `op` (esegui Operazione).

## Trascrizione carte GOVERNO (AN = Alleanza USA)
- **GOV-U** (fronte, Operazione **Perlustrazione**): D1 *Città non a Supporto Attivo?* ✓→scendi /
  ✗→**pesca**. D2 *Guerriglia Clandestina in spazio a Supporto?* ✓→Operazione / ✗→**gira**.
  Op Perlustrazione: ① Priorità Movimento; → attiva Guerriglie anche senza muovere Truppe.
  Att. Speciale: Ⓐ Attacco Aereo su Base/Casinò Vulnerabile (Remove); Ⓑ se Controllo COIN a
  Opposizione: Rappresaglia; Ⓒ Trasporto (Priorità Movimento); Ⓓ Attacco Aereo (Remove).
  **GOV-UU** (retro, incondizionata): **Addestramento** ① piazza cubi solo a gruppi di 4.
  Att. Speciale: Ⓐ Trasporto (Priorità Movimento). Poi Addestramento: ★ Azione Civica con
  *Shift verso Supporto Attivo* (max 1d3 marker rimossi + shift); → piazza Base in Provincia
  senza Base GOV; → se non Limitata, Azione Civica/Base può colpire spazio non scelto per Addestramento.
- **GOV-Y / GOV-Z / GOV-X / GOV-W / GOV-V**: in trascrizione (fronti pag.1, retri pag.2).

> Carte di 26 Luglio (pag.3-4), Directorio (pag.5-6), Sindacato (pag.7-8) e tabelle di
> Priorità/Disponibilità/Eventi seguono.


## Piano incrementale
1. Confermare la lettura delle carte Governo (sopra).
2. Trascrivere carte 26L/DR/Sindacato + tabelle Priorità/Disponibilità.
3. Implementare l'interprete (condizioni + azioni + priorità) e i predicati condivisi.
4. Tabelle Eventi e istruzioni Propaganda NP.
5. Selettore bot cap.8 / Calixto nella UI.
