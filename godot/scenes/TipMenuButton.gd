class_name TipMenuButton
extends MenuButton

## MenuButton con tooltip opaco e a capo (vedi TipButton).

func _make_custom_tooltip(for_text: String) -> Object:
	return TipButton.build_tip(for_text)
