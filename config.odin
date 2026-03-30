package main
import "core:encoding/json"
import "core:fmt"
import "core:os"

Config :: struct {
	project:    struct {
		name:        string,
		version:     string,
		description: string,
		repository:  string,
		page_title:  string,
	},
	paths:      struct {
		source_dir:   string,
		output_html:  string,
		template_dir: string,
		syntax_json:  string,
		style_css:    string,
		theme_css:    string,
	},
	sort_order: map[string]int,
}

load_config :: proc(config_path: string) -> Config {
	config_bytes, err := os.read_entire_file(config_path, context.allocator)
	if err != nil {
		fmt.panicf("Error: could not read config file -> %s\n", config_path)
	}
	config := Config{}
	unmarshal_err := json.unmarshal(config_bytes, &config)
	if unmarshal_err != nil {
		fmt.panicf("Error: could not parse config file -> %s\n", config_path)
	}

	return config
}
