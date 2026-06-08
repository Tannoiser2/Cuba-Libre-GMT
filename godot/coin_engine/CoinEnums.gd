class_name CoinEnums
extends RefCounted

## Enumerazioni condivise dal motore COIN generico.
## Concetti comuni a tutti i giochi della serie COIN (GMT).

## Tipo di spazio sulla mappa.
enum SpaceType {
	PROVINCE,   ## Provincia/area rurale (con Popolazione)
	CITY,       ## Città (con Popolazione)
	ECONOMIC,   ## Centro Economico / risorsa (con valore Econ, senza Popolazione)
	LOC,        ## Line of Communication (strade/ferrovie/fiumi) - altri giochi COIN
	COUNTRY,    ## Spazio "estero"/extra-mappa - altri giochi COIN
}

## Categoria generica di pezzo.
enum PieceCategory {
	CUBE,       ## Forza mobile schierata "in chiaro" (es. Truppe, Polizia)
	GUERRILLA,  ## Forza irregolare con stato nascosto/attivo
	BASE,       ## Base/struttura (include i Casinò del Sindacato)
	OTHER,
}

## Ruolo della Fazione nel conflitto.
enum FactionRole {
	COIN,       ## Contro-insurrezione (es. Governo)
	INSURGENT,  ## Insorgente
}

## Livelli di Supporto/Opposizione (meccanica standard COIN).
enum Support {
	ACTIVE_SUPPORT = 2,
	PASSIVE_SUPPORT = 1,
	NEUTRAL = 0,
	PASSIVE_OPPOSITION = -1,
	ACTIVE_OPPOSITION = -2,
}

## Stato di disponibilità nella sequenza di gioco a carte.
enum Eligibility {
	ELIGIBLE,
	INELIGIBLE,
}

## Tipo di azione scelta da una Fazione con una carta.
enum ActionType {
	PASS,
	OPERATION,
	OPERATION_WITH_SPECIAL,
	LIMITED_OPERATION,
	EVENT,
}


## Restituisce il valore di Popolazione "pesato" per un livello di supporto.
## Usato per Totale Supporto / Totale Opposizione.
static func support_weight(level: int) -> int:
	return level  # i valori dell'enum sono già i pesi (+2/+1/0/-1/-2)
