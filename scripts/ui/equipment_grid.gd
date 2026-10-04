class_name EquipmentGrid
extends ExpeditionLootGrid
## The same item rectangles as expedition loot; placement remains an inventory command.
var loadout_owner: LoadoutPanel

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var id := int(occupied.get(ExpeditionBaseline.cell_key(_cell(event.position)), -1))
		if id < 0:
			loadout_owner._on_container_clicked(container)
			accept_event()
			return
	super._gui_input(event)

func _get_drag_data(at: Vector2) -> Variant:
	var id := int(occupied.get(ExpeditionBaseline.cell_key(_cell(at)), -1))
	if id < 0:
		return null
	item_selected.emit(id)
	var instance := loadout_owner.inventory.find_instance(id)
	var preview := ExpeditionUI.label(ItemDefs.get_item(str(instance["def_id"]))["name"], 20)
	set_drag_preview(preview)
	return {"instance_id":id,"def_id":instance["def_id"],"rotated":instance.get("rotated",false),"loadout_owner":loadout_owner.get_instance_id()}

func _valid_payload(data: Variant) -> bool:
	return data is Dictionary and int(data.get("loadout_owner",-1)) == loadout_owner.get_instance_id() and not loadout_owner.pending_placement

func _drop_data(at: Vector2, data: Variant) -> void:
	loadout_owner.place_item(data,container,_cell(at))
