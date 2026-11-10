extends HBoxContainer
## Local ammunition receipts. Snapshot event IDs prevent repeated notifications.
const Battle: Script = preload("res://games/minigame/gp_artillery/battle.gd")
@export var hold_seconds: float = 2.0
var last_id: int = -1
var last_turn: int = -1
var pages: Array[Dictionary] = []
var animation: Tween

func update_state(snapshot: Dictionary, player_id: String) -> void:
	if last_turn > int(snapshot.turn):
		clear_cards()
	last_turn = snapshot.turn
	for event: Dictionary in snapshot.ammo_events:
		if int(event.id) <= last_id:
			continue
		if last_id >= 0 and event.player == player_id:
			var counts: Dictionary = {}
			for weapon: int in event.weapons:
				counts[weapon] = int(counts.get(weapon, 0)) + 1
			var page: Dictionary = {}
			for weapon: int in counts:
				page[weapon] = counts[weapon]
				if page.size() == 5:
					pages.append(page)
					page = {}
			if not page.is_empty():
				pages.append(page)
	if not snapshot.ammo_events.is_empty():
		last_id = int(snapshot.ammo_events.back().id)
	elif last_id < 0:
		last_id = 0
	if get_child_count() == 0 and not pages.is_empty():
		_show_page()

func clear_cards() -> void:
	if animation != null:
		animation.kill()
	pages.clear()
	_remove_cards()

func _remove_cards() -> void:
	for card: Node in get_children():
		remove_child(card)
		card.queue_free()

func _show_page() -> void:
	var page: Dictionary = pages.pop_front()
	for weapon: int in page:
		var card: PanelContainer = PanelContainer.new()
		card.custom_minimum_size = Vector2(148, 76)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var column: VBoxContainer = VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(column)
		var name_label: Label = Label.new()
		name_label.text = Battle.WEAPONS[weapon].name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 20)
		name_label.add_theme_color_override("font_color", Color(Battle.WEAPONS[weapon].color))
		column.add_child(name_label)
		var amount: Label = Label.new()
		amount.text = "+%d" % int(page[weapon])
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		amount.add_theme_font_size_override("font_size", 24)
		column.add_child(amount)
		add_child(card)
	modulate.a = 0.0
	scale = Vector2(0.9, 0.9)
	pivot_offset = size * 0.5
	animation = create_tween()
	animation.set_parallel(true)
	animation.tween_property(self, "modulate:a", 1.0, 0.22)
	animation.tween_property(self, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	animation.chain().tween_interval(hold_seconds)
	animation.chain().tween_property(self, "modulate:a", 0.0, 0.3)
	animation.chain().tween_callback(_page_finished)

func _page_finished() -> void:
	_remove_cards()
	if not pages.is_empty():
		_show_page()
