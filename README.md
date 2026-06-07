# Cuba Libre — Digital Edition

Edizione digitale (non ufficiale, amatoriale) di **Cuba Libre**, il volume II della
Serie COIN di GMT Games — l'insorgenza di Castro a Cuba, 1957–1958.

## Stato del progetto

🚧 **Fase 1 — Motore di gioco.** Materiali sorgente caricati, regolamento sintetizzato,
modello dati estratto e **motore COIN generico** avviato in Godot 4 (caricamento dati,
schieramento, Controllo, Supporto/Opposizione, metriche di vittoria — validati da test).
Vedi [`docs/ROADMAP.md`](docs/ROADMAP.md) per il piano completo.

L'architettura separa un **motore COIN generico** (riusabile per altri giochi della serie)
dal **modulo Cuba Libre**, così che lo stesso engine possa ospitare altri titoli COIN.

## Struttura del repository

```
sources/        Materiali sorgente (regolamento, playbook, modulo VASSAL)
  rules/        PDF del regolamento (ITA) e del Playbook (ENG)
  vassal/       Modulo VASSAL 1.3.2 (immagini + definizioni)
godot/          Progetto Godot 4 (vedi godot/README.md)
  coin_engine/  Motore COIN generico (riusabile)
  games/cuba_libre/  Modulo Cuba Libre (dati + regole)
  tests/        Test headless
docs/           Documentazione
  RULES_DIGEST.md   sintesi operativa del regolamento
  ROADMAP.md        piano di sviluppo
```

## Giocare nel browser (iPad/PC, senza installare nulla)

Il progetto include una GitHub Action che compila l'export Web e lo pubblica su
**GitHub Pages**. Per attivarlo una volta sola:
1. Vai su **Settings → Pages**.
2. In **Source** seleziona **GitHub Actions**.

Al push successivo, l'Action compila ed espone il gioco a un URL pubblico (visibile
nell'output del workflow), apribile anche da **Safari su iPad**.

In locale: aprire la cartella `godot/` con **Godot 4.3** (gratuito) ed eseguire (F5),
oppure i test con `godot4 --headless --path godot -s res://tests/test_runner.gd`.

## Riferimenti

- Regolamento: `sources/rules/Cuba_Libre_Regolamento_ITA.pdf`
- Playbook: `sources/rules/Cuba_Libre_Playbook_2018_ENG.pdf`
- Sintesi regole: [`docs/RULES_DIGEST.md`](docs/RULES_DIGEST.md)

## Note legali

Cuba Libre © 2013 GMT Games. Progetto amatoriale a scopo personale/educativo. Gli asset
grafici e i testi originali sono proprietà di GMT Games e dei rispettivi autori
(Volko Ruhnke, Jeff Grossman) e non devono essere ridistribuiti senza autorizzazione.
