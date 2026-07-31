class_name TipLabel
extends Label

## Etichetta con tooltip OPACO e a CAPO (come TipButton): serve per l'anteprima
## dell'Operazione, il cui elenco di effetti è lungo più righe.

func _make_custom_tooltip(for_text: String) -> Object:
	return TipButton.build_tip(for_text)
