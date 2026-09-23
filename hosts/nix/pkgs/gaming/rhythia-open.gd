extends Node

# The release ignores filename arguments; reuse its map/replay drop handler.
func _ready() -> void:
    var files := OS.get_cmdline_user_args()
    if files.is_empty():
        return
    var viewport := get_tree().root
    while viewport.get_signal_connection_list("files_dropped").is_empty():
        await get_tree().process_frame
    await get_tree().process_frame
    viewport.files_dropped.emit(files)
