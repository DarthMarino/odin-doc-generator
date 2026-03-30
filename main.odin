package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:text/regex"

main :: proc() {
	args := os.args

	dir := "."
	config_path := "./config.json"
	embed := false

	for i := 1; i < len(args); i += 1 {
		if args[i] == "--dir" && i + 1 < len(args) {
			dir = args[i + 1]
			break
		}
		if args[i] == "--config" && i + 1 < len(args) {
			config_path = args[i + 1]
		}
		if args[i] == "--embed" {
			embed = true
		}
	}

	config := load_config(config_path)

	// Verify source directory exists
	stat, err := os.stat(dir, context.allocator)
	if err != nil {
		fmt.panicf("Error: directory not found -> %s\n", dir)
	}
	if stat.type != os.File_Type.Directory {
		fmt.panicf("Error: path is not a directory -> %s\n", dir)
	}

	all_declarations := collect_declarations(dir)

	// Analyze cross-references across all files
	analyze_cross_references(all_declarations)

	template_path := strings.concatenate(
		{config.paths.template_dir, "/template.html"},
		context.temp_allocator,
	)
	html_output := generate_html(template_path, config, all_declarations, embed)

	output_path := config.paths.output_html
	err = os.write_entire_file(output_path, transmute([]byte)html_output)
	if err != nil {
		fmt.panicf("Error: could not write output file -> %s\n", output_path)
	}

	fmt.printf("Done: HTML generated -> %s\n", output_path)
}

collect_declarations :: proc(dir: string) -> [dynamic]Declaration {
	entries, dir_err := os.read_directory_by_path(dir, 0, context.allocator)
	if dir_err != nil {
		fmt.panicf("Error: could not read directory -> %s\n", dir)
	}

	declarations := make([dynamic]Declaration, context.allocator)
	for entry in entries {
		if entry.type == os.File_Type.Directory {
			continue
		}
		if !strings.has_suffix(entry.name, ".odin") {
			continue
		}
		file_path := strings.concatenate({dir, "/", entry.name}, context.allocator)
		for decl in parse_declarations(file_path) {
			append(&declarations, decl)
		}
	}
	return declarations
}

analyze_cross_references :: proc(declarations: [dynamic]Declaration) {
	name_to_decl := map[string]Declaration{}
	for decl in declarations {
		name_to_decl[decl.name] = decl
	}

	for decl, i in declarations {
		ident_pattern := `\b([A-Za-z_]\w*)\b`
		re, _ := regex.create_iterator(decl.code_block, ident_pattern)
		defer regex.destroy(re)

		added: map[string]bool

		for {
			capt, _, ok := regex.match_iterator(&re)
			if !ok {break}

			ident := capt.groups[1]

			if other_decl, found := name_to_decl[ident]; found && other_decl.name != decl.name {
				ref_id := strings.concatenate({decl.file, "--", decl.name}, context.allocator)

				// Only add if we haven't already
				if !added[ref_id] {
					for other, j in declarations {
						if other.name == other_decl.name {
							append(&declarations[j].used_by, ref_id)
							added[ref_id] = true
							break
						}
					}
				}
			}
		}
	}
}
