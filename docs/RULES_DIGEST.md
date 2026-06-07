# Cuba Libre — Sintesi del Regolamento (per l'implementazione digitale)

Sintesi operativa delle regole di **Cuba Libre** (Serie COIN Vol. II, GMT 2013),
estratta dal regolamento italiano (`sources/rules/Cuba_Libre_Regolamento_ITA.pdf`)
e dal Playbook 2018 (`sources/rules/Cuba_Libre_Playbook_2018_ENG.pdf`).
Questo documento è la specifica di riferimento per il motore di gioco.

## 1. Panoramica

- 1–4 giocatori, conflitto COIN a Cuba 1957–58.
- 4 Fazioni: **Governo** (blu, COIN), **26 Luglio / M26** (rosso, insorgente),
  **Directorio / DR** (giallo, insorgente), **Sindacato** (verde, insorgente).
- Tutte le Fazioni sono nemiche tra loro.
- Mazzo di 52 carte: 48 Eventi + 4 Propaganda. Le carte si giocano dalla cima del
  mazzo, una alla volta. Nessuna mano in mano ai giocatori.
- Le Fazioni non controllate da un giocatore sono **Non-Giocatore (Bot)**, governate
  dal cap. 8 (regole/flowchart deterministici).

## 2. La Mappa (vedi `data/spaces.json`)

- **Province**: terreno Foresta / Prateria (Grassland) / Montagna; Pop 1–2.
- **Città**: Pop 1 o 6 (Havana = 6).
- **Centri Economici (EC)**: valore Econ 2–3, senza Popolazione, non possono
  contenere Basi. Econ totale = 8.
- Spazi: Pinar del Río, La Habana, Havana (Città), Matanzas, Las Villas,
  Camagüey (Prov.), Camagüey (Città), Oriente, Sierra Maestra, Santiago de Cuba (Città)
  + 3 EC. **Le adiacenze in `spaces.json` vanno verificate sulla mappa fisica.**

## 3. Forze (vedi `data/factions.json`)

| Fazione | Truppe | Polizia | Guerriglie | Basi |
|---|---|---|---|---|
| Governo | 15 | 15 | – | 2 |
| 26 Luglio | – | – | 15 | 4 |
| Directorio | – | – | 15 | 4 |
| Sindacato | – | – | 6 | 10 (Casinò) |

- **Guerriglie**: Clandestine (nascoste) o Attive. Si piazzano Clandestine.
- **Casinò** (Basi del Sindacato): Aperti o Chiusi. Si piazzano/ripristinano Aperti.
  Azioni che rimuoverebbero/sposterebbero una Base normale invece **chiudono** un
  Casinò aperto (no effetto se già chiuso). Solo il Sindacato può rimuovere/chiudere
  volontariamente i propri Casinò.
- **Raggruppamento (stacking)**: max 2 Basi non-Casinò + 2 Casinò per spazio.
  Basi/Casinò non possono stare negli EC.

## 4. Supporto / Opposizione / Controllo

- 5 livelli per Città/Province: Supporto Attivo, Supporto Passivo, Neutrale,
  Opposizione Passiva, Opposizione Attiva. Gli EC non hanno mai Supporto/Opposizione.
- Attivo conta doppio.
  - Totale Supporto = 2·Pop(SuppAttivo) + 1·Pop(SuppPassivo)
  - Totale Opposizione = 2·Pop(OppAttiva) + 1·Pop(OppPassiva)
- **Controllo**: una Fazione controlla uno spazio se i suoi pezzi superano la somma
  di tutti gli altri. Casinò contano solo se Aperti.

## 5. Risorse e Aiuti

- Ogni Fazione ha 0–49 Risorse. Il Governo somma anche gli **Aiuti** (0–49) durante
  Propaganda ed Eventi.
- Trasferimenti negoziati (palesi): solo Risorse o Denaro, solo da/a una Fazione che
  sta svolgendo Op/Attività Speciale/Evento.

## 6. Sequenza di Gioco — Carta Evento (cap. 2)

1. Si rivela la carta corrente; l'ordine delle Fazioni è dato dai simboli in cima.
2. Le Fazioni **Disponibili** (Eligible) agiscono da sinistra a destra. Le Non
   Disponibili non fanno nulla.
