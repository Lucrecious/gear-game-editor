extends Node2D

class_name GameEditor

signal selected_changed

onready var _terminal := $HUD/Terminal
onready var _regions := $Space/Regions as EditorRegions
onready var _view := $Space/View as EditorView
onready var _grid := $Space/Grid as EditorGrid

var fsm := FSM.new()

var _event_current

var _selected := []

func _ready() -> void:
	_grid.set_view(_view.get_rect2())
	
	fsm.add_transition(_state_idle, _state_move_selected, _to_move_selected)
	fsm.add_transition(_state_move_selected, _state_idle, _from_move_selected)
	
	fsm.add_transition(_state_idle, _state_scale_selected, _to_scale_selected)
	fsm.add_transition(_state_scale_selected, _state_idle, _from_scale_selected)
	
	fsm.add_transition(_state_idle, _state_move_view, _to_move_view)
	fsm.add_transition(_state_move_view, _state_idle, _from_move_view)
	
	fsm.state(_state_idle)

func get_selected() -> Array:
	return _selected.duplicate()

func _unhandled_input(event):
	_event_current = event
	fsm.update(get_physics_process_delta_time())

func _select(add : bool) -> void:
	if not add:
		_selected.clear()
	
	var mpos := _grid.to_coords(get_global_mouse_position())
	var region = _regions.get_at(mpos)
	
	if region:
		if add and region in _selected:
			_selected.erase(region)
		else:
			_selected.append(region)
	
	emit_signal("selected_changed")

func _on_Terminal_command_entered(command : Dictionary) -> void:
	var cmd = command['cmd']
	if cmd == null: return
	
	match cmd:
		EditorCommands.Unknown:
			_terminal.output.put(['[Unknown Command]'])
		EditorCommands.Create:
			var object = command['params'][0]
			var location = command['params'][1]
			match object:
				EditorCommands.RegionParam:
					var pos = _get_create_position(location)
					_regions.create(pos, Vector2(1, 1))
					_terminal.output.put(['Region created'])

func _get_create_position(location : String) -> Vector2:
	if location == EditorCommands.CursorParam:
		return _grid.to_coords(get_global_mouse_position())
		
	var default := _view.to_world(Vector2(.756, .51))
	return _grid.to_coords(default)

var _state_idle := FSMQuickState.new(fsm)\
	.add_main(self, "_state_idle_main")
func _state_idle_main() -> void:
	if Input.is_action_just_pressed("editor_zoom_in"):
		_view.magnify(1.3)
	elif Input.is_action_just_pressed("editor_zoom_out"):
		_view.shrink(1.3)
	elif Input.is_action_just_pressed("editor_select"):
		var add := Input.is_action_pressed("editor_modifier")
		_select(add)

var _state_move_view := FSMQuickState.new(fsm)\
	.add_main(self, "_state_move_view_main")
func _state_move_view_main() -> void:
	if _event_current is InputEventMouseMotion:
		var rel = (_event_current as InputEventMouseMotion).relative
		_view.global_position -= Vector2(rel.x, rel.y) * _view.get_zoom()
	
	_grid.set_view(_view.get_rect2())

var _state_move_selected := FSMQuickState.new(fsm)\
	.add_data({'alt_coords' : Vector2()})\
	.add_enter(self, "_state_move_selected_enter")\
	.add_main(self, "_state_move_selected_main")
func _state_move_selected_enter(from : FSMState) -> void:
	_state_move_selected.data['alt_coords'] = _grid.to_coords(get_global_mouse_position())
func _state_move_selected_main() -> void:
	if not _event_current is InputEventMouseMotion: return
	var event := _event_current as InputEventMouseMotion
	
	var _last_alt_coords := _state_move_selected.data['alt_coords'] as Vector2
	var _now_alt_coords := _grid.to_coords(get_global_mouse_position())
	
	var delta := _now_alt_coords - _last_alt_coords
	
	_state_move_selected.data['alt_coords'] = _now_alt_coords
	
	_move_selected(delta)

func _move_selected(delta : Vector2) -> void:
	assert(not _selected.empty())
	
	for select in _selected:
		select.move(delta)

var _state_scale_selected := FSMQuickState.new(fsm)\
	.add_data({'alt_pos': Vector2(), 'scale': Vector2()})\
	.add_enter(self, '_state_scale_selected_enter')\
	.add_main(self, '_state_scale_selected_main')
func _state_scale_selected_enter(from_state : FSMState) -> void:
	_state_scale_selected.data['alt_pos'] = get_global_mouse_position()
	_state_scale_selected.data['scale'] = _selected.front().rect().size
func _state_scale_selected_main() -> void:
	if not _event_current is InputEventMouseMotion: return
	var event := _event_current as InputEventMouseMotion
	
	var _last_alt_coords := _state_scale_selected.data['alt_pos'] as Vector2
	var _now_alt_coords := get_global_mouse_position()
	
	var delta := _now_alt_coords - _last_alt_coords
	
	_scale_selected(delta)

func _scale_selected(delta : Vector2):
	var region := _selected.front() as EditorRegion
	var scale = _state_scale_selected.data['scale']
	var delta_grid = _grid.to_coords(delta)
	
	region.set_scale(scale + delta_grid)

var _to_scale_selected := FSMQuickTransition.new(fsm)\
	.set_evaluation(self, "_to_scale_selected_evaluation")
func _to_scale_selected_evaluation() -> bool:
	if not Input.is_action_just_pressed("editor_alt"): return false
	if _selected.empty(): return false
	
	var select = _selected.front()
	if select is EditorRegion:
		return _is_scaling_region(select as EditorRegion)
	
	return false

var _from_scale_selected := FSMQuickTransition.new(fsm)\
	.set_evaluation(self, "_from_scale_selected_evaluation")
func _from_scale_selected_evaluation() -> bool:
	return Input.is_action_just_released("editor_alt")

var _to_move_view := FSMQuickTransition.new(fsm)\
	.set_evaluation(self, "_to_move_view_evaluation")
func _to_move_view_evaluation() -> bool:
	return Input.is_action_just_pressed("editor_alt")

var _from_move_view := FSMQuickTransition.new(fsm)\
	.set_evaluation(self, "_from_move_view_evaluation")
func _from_move_view_evaluation() -> bool:
	return Input.is_action_just_released("editor_alt")

var _to_move_selected := FSMQuickTransition.new(fsm)\
	.set_evaluation(self, "_to_move_selected_evaluation")
func _to_move_selected_evaluation() -> bool:
	if not Input.is_action_just_pressed("editor_alt"): return false
	if _selected.empty(): return false
	
	var select = _selected.front()
	if select is EditorRegion:
		return _is_moving_region(select as EditorRegion)
	
	return false

var _from_move_selected := FSMQuickTransition.new(fsm)\
	.set_evaluation(self, "_from_move_selected_evaluation")
func _from_move_selected_evaluation() -> bool:
	return Input.is_action_just_released("editor_alt")

func _is_moving_region(region : EditorRegion) -> bool:
	return _cursor_within(region.movement_hint_position(), region.movement_hint_size())

func _is_scaling_region(region : EditorRegion) -> bool:
	return _cursor_within(region.scale_hint_position(), region.scale_hint_size())

func _cursor_within(pos : Vector2, max_distance : float) -> bool:
	var cpos := _grid.to_pixels(pos)
	var mpos := get_global_mouse_position()
	var distance := (cpos - mpos).length()
	return distance < _grid.to_pixelsf(max_distance) * _view.get_zoom()






