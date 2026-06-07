# Calixto Bot — piano di implementazione

Sistema Non-Giocatore a carte (di Kevin Crooks) che **sostituisce il cap. 8** del
regolamento base. Materiali sorgente nel repo:
- `sources/rules/Calixto_Bot_Regole.pdf` (+ `Calixto_Bot_OCR.txt`)
- `sources/rules/Carte_Calixto.pdf` (+ `Calixto_Carte_OCR.txt`) — 24 carte (6 per fazione)
- `sources/rules/Tabelle_Calixto.pdf` (+ `Calixto_Tabelle_OCR.txt`) — Priorità, Disponibilità, Eventi, Propaganda

## Come funziona (dalle regole)
- Ogni fazione NP ha **6 carte Calixto** (mazzo unico mescolato a faccia in su).
- Ogni carta è un **flowchart**: una serie di domande; la prima vera seleziona
  l'**Operazione**; poi si sceglie **1 Attività Speciale** da una lista di priorità; STOP.
- Tabelle condivise: **Priorità Movimento**, **Priorità Pezzi**; per fazione: **Priorità
  Selezione Spazi**. Tabella **Disponibilità** (Evento vs Operazione). Tabelle **Eventi**.
- Regole d'oro: gli NP non rimuovono pezzi per pagare; **solo il Sindacato NP traccia le
  Risorse** (Governo/26L/DR le ignorano); si tira un **Activation Number** (AN) per limitare
  il numero di spazi; le istruzioni si eseguono "il più possibile", saltando l'illegale.

## Architettura prevista
- `coin_engine/`: estendere `BotBrain` con un'interfaccia per i "priority/condition" generici.
- `games/cuba_libre/rules/CalixtoBot.gd`: interprete delle carte + tabelle.
- `games/cuba_libre/data/calixto_cards.json`: le 24 carte come dati (condizioni → operazione,
  dettagli operazione, priorità attività speciali).
- `games/cuba_libre/data/calixto_tables.json`: Priorità Spazi/Movimento/Pezzi, Disponibilità, Eventi.
- Selezionabile in alternativa ai bot cap. 8 esistenti.

## Trascrizione carte GOVERNO (prima passata — DA CONFERMARE)
AN (Activation Number) = livello Alleanza USA per tutte.

- **GOV-U** — Q1 *Città non a Supporto Attivo?* → Addestramento · Q2 *Guerriglia Clandestina a
  Supporto?* → Perlustrazione (Sweep: usa Priorità Movimento; attiva Guerriglie anche senza
  muovere Truppe). Att. Speciale: 1) Attacco Aereo su spazio con Base/Casinò Vulnerabile (Remove)
  2) se Controllo COIN a Opposizione: Rappresaglia 3) Trasporto (Priorità Movimento) 4) Attacco Aereo (Remove).
- **GOV-Y** — Q1 *EC con Guerriglie?* → Guarnigione · Q2 *Guerriglia Clandestina a Supporto?* →
  Perlustrazione. Att. Speciale: 1) Attacco Aereo vulnerabile (Remove) 2) Rappresaglia 3) Trasporto 4) Attacco Aereo.
- **GOV-Z** — Q1 *Provincia 2-Pop senza Controllo GOV?* → (Operazione) · Q2 *Assalto in 1 spazio
  può rimuovere 3+ Guerriglie o 1 Base/Casinò?* → Assalto (rimuovi Basi e chiudi Casinò, Remove).
  Att. Speciale: 1) Attacco Aereo vulnerabile 2) Trasporto 3) Attacco Aereo 4) Rappresaglia.
- **GOV-X** — Q1 *Spazio con forze GOV e nemici vulnerabili?* → Assalto · Q2 *Guerriglia
  Clandestina a Supporto?* → Perlustrazione. Att. Speciale: come GOV-U/Y.
- **GOV-W** — Q1 *Spazio con forze GOV e nemici vulnerabili?* → Assalto · Q2 *Città non a Supporto
  Attivo?* → Addestramento (piazza cubi solo a gruppi di 4; Azione Civica con Shift verso Supporto
  Attivo per max 1d3 marker rimossi + shift; piazza Base in Provincia senza Base GOV). Att. Speciale: Trasporto.
- **GOV-V** — Q1 *3+ Truppe non necessarie al Controllo in una Città o Provincia con Base GOV?* →
  Trasporto · Q2 *Base GOV disponibile?* → Addestramento (cubi a gruppi di 4; piazza Base in
  Provincia senza Base GOV; Azione Civica…). Att. Speciale: Trasporto.

> NB: l'identificazione esatta dell'Operazione di ciascun ramo (dalle icone) e i dettagli vanno
> verificati con le sezioni C8.6/C8.7 del regolamento. Le carte di 26 Luglio, Directorio e
> Sindacato e le tabelle di Priorità/Disponibilità/Eventi seguono.

## Piano incrementale
1. Confermare la lettura delle carte Governo (sopra).
2. Trascrivere carte 26L/DR/Sindacato + tabelle Priorità/Disponibilità.
3. Implementare l'interprete (condizioni + azioni + priorità) e i predicati condivisi.
4. Tabelle Eventi e istruzioni Propaganda NP.
5. Selettore bot cap.8 / Calixto nella UI.