3. **Passare**: +1 Risorsa (+3 per il Governo), resta Disponibile.
4. Opzioni della **1ª Fazione Disponibile**: Operazione (± Attività Speciale) **oppure** Evento.
5. Opzioni della **2ª Fazione Disponibile** (dipendono dalla 1ª):
   - 1ª ha fatto **solo Op** → 2ª può fare **Operazione Limitata** (1 spazio, no Att. Speciale).
   - 1ª ha fatto **Op + Att. Speciale** → 2ª può fare **l'Evento**.
   - 1ª ha fatto **l'Evento** → 2ª può fare **Operazione (± Att. Speciale)**.
6. **Riciclaggio (Launder)**: chi paga Risorse per un'Op senza Att. Speciale può
   rimuovere 1 segnalino Denaro per una LimOp gratuita extra (eccetto Costruire).
7. **Modifica Disponibilità**: chi ha agito (Op/Evento) → Non Disponibile; gli altri → Disponibile.
8. **Carta seguente**: si sposta la carta del mazzo di pesca sopra le carte giocate
   e si rivela la successiva (i giocatori vedono la prossima carta).
9. **Carta Evento Finale** (prima della Propaganda finale): solo Operazioni Limitate.

## 7. Operazioni (cap. 3)

### Governo (COIN) — costo per spazio 2/3/4 secondo Alleanza USA (Garrison: totale)
- **Train (Addestramento)**: piazza fino a 4 cubi in Città scelte o Province con Base
  Govt; poi in 1 spazio: sostituisci 2 cubi con 1 Base **oppure** Azione Civica (Supporto).
- **Garrison (Guarnigione)**: muovi cubi verso EC/Città; in ogni EC attiva 1 Guerriglia
  per cubo; opzionale Assalto gratis in 1 EC.
- **Sweep (Perlustrazione)**: muovi Truppe adiacenti negli spazi scelti; attiva 1
  Guerriglia per cubo (in Foresta 1 ogni 2 cubi).
- **Assault (Assalto)** (3 Risorse/spazio): rimuovi 1 Guerriglia Attiva per Truppa; poi
  Basi. In Città/EC +1 pezzo ogni 2 Truppe; in Montagna solo 1 ogni 2 Truppe.

### Insorgenti (M26/DR/Sindacato)
- **Rally (Riorganizzazione)** (1 Ris/spazio): piazza 1 Guerriglia, o rimpiazza 2
  Guerriglie con 1 Base, o (se Basi presenti) gira le Guerriglie Clandestine / piazza
  Guerriglie extra (M26: 2·Basi + 2·Pop; DR: Basi + Pop). Vincoli di Supporto per spazio.
- **March (Marcia)** (1 Ris/Città-Provincia, 0 per EC): muovi Guerriglie in spazi
  adiacenti; si Attivano entrando in spazio con Supporto/EC se (Guerriglie + cubi dest) > 3.
- **Attack (Attacco)** — solo M26/DR (1 Ris/spazio): attiva tutte le proprie Guerriglie,
  tira 1d6 ≤ n° Guerriglie → rimuovi fino a 2 pezzi nemici. Su "1" piazza 1 Guerriglia.
- **Terror (Terrorismo)** (1 Ris/Città-Prov, 0/EC): attiva 1 Guerriglia Clandestina;
  in Città/Prov metti Terrore e sposta Supp/Opp di 1 verso Neutrale (M26: verso Opp Attiva);
  in EC metti Sabotaggio.
- **Build (Costruzione)** — solo Sindacato (5 Ris/spazio, mai gratis): in Città/Prov
  controllata da Govt o Sindacato, piazza un Casinò chiuso o apri un Casinò chiuso.

## 8. Attività Speciali (cap. 4)

- **Governo**: Transport (muovi ≤3 Truppe), Air Strike (rimuovi 1 Guerriglia Attiva/Base;
  no in Embargo; con Garrison/Sweep/Assault), Reprisal (Terrore + Opp→Neutrale + sposta 1 Guerriglia).
- **26 Luglio**: Infiltrate (rimpiazza 1 cubo con Guerriglia M26; con Rally/March),
  Ambush (Attacco automatico in 1 spazio), Kidnap/Sequestro (sottrai Risorse/Denaro).
- **Directorio**: Subvert/Sovversione (Pop→Risorse + Provincia a Neutrale),
  Ambush, Assassinate (rimuovi/chiudi 1 pezzo nemico, anche Base protetta).
