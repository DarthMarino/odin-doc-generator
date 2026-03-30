package main
import "core:fmt"
import "core:os"
import "core:strings"
import "core:text/regex"

Metadata :: struct {
	comments:   [dynamic]string,
	attributes: [dynamic]string,
}

Parameter :: struct {
	name: string,
	type: string,
}

Signature :: struct {
	parameters:  [dynamic]Parameter,
	return_type: string,
}

Declaration :: struct {
	name:       string,
	cat:        string,
	file:       string,
	metadata:   Metadata,
	signature:  Signature,
	code_block: string,
	used_by:    [dynamic]string,
}


parse_declarations :: proc(file_path: string) -> [dynamic]Declaration {
	content_bytes, err := os.read_entire_file(file_path, context.allocator)
	if err != nil {
		fmt.panicf("Error reading %s\n", file_path)
	}

	content := string(content_bytes)
	lines := strings.split(content, "\n")

	// Regex Pattern
	pattern := `(\w+)\s*::\s*(proc|struct|enum|union)`
	re, compile_err := regex.create_iterator(content, pattern)
	if compile_err != nil {
		fmt.panicf("Regex compile error: %v\n", compile_err)
	}
	defer regex.destroy(re)

	declarations := make([dynamic]Declaration, context.allocator)

	for {
		capt, idx, ok := regex.match_iterator(&re)
		if !ok {
			break
		}
		name := capt.groups[1]
		cat := capt.groups[2]

		match_pos := capt.pos[0][0]
		line_num := strings.count(content[0:match_pos], "\n")

		metadata := extract_preceding_metadata(lines, line_num)

		code_block := get_code_block(content, match_pos)

		file_name := extract_file_name(file_path)

		signature: Signature
		if cat == "proc" {
			signature = extract_signature(code_block)
		} else {
			signature = Signature{} // Empty signature for non-procs
		}

		decl := Declaration {
			name       = name,
			cat        = cat,
			file       = file_name,
			metadata   = metadata,
			signature  = signature,
			code_block = code_block,
			used_by    = make([dynamic]string, context.allocator),
		}
		append(&declarations, decl)
	}
	return declarations
}

extract_preceding_metadata :: proc(lines: []string, line_number: int) -> Metadata {
	metadata: Metadata

	for i := line_number - 1; i >= 0; i -= 1 {
		line := strings.trim_space(lines[i])
		if len(line) == 0 {
			break
		}
		// Check if its a comment or an attribute
		if strings.has_prefix(line, "//") {
			append(&metadata.comments, line)
		} else if strings.has_prefix(line, "@") {
			append(&metadata.attributes, line)
		} else {
			break
		}
	}
	return metadata
}

parse_signature :: proc(param_string: string, return_type_string: string) -> Signature {
	params := make([dynamic]Parameter, context.temp_allocator)

	// Split into individual parameters
	individual_params := split_params(param_string)

	// For each parameter, split by : and extract name and type
	for param_str in individual_params {
		trimmed_str := strings.trim_space(param_str)
		res, err := strings.split(trimmed_str, ":")
		if err != nil {
			fmt.panicf("Error extracting from the param_string")
		}

		// Check that we actually have both name and type
		if len(res) < 2 {
			continue
		}

		param: Parameter
		param.name = strings.trim_space(res[0])
		param.type = strings.trim_space(res[1])

		append(&params, param)
	}

	return Signature{parameters = params, return_type = strings.trim_space(return_type_string)}
}

split_params :: proc(param_string: string) -> [dynamic]string {
	params := make([dynamic]string, context.temp_allocator)
	depth := 0
	current_param := strings.Builder{}

	for char in param_string {
		if char == '(' {
			depth += 1
			strings.write_rune(&current_param, char)
		} else if char == ')' {
			depth -= 1
			strings.write_rune(&current_param, char)
		} else if char == ',' && depth == 0 {
			// Top-level comma, split here
			param_str := strings.to_string(current_param)
			append(&params, strings.trim_space(param_str))
			current_param = strings.Builder{}
		} else {
			strings.write_rune(&current_param, char)
		}
	}

	// Don't forget the last parameter
	if len(current_param.buf) > 0 {
		append(&params, strings.trim_space(strings.to_string(current_param)))
	}

	return params
}

extract_signature :: proc(code_block: string) -> Signature {
	// Find "proc("
	proc_idx := strings.index(code_block, "proc(")
	if proc_idx == -1 {
		fmt.printf("Error, no proc was found on this block.")

	}
	closing_params_idx: int
	depth := 1
	for i := proc_idx + 5; i < len(code_block); i += 1 {
		char := code_block[i]
		if char == '(' {
			depth += 1
		} else if char == ')' {
			depth -= 1
		}
		if char == ')' && depth == 0 {
			closing_params_idx = i
			break
		}
	}
	// Extract parameter string
	param_string := code_block[proc_idx + 5:closing_params_idx]

	// Extract return type string
	return_type_idx := strings.index(code_block[closing_params_idx:], "->")
	return_type_string: string
	if return_type_idx == -1 {
		return_type_string = ""
	} else {
		return_type_idx += closing_params_idx
		return_type_string = code_block[return_type_idx + 2:]

		for i := 0; i < len(return_type_string); i += 1 {
			if return_type_string[i] == '{' {
				return_type_string = return_type_string[:i]
				break
			}
		}
	}
	// Call parse_signature()
	return parse_signature(param_string, return_type_string)
}

get_code_block :: proc(content: string, start_pos: int) -> string {
	brace_idx := strings.index(content[start_pos:], "{")
	if brace_idx == -1 {
		return ""
	}
	brace_idx += start_pos
	// Count braces to find matching }
	depth := 1
	closing_brace_idx := -1
	for i := brace_idx + 1; i < len(content); i += 1 {
		char := content[i]
		if char == '{' {
			depth += 1
		} else if char == '}' {
			depth -= 1
		}
		if char == '}' && depth == 0 {
			closing_brace_idx = i
			break
		}
	}
	return content[start_pos:closing_brace_idx + 1]
}

extract_file_name :: proc(file_path: string) -> string {
	last_slash := strings.last_index(file_path, "/")
	file_name: string
	if last_slash != -1 {
		file_name = file_path[last_slash + 1:]
	} else {
		file_name = file_path
	}
	return file_name
}
