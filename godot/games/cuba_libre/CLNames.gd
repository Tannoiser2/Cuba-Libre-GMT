class_name CLNames
extends RefCounted

## Nomi italiani di Operazioni, Attività Speciali e pezzi: UNICA fonte di verità,
## condivisa da interfaccia, log e pianificazione (prima erano duplicati in
## Main.gd e GameController.gd, con il rischio che divergessero).

const OP := {
	"train": "Addestramento", "garrison": "Guarnigione", "sweep": "Perlustrazione",
	"assault": "Assalto", "rally": "Riorganizzazione", "march": "Marcia",
	"attack": "Attacco", "terror": "Terrorismo", "build": "Costruzione",
	"construct": "Costruzione",
}

const SA := {
	"transport": "Trasporto", "air_strike": "Attacco Aereo", "reprisal": "Rappresaglia",
	"infiltrate": "Infiltrazione", "ambush": "Imboscata", "ambush_m26": "Imboscata",
	"ambush_dr": "Imboscata", "kidnap": "Sequestro", "subvert": "Sovversione",
	"assassinate": "Assassinio", "profit": "Profitto", "muscle": "Muscle",
	"bribe": "Corruzione",
}

const PIECE := {
	"troops": "Truppa", "police": "Polizia", "guerrilla": "Guerriglia",
	"base": "Base", "casino": "Casinò",
}

## Etichette delle scelte di Riorganizzazione (Rally) per spazio.
const RALLY := {"place": "Guerriglie", "extra": "Guerriglie", "base": "Base", "flip": "Clandestine"}

## Sigle delle Fazioni (tasti dei Ruoli, pannello Vittoria).
const FACTION_SHORT := {"government": "Gov", "m26": "26J", "directorio": "DR", "syndicate": "SYN"}


static func op(id: String) -> String:
	return String(OP.get(id, id))


static func sa(id: String) -> String:
	return String(SA.get(id, id))


static func piece(id: String) -> String:
	return String(PIECE.get(id, id))


static func faction_short(id: String) -> String:
	return String(FACTION_SHORT.get(id, id))

