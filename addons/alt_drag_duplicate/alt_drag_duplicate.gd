@tool
extends EditorPlugin


func print_info(...args) -> void:
	var console_text_color = EditorInterface.get_editor_theme().get_color(&"comment_color", &"EditorHelp").to_html()
	print_rich.callv(["[color=" + console_text_color + "]AltDragDuplicate: "] + args + ["[/color]"])

func _enter_tree() -> void:
	print_info("Plugin loaded")

func _exit_tree() -> void:
	print_info("Plugin unloaded")


func _handles(object: Object) -> bool:
	return (object is Node) or (object.get_class() == "MultiNodeEdit")

func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	return handle_gui_input(event)


## Borrows heavily from editor/docks/scene_tree_dock.cpp
## so as to maintain parity with the editor's node duplication (Ctrl+D).
## Supports duplicating multiple nodes, and the editable children of nodes.
func handle_gui_input(event: InputEvent) -> int:
	var undo_redo := get_undo_redo()
	var editor_selection := EditorInterface.get_selection()
	var selection := editor_selection.get_top_selected_nodes()
	var edited_scene := EditorInterface.get_edited_scene_root()
	
	if event is InputEventMouseButton:
		if (not selection.is_empty()
			and Input.is_key_pressed(KEY_ALT)
			and event.button_index == MouseButton.MOUSE_BUTTON_LEFT
			and event.is_pressed()
			):
			
			if (selection.is_empty()):
				return EditorPlugin.AfterGUIInput.AFTER_GUI_INPUT_PASS
			
			if (selection.has(edited_scene)):
				print_info("Cannot duplicate the tree root")
				return EditorPlugin.AfterGUIInput.AFTER_GUI_INPUT_PASS
			
			undo_redo.create_action("Duplicate Node(s)█████", UndoRedo.MERGE_DISABLE, edited_scene)
			undo_redo.add_do_method(editor_selection, &"clear")
			
			selection.sort_custom(node_comparator)
			
			var add_below_map : Dictionary[Node, Node]
			
			# loop through nodes in reverse
			# and add to map if we haven't seen this parent yet
			# (gets the last selected node under each parent)
			
			for i in range(len(selection)-1, -1, -1):
				var node : Node = selection[i]
				if !add_below_map.has(node.get_parent()):
					add_below_map[node.get_parent()] = node
			
			for node in selection:
				var parent : Node = node.get_parent()
				
				var owned : Array[Node]
				var owner_ : Node = node
				while owner_ != null:
					var cur_owned : Array[Node]
					get_owned_by(node, owner_, cur_owned)
					owner_ = owner_.owner
					owned.append_array(cur_owned)
				
				var dup : Node = node.duplicate()
				
				undo_redo.add_do_method(add_below_map[parent], &"add_sibling", dup, true)
				
				for F in owned:
					var n = dup.get_node_or_null(node.get_path_to(F))
					if n != null:
						if F.owner == node:
							undo_redo.add_do_method(n, &"set_owner", dup)
						elif F.owner == node.owner:
							undo_redo.add_do_method(n, &"set_owner", edited_scene)
						else:
							undo_redo.add_do_method(self, &"set_owner_to_corresponding", node, F, dup, n)
				
				undo_redo.add_do_method(editor_selection, &"add_node", dup)
				undo_redo.add_do_reference(dup)
				
				undo_redo.add_undo_method(parent, &"remove_child", dup)
				
				add_below_map[parent] = dup
			
			undo_redo.commit_action(true)
	
	return EditorPlugin.AfterGUIInput.AFTER_GUI_INPUT_PASS


func get_owned_by(the_node : Node, by : Node, owned : Array[Node]) -> void:
	if the_node.owner == by:
		owned.push_back(the_node)
	for k in the_node.get_children():
		get_owned_by(k, by, owned)

func set_owner_to_corresponding(parent : Node, child : Node, new_parent : Node, new_child : Node) -> void:
	new_child.owner = get_corresponding_owner(parent, child, new_parent)

func get_corresponding_owner(parent : Node, child : Node, new_parent : Node) -> Node:
	return new_parent.get_node_or_null(parent.get_path_to(child.owner))

func node_comparator(a: Node, b: Node):
	return b.is_greater_than(a)
