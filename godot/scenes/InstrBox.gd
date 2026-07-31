class_name InstrBox
extends Control

## Contenitore della riga istruzioni: altezza FISSA (la mappa non "balla") ma testo
## completo sempre leggibile — al passaggio del mouse compare un tooltip opaco con
## l'intero messaggio (utile quando il clip taglia le istruzioni lunghe).

func _make_custom_tooltip(for_text: String) -> Object:
	return TipButton.build_tip(for_text)
