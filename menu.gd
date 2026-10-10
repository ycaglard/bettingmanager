extends Control

const UITheme = preload("res://scripts/ui_theme.gd")


func _ready() -> void:
	theme = UITheme.build()
	$CenterContainer/VBoxContainer/TitleLabel.theme_type_variation = &"DisplayLabel"
	for button in [$CenterContainer/VBoxContainer/OptionsButton, $CenterContainer/VBoxContainer/QuitButton]:
		button.custom_minimum_size = Vector2(320, 56)
	var start: Button = $CenterContainer/VBoxContainer/StartButton
	start.theme_type_variation = &"PrimaryButton"
	start.custom_minimum_size = Vector2(320, 64)


func _on_start_button_pressed() -> void:
	get_tree().change_scene_to_file("res://game.tscn")


func _on_options_button_pressed() -> void:
	print("Options pressed (not implemented yet)")


func _on_quit_button_pressed() -> void:
	get_tree().quit()
