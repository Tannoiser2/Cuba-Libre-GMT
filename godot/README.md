# COIN Engine (Godot 4)

Motore generico per la **serie COIN** di GMT Games + modulo **Cuba Libre**.
Progetto Godot 4.3.

## Architettura

```
coin_engine/        MOTORE COIN GENERICO (riusabile per altri giochi COIN)
  CoinEnums.gd        enumerazioni comuni
  PieceTypeDef.gd     definizione tipo di pezzo (cube/guerriglia/base, stati)
  FactionDef.gd       definizione Fazione
  SpaceDef.gd         definizione spazio mappa
  GameDef.gd          definizione completa del gioco (immutabile)
  SpaceState.gd       stato mutabile di uno spazio (pezzi, supporto, controllo, marker)
  GameState.gd        stato mutabile della partita (+ Controllo, Supporto/Opposizione)
  RulesModule.gd      interfaccia che ogni gioco COIN implementa

games/
  cuba_libre/
    CubaLibreModule.gd   modulo concreto: dati, tipi di pezzo, setup, vittoria
    data/                spaces / factions / setup / cards (JSON)

tests/
  test_runner.gd      test headless (validano dati, setup, controllo, vittoria)

scenes/               interfaccia grafica
  CLTheme.gd          tema "dossier 1958": palette, caratteri, riquadri (unico file da
                      cambiare per vestire un altro gioco COIN)
  TopBar.gd           barra superiore: emblema, tessere Fazione, carte, comandi
  BottomStrip.gd      striscia inferiore: carta, Risorse, Vittoria, registro
  Main.gd             mappa, ordine di servizio, pannello azione a passi

assets/fonts/         Bebas Neue, Barlow Condensed (OFL), Special Elite (Apache 2.0)
tools/screenshot.gd   fotografia della scena per controllare l'interfaccia
```

Il principio è la separazione tra **motore generico** (meccaniche comuni a tutti i COIN:
spazi, fazioni, pezzi con stati, Controllo, Supporto/Opposizione, sequenza a carte,
round periodici, framework di vittoria) e **modulo di gioco** (dati e regole specifiche).
Per implementare un altro gioco COIN basta aggiungere `games/<gioco>/` con il suo
`RulesModule` e i dati.

## Eseguire i test (headless)

```bash
# prima importazione del progetto (genera la cache delle classi globali)
godot4 --headless --path godot --import

# esecuzione dei test
godot4 --headless --path godot -s res://tests/test_runner.gd
```

Esce con codice 0 se tutti i test passano.

## Aprire nell'editor

Aprire la cartella `godot/` come progetto in Godot 4.3+.

## Fotografare l'interfaccia

Serve un display (in CI o in un container: `xvfb-run`).

```bash
xvfb-run godot --path godot --rendering-method gl_compatibility --resolution 1500x820 \
  -s res://tools/screenshot.gd -- partita.png rally   # Rally del 26 Luglio in Sierra Maestra
xvfb-run godot --path godot --rendering-method gl_compatibility --resolution 1500x820 \
  -s res://tools/screenshot.gd -- menu.png menu       # menu iniziale
```
