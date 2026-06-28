class_name DeepGrubGroovesFlyout
extends CanvasLayer

# ---------------------------------------------------------------------------
# Deep Grub Grooves — music-selection flyout
# Connects to the global SoundController autoload.
# ---------------------------------------------------------------------------

var panel_container: PanelContainer
var current_track_label: Label
var tracks_container: VBoxContainer
var no_tracks_label: Label
var stop_button: Button
var is_open: bool = false  # Start closed

# Reference to the global SoundController autoload.
var _sc: Node


func _ready() -> void:
	# Access autoload via /root path (standard Godot pattern).
	_sc = get_node_or_null("/root/SoundController")
	if _sc == null:
		push_warning("DeepGrubGroovesFlyout: SoundController autoload not found at /root/SoundController.")
	# --- Create panel ---
	panel_container = PanelContainer.new()
	panel_container.size = Vector2(360, 400)
	panel_container.position = Vector2(-400, 10)  # Off-screen → hidden

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color.html("#2a2a3e")
	style.border_color = Color.html("#888888")
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.content_margin_left = 12
	style.content_margin_top = 12
	style.content_margin_right = 12
	style.content_margin_bottom = 12
	panel_container.add_theme_stylebox_override("panel", style)

	# --- Main layout ---
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(336, 350)

	# Title
	var title: Label = Label.new()
	title.text = "DEEP GRUB GROOVES"
	title.add_theme_font_size_override("font_size", 16)
	title.modulate = Color.WHITE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Current track display
	current_track_label = Label.new()
	current_track_label.add_theme_font_size_override("font_size", 13)
	current_track_label.modulate = Color.html("#aaaaaa")
	vbox.add_child(current_track_label)

	# Separator
	vbox.add_child(HSeparator.new())

	# Tracks section header
	var tracks_header: Label = Label.new()
	tracks_header.text = "Available Tracks"
	tracks_header.add_theme_font_size_override("font_size", 14)
	tracks_header.modulate = Color.WHITE
	vbox.add_child(tracks_header)

	# Container for dynamic track buttons
	tracks_container = VBoxContainer.new()
	vbox.add_child(tracks_container)

	# "No tracks" placeholder
	no_tracks_label = Label.new()
	no_tracks_label.text = "No tracks installed."
	no_tracks_label.add_theme_font_size_override("font_size", 12)
	no_tracks_label.modulate = Color.html("#888888")
	vbox.add_child(no_tracks_label)

	# Stop button
	stop_button = Button.new()
	stop_button.text = "Stop"
	stop_button.focus_mode = Control.FOCUS_NONE
	stop_button.pressed.connect(_on_stop_pressed)
	vbox.add_child(stop_button)

	panel_container.add_child(vbox)
	add_child(panel_container)

	# --- Initialise ---
	_refresh_tracks()
	_update_panel()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("toggle_grooves"):
		toggle_panel()


func toggle_panel() -> void:
	is_open = not is_open
	if is_open:
		_refresh_tracks()
	_update_panel()
	print("Deep Grub Grooves %s." % ("opened" if is_open else "closed"))


# ---------------------------------------------------------------------------
# Track list management
# ---------------------------------------------------------------------------

func _refresh_tracks() -> void:
	# Clear old buttons
	for child: Node in tracks_container.get_children():
		child.queue_free()

	var tracks: Array = _sc.get_available_tracks()

	if tracks.is_empty():
		no_tracks_label.show()
	else:
		no_tracks_label.hide()
		for track_name: String in tracks:
			var btn: Button = Button.new()
			btn.text = track_name
			btn.focus_mode = Control.FOCUS_NONE
			btn.pressed.connect(_on_track_pressed.bind(track_name))
			tracks_container.add_child(btn)

	_update_current_track_label()


func _update_current_track_label() -> void:
	var current: String = _sc.get_current_track_name()
	if current.is_empty():
		current_track_label.text = "Current Track: None"
	else:
		current_track_label.text = "Current Track: %s" % current


# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------

func _on_track_pressed(track_name: String) -> void:
	_sc.play_music(track_name)
	_update_current_track_label()
	_clear_ui_focus()


func _on_stop_pressed() -> void:
	_sc.stop_music()
	_update_current_track_label()
	_clear_ui_focus()


# ---------------------------------------------------------------------------
# Panel visibility
# ---------------------------------------------------------------------------

func _update_panel() -> void:
	if is_open:
		panel_container.visible = true
		panel_container.position = Vector2(10, 10)
	else:
		panel_container.visible = false
		_clear_ui_focus()


func _clear_ui_focus() -> void:
	var viewport := get_viewport()
	if viewport:
		viewport.gui_release_focus()
