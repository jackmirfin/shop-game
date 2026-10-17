extends Node
## One small autoload: doorway contact loads the next authored room scene directly.

const ROOM_DIRECTORY: String = "res://scenes/cave_rooms/"
const ROUTES: Dictionary = {
	"room_2": {"exit": "room_6"},
	"room_6": {"entrance": "room_2", "exit": "hallway_3"},
	"hallway_3": {"entrance": "room_6", "exit": "room_3"},
	"room_3": {"entrance": "hallway_3", "exit": "room_5", "exit2": "room_1"},
	"room_5": {"entrance": "room_3", "exit": "room_8"},
	"room_1": {"entrance": "room_3", "exit": "hallway_1"},
	"hallway_1": {"entrance": "room_1", "exit": "room_4"},
	"room_4": {"entrance": "hallway_1", "exit": "room_8"},
	"room_8": {"entrance": "branch_return", "exit": "branch_forward"},
	"hallway_2": {"entrance": "room_8", "exit": "treasure_room_1", "exit2": "room_7"},
	"treasure_room_1": {"entrance": "hallway_2"},
	"room_7": {"entrance": "hallway_2"},
	"treasure_room_2": {"entrance": "room_8"},
}

var _wired_scene_id: int = 0
var _previous_room_key: String = ""
var _branch_a: bool = false
var _transitioning: bool = false

func _process(_delta: float) -> void:
	var active_scene: Node = get_tree().current_scene
	if active_scene == null:
		return
	var scene_id: int = active_scene.get_instance_id()
	if scene_id == _wired_scene_id:
		return
	_wired_scene_id = scene_id
	_transitioning = false
	var scene_path: String = active_scene.scene_file_path
	var scene_basename: String = scene_path.get_file().get_basename()
	if scene_basename == "northern_forest":
		_request_preload(ROOM_DIRECTORY + "room_2.tscn")
		return
	if not scene_path.begins_with(ROOM_DIRECTORY):
		return
	var room_key: String = scene_basename
	if room_key == "room_2":
		_previous_room_key = ""
		_branch_a = false
	var room_routes: Dictionary = ROUTES.get(room_key, {}) as Dictionary
	for connector_name: String in room_routes:
		var doorway: Area2D = active_scene.get_node_or_null(NodePath(connector_name)) as Area2D
		if doorway == null:
			continue
		doorway.collision_mask = 4
		doorway.monitoring = true
		var callback: Callable = _on_doorway_body_entered.bind(room_key, connector_name)
		if not doorway.body_entered.is_connected(callback):
			doorway.body_entered.connect(callback)
	_prefetch_routes(room_key, room_routes)

func _prefetch_routes(room_key: String, room_routes: Dictionary) -> void:
	for connector_name: String in room_routes:
		var destination_key: String = _get_destination_key(room_key, connector_name, room_routes)
		if destination_key.is_empty() or destination_key == "branch_return" or destination_key == "branch_forward":
			continue
		_request_preload(ROOM_DIRECTORY + destination_key + ".tscn")

func _request_preload(destination_path: String) -> void:
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(destination_path)
	if status != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		return
	var request_error: Error = ResourceLoader.load_threaded_request(destination_path, "PackedScene", true)
	if request_error != OK and request_error != ERR_BUSY:
		push_warning("Could not pre-load cave room %s (%s)" % [destination_path, request_error])

func _get_destination_key(room_key: String, connector_name: String, room_routes: Dictionary) -> String:
	var destination_key: String = str(room_routes.get(connector_name, ""))
	if room_key == "room_8":
		if connector_name == "entrance":
			destination_key = "hallway_2" if _previous_room_key == "hallway_2" else ("room_5" if _branch_a else "room_4")
		else:
			destination_key = "hallway_2" if _branch_a else "treasure_room_2"
	return destination_key

func _on_doorway_body_entered(body: Node2D, room_key: String, connector_name: String) -> void:
	if _transitioning or not body.is_in_group("player"):
		return
	var room_routes: Dictionary = ROUTES.get(room_key, {}) as Dictionary
	var destination_key: String = _get_destination_key(room_key, connector_name, room_routes)
	if destination_key.is_empty() or destination_key == "branch_return" or destination_key == "branch_forward":
		return
	if destination_key == "room_8":
		_branch_a = room_key == "room_5"
	_transitioning = true
	_previous_room_key = room_key
	call_deferred("_change_room", ROOM_DIRECTORY + destination_key + ".tscn")

func _change_room(destination_path: String) -> void:
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(destination_path)
	if status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		var request_error: Error = ResourceLoader.load_threaded_request(destination_path, "PackedScene", true)
		if request_error != OK and request_error != ERR_BUSY:
			_transitioning = false
			push_error("Cave room preload failed: %s (%s)" % [destination_path, request_error])
			return
		status = ResourceLoader.load_threaded_get_status(destination_path)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(destination_path)
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		_transitioning = false
		push_error("Cave room preload did not complete: %s (status %s)" % [destination_path, status])
		return
	var next_scene: PackedScene = ResourceLoader.load_threaded_get(destination_path) as PackedScene
	if next_scene == null:
		_transitioning = false
		push_error("Cave room preload returned no PackedScene: %s" % destination_path)
		return
	var error: Error = get_tree().change_scene_to_packed(next_scene)
	if error != OK:
		_transitioning = false
		push_error("Cave room transition failed: %s (%s)" % [destination_path, error])