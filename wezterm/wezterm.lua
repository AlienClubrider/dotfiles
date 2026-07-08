local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.color_scheme = "rose-pine-moon"

config.font = wezterm.font("Hack Nerd Font")
config.font_size = 15

config.window_background_opacity = 0.8

config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = "RESIZE"

wezterm.on("gui-startup", function(cmd)
	local tab, pane, window = wezterm.mux.spawn_window(cmd or {})
	window:gui_window():maximize()
end)

return config