- **Sindacato**: Profit (accumula Denaro o converte Denaro/Casinò in Risorse),
  Muscle/Forzare (muovi Polizia/Truppe a difesa Casinò/EC), Bribe/Corrompere
  (−3 Ris: rimuovi/gira pezzi). Bribe è l'unica Att. Speciale con costo in Risorse.

### Denaro (Cash, max 4 token)
- Stanno sotto una Guerriglia/cubo e si muovono con essa; appartengono alla Fazione di quel pezzo.
- Rimossi: se il pezzo viene rimosso (trasferisci se possibile), per Riciclaggio, o
  in Fase Risorse (ogni token → 1 Base/Casinò aperto **o** +6 Risorse).

## 9. Eventi (cap. 5)

- Testo non-ombreggiato e ombreggiato (**Uso Duplice**): si sceglie uno dei due.
- **Capacità degli Insorgenti**: effetti permanenti per tutta la partita.
- **Momentum del Governo**: effetto fino alla Fase di Sistemazione della Propaganda successiva.
- Il testo dell'Evento ha priorità sulle regole (con le eccezioni: disponibilità pezzi,
  raggruppamento, limite 49, no operazioni di altre Fazioni salvo specifica).

## 10. Round di Propaganda (cap. 6)

1. **Vittoria**: se una Fazione soddisfa le condizioni, fine partita (cap. 7).
2. **Risorse**: entrate Governo (Econ EC non Sabotati + Aiuti, dopo aver Sabotato EC dove
   Guerriglie M26+DR > cubi), entrate Insorgenti (M26 = n° Basi; DR = n° spazi con pezzi;
   Sindacato = Pop Città + Econ EC dove Guerr.Sind > Polizia + 2·Casinò aperti),
   **Fare la Cresta** (Skim: 2 Ris dal Sindacato al controllante per ogni spazio con Casinò),
   **Depositi di Denaro**.
3. **Supporto**: Alleanza USA (se Tot.Supporto ≤18 scende di 1 e Aiuti −10); Azione Civica
   (Govt), Dimostrazioni (M26), Supporto Espatriati (DR — Rally gratis).
4. **Spostamento (Redeploy)**: il Governo riposiziona Polizia/Truppe.
5. **Sistemazione (Reset)**: tutte Disponibili; rimuovi Terrore/Sabotaggio; scarta Momentum;
   Guerriglie → Clandestine, Casinò → Aperti; gioca carta seguente.

- Mai due Propaganda di fila. La **4ª Propaganda** è finale: si salta a Fase Supporto e si
  determina il vincitore (7.3).

## 11. Vittoria (cap. 7)

Condizioni (controllate all'inizio di ogni Propaganda):
- **Governo**: tutte le Città a Supporto Attivo **e** Totale Supporto > 18.
- **26 Luglio**: Totale Opposizione + Basi M26 > 15.
- **Directorio**: Pop controllata da DR + Basi DR > 9.
- **Sindacato**: Casinò aperti > 7 **e** Risorse > 30.

Margine di vittoria (a fine partita, il maggiore vince; parità → Bot, Sindacato, DR, M26):
- Govt: TotSupp − 18 · M26: TotOpp+Basi − 15 · DR: PopDR+Basi − 9 · Sind: min(Casinò−7, Ris−30).

## 12. Bot / Non-Giocatore (cap. 8)

Le Fazioni Bot seguono priorità deterministiche (flowchart per Fazione). In sintesi:
preferiscono l'Evento (se efficace), altrimenti Operazione + Attività Speciale; non fanno
LimOp né Riciclaggio; Passano solo se non possono pagare alcuna Op. Le priorità di scelta
di spazi/bersagli sono dettagliate alle pp. 19–27 del regolamento e nelle schede Bot
(immagini `Chart_*.jpg` nel modulo VASSAL). **Da formalizzare in fase dedicata.**

## Setup Standard

Vedi `data/setup_standard.json`. Schieramento Variabile (riassunto):
- Sindacato: 3 Casinò ovunque.
- Directorio: 3 Guerriglie ovunque.
- 26 Luglio: 4 Guerriglie + 1 Base in spazi senza DR (max 1 Guerriglia/Città).
- Governo: 9 Truppe + 8 Polizia tra le Città, + 3 Truppe in 1 Provincia.
- Poi si marca il Controllo. Marker e forze Bot come nello Standard (eccetto Controllo).
