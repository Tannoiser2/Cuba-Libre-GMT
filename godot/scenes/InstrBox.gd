class_name InstrBox
extends PanelContainer

## Foglietto delle istruzioni sopra la mappa: altezza contenuta (righe limitate) ma
## testo completo sempre leggibile — al passaggio del mouse compare un tooltip opaco
## con l'intero messaggio.

func _make_custom_tooltip(for_text: String) -> Object:
	return TipButton.build_tip(for_text)
