package main
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"


// Global so nested sort procs can read it — Odin nested procs cannot capture locals from parent scopes.
CURRENT_SORT_ORDER: map[string]int

Toc_Item :: struct {
	id, name, cat: string,
}

Syntax :: struct {
	keywords:      [dynamic]string,
	builtin_types: [dynamic]string,
	builtin_procs: [dynamic]string,
	literals:      [dynamic]string,
}

generate_html :: proc(
	template_path: string,
	config: Config,
	declarations: [dynamic]Declaration,
	embed: bool,
) -> string {
	template_bytes, err := os.read_entire_file(template_path, context.allocator)
	if err != nil {
		fmt.panicf("Error: could not read template file -> %s\n", template_path)
	}

	template := string(template_bytes)
	content_html := generate_content_html(declarations, config.sort_order)


	replacements := make(map[string]string, context.temp_allocator)
	replacements["{{project_name}}"] = config.project.name
	replacements["{{version}}"] = config.project.version
	replacements["{{description}}"] = config.project.description
	replacements["{{repository}}"] = config.project.repository
	replacements["{{page_title}}"] = config.project.page_title
	replacements["{{content}}"] = content_html

	style_content: string
	if embed {
		style_bytes, _ := os.read_entire_file(config.paths.style_css, context.allocator)
		style_content = strings.concatenate(
			{"<style>", string(style_bytes), "</style>"},
			context.temp_allocator,
		)
	} else {
		style_content = config.paths.style_css
	}
	replacements["{{style_css}}"] = style_content

	theme_content: string
	if embed {
		theme_bytes, _ := os.read_entire_file(config.paths.theme_css, context.allocator)
		theme_content = strings.concatenate(
			{"<style>", string(theme_bytes), "</style>"},
			context.temp_allocator,
		)
	} else {
		theme_content = config.paths.theme_css
	}
	replacements["{{theme_css}}"] = theme_content

	replacements["{{toc_json}}"] = build_toc_json(declarations)

	syntax_path := config.paths.syntax_json
	syntax_bytes, syn_err := os.read_entire_file(syntax_path, context.allocator)
	if syn_err != nil {
		fmt.panicf("Error: could not read syntax file -> %s\n", syntax_path)
	}
	syntax: Syntax
	syntax_err := json.unmarshal(syntax_bytes, &syntax)
	if syntax_err != nil {
		fmt.panicf("Error: could not parse syntax file -> %v\n", syntax_err)
	}

	replacements["{{highlight_rules}}"] = build_highlight_rules(syntax)
	replacements["{{item_count}}"] = fmt.aprintf("%d", len(declarations))

	now := time.now()
	time_buf: [time.MIN_YYYY_DATE_LEN]u8
	generated_at := time.to_string_dd_mm_yyyy(now, time_buf[:])
	replacements["{{generated_at}}"] = generated_at

	// Apply all replacements
	result := template
	for key, value in replacements {
		result, _ = strings.replace_all(result, key, value)
	}
	return result
}

build_toc_json :: proc(declarations: [dynamic]Declaration) -> string {
	toc := make(map[string][dynamic]Toc_Item, context.temp_allocator)
	for decl in declarations {
		if toc[decl.file] == nil {
			toc[decl.file] = make([dynamic]Toc_Item, context.temp_allocator)
		}
		append(
			&toc[decl.file],
			Toc_Item {
				id = strings.concatenate({decl.file, "--", decl.name}, context.temp_allocator),
				name = decl.name,
				cat = decl.cat,
			},
		)
	}
	// Sort
	for file, items in toc {
		slice.sort_by(items[:], proc(a, b: Toc_Item) -> bool {
			type_a := CURRENT_SORT_ORDER[a.cat]
			type_b := CURRENT_SORT_ORDER[b.cat]
			if type_a != type_b {
				return type_a < type_b
			}
			return a.name < b.name
		})
	}
	b: strings.Builder
	strings.write_string(&b, "{")
	i := 0
	for file, items in toc {
		if i > 0 {strings.write_string(&b, ",")}
		strings.write_string(&b, "\"")
		strings.write_string(&b, file)
		strings.write_string(&b, "\":[")
		for item, j in items {
			if j > 0 {strings.write_string(&b, ",")}
			strings.write_string(&b, "{\"id\":\"")
			strings.write_string(&b, item.id)
			strings.write_string(&b, "\",\"name\":\"")
			strings.write_string(&b, item.name)
			strings.write_string(&b, "\",\"cat\":\"")
			strings.write_string(&b, item.cat)
			strings.write_string(&b, "\"}")
		}
		strings.write_string(&b, "]")
		i += 1
	}
	strings.write_string(&b, "}")
	return strings.to_string(b)
}


strip_comment_prefix :: proc(line: string) -> string {
	if strings.has_prefix(line, "// ") { return line[3:] }
	if strings.has_prefix(line, "//")  { return line[2:] }
	return line
}

declaration_to_html :: proc(decl: Declaration) -> string {
	b: strings.Builder

	strings.write_string(&b, `<details id="`)
	strings.write_string(&b, decl.file)
	strings.write_string(&b, `--`)
	strings.write_string(&b, decl.name)
	strings.write_string(&b, `">`)

	strings.write_string(&b, "\n    <summary>")
	strings.write_string(&b, "\n        <span class=\"item-name\">")
	strings.write_string(&b, decl.name)
	strings.write_string(&b, "</span>")

	if len(decl.metadata.comments) > 0 {
		strings.write_string(&b, "\n        <span class=\"item-doc-preview\">")
		text := strings.trim_space(strip_comment_prefix(decl.metadata.comments[len(decl.metadata.comments) - 1]))
		if len(text) > 50 {
			text = text[:50]
			strings.write_string(&b, text)
			strings.write_string(&b, "...")
		} else {
			strings.write_string(&b, text)
		}
		strings.write_string(&b, "</span>")
	}

	strings.write_string(&b, "\n        <span class=\"badge badge-")
	strings.write_string(&b, decl.cat)
	strings.write_string(&b, `">`)
	strings.write_string(&b, strings.to_upper(decl.cat, context.temp_allocator))
	strings.write_string(&b, "</span>")
	strings.write_string(&b, "\n    </summary>")

	if len(decl.metadata.comments) > 0 {
		strings.write_string(&b, "\n    <div class=\"doc-text\">")
		for i := len(decl.metadata.comments) - 1; i >= 0; i -= 1 {
			text := strip_comment_prefix(decl.metadata.comments[i])
			if i < len(decl.metadata.comments) - 1 {
				strings.write_string(&b, " ")
			}
			strings.write_string(&b, text)
		}
		strings.write_string(&b, "</div>")
	}

	if len(decl.signature.parameters) > 0 {
		strings.write_string(&b, "\n    <div class=\"sig-bar\">")
		strings.write_string(&b, "\n        <span class=\"sig-label\">params</span>")
		strings.write_string(&b, "\n        <span class=\"sig-val\">")
		for param, i in decl.signature.parameters {
			if i > 0 {
				strings.write_string(&b, ", ")
			}
			strings.write_string(&b, param.name)
			strings.write_string(&b, ": ")
			strings.write_string(&b, param.type)
		}
		strings.write_string(&b, "</span>")
		strings.write_string(&b, "\n    </div>")
	}
	if len(decl.used_by) > 0 {
		strings.write_string(&b, "\n    <div class=\"refs-bar\">")
		strings.write_string(&b, "\n        <span class=\"refs-label\">used by</span>")
		for ref_id in decl.used_by {
			strings.write_string(&b, "\n        <a class=\"ref-link\" href=\"#")
			strings.write_string(&b, ref_id)
			strings.write_string(&b, "\">")
			// Extract just the name from "file--name"
			last_dash := strings.last_index(ref_id, "--")
			if last_dash != -1 {
				strings.write_string(&b, ref_id[last_dash + 2:])
			} else {
				strings.write_string(&b, ref_id)
			}
			strings.write_string(&b, "</a>")
		}
		strings.write_string(&b, "\n    </div>")
	}
	strings.write_string(&b, "\n    <div class=\"content\">")
	strings.write_string(&b, "\n        <div class=\"code-header\">")
	strings.write_string(&b, "\n            <span class=\"code-file\">")
	strings.write_string(&b, decl.file)
	strings.write_string(&b, "</span>")
	strings.write_string(&b, "\n            <button class=\"copy-btn\">Copy</button>")
	strings.write_string(&b, "\n        </div>")
	strings.write_string(&b, "\n        <pre><code class=\"language-odin\">")
	escaped_code := escape_html(decl.code_block)
	strings.write_string(&b, escaped_code)
	strings.write_string(&b, "</code></pre>")
	strings.write_string(&b, "\n    </div>")
	strings.write_string(&b, "\n</details>")

	return strings.to_string(b)
}

generate_content_html :: proc(
	declarations: [dynamic]Declaration,
	sort_order: map[string]int,
) -> string {

	CURRENT_SORT_ORDER = sort_order

	// Make a copy so we don't modify the original
	sorted_decls := make([dynamic]Declaration, context.allocator)
	for decl in declarations {
		append(&sorted_decls, decl)
	}

	slice.sort_by(sorted_decls[:], proc(a, b: Declaration) -> bool {
		if a.file != b.file {
			return a.file < b.file
		}
		type_a := CURRENT_SORT_ORDER[a.cat]
		type_b := CURRENT_SORT_ORDER[b.cat]
		if type_a != type_b {
			return type_a < type_b
		}
		return a.name < b.name
	})

	// Generate HTML
	b: strings.Builder
	current_file := ""

	for decl in sorted_decls {
		// If file changed, start a new file section
		if decl.file != current_file {
			if current_file != "" {
				strings.write_string(&b, "\n    </div>") // Close previous section
			}
			current_file = decl.file
			strings.write_string(&b, "\n    <div class=\"file-section\">")
			strings.write_string(&b, "\n        <div class=\"file-header\">")
			strings.write_string(&b, current_file)
			strings.write_string(&b, "</div>")
		}

		// Add the declaration
		strings.write_string(&b, "\n        ")
		strings.write_string(&b, declaration_to_html(decl))
	}

	// Close the last section
	if current_file != "" {
		strings.write_string(&b, "\n    </div>")
	}

	return strings.to_string(b)
}

escape_html :: proc(s: string) -> string {
	b: strings.Builder
	for char in s {
		switch char {
		case '<':
			strings.write_string(&b, "&lt;")
		case '>':
			strings.write_string(&b, "&gt;")
		case '&':
			strings.write_string(&b, "&amp;")
		case '"':
			strings.write_string(&b, "&quot;")
		case '\'':
			strings.write_string(&b, "&#39;")
		case:
			strings.write_rune(&b, char)
		}
	}
	return strings.to_string(b)
}

build_highlight_rules :: proc(syntax: Syntax) -> string {
	b: strings.Builder
	strings.write_string(&b, "var RULES = [")

	// Comments
	strings.write_string(&b, "{cls: \"cm\", re: /\\/\\*[\\s\\S]*?\\*\\//g},")
	strings.write_string(&b, "{cls: \"cm\", re: /\\/\\/[^\\n]*/g},")

	// Strings
	strings.write_string(&b, "{cls: \"str\", re: /`[^`]*`/g},")
	strings.write_string(&b, "{cls: \"str\", re: /\"(?:[^\"\\\\]|\\\\.)*\"/g},")

	// Keywords
	strings.write_string(&b, "{cls: \"kw\", re: /\\b(?:")
	for kw, i in syntax.keywords {
		if i > 0 {strings.write_string(&b, "|")}
		strings.write_string(&b, kw)
	}
	strings.write_string(&b, ")\\b/g},")

	// Built-in types
	strings.write_string(&b, "{cls: \"ty\", re: /\\b(?:")
	for typ, i in syntax.builtin_types {
		if i > 0 {strings.write_string(&b, "|")}
		strings.write_string(&b, typ)
	}
	strings.write_string(&b, ")\\b/g},")

	// Built-in procs
	strings.write_string(&b, "{cls: \"bi\", re: /\\b(?:")
	for procedure, i in syntax.builtin_procs {
		if i > 0 {
			strings.write_string(&b, "|")
		}
		strings.write_string(&b, procedure)
	}
	strings.write_string(&b, ")\\b/g},")

	// Literals
	strings.write_string(&b, "{cls: \"bl\", re: /\\b(?:")
	for lit, i in syntax.literals {
		if i > 0 {strings.write_string(&b, "|")}
		strings.write_string(&b, lit)
	}
	strings.write_string(&b, ")\\b/g},")

	strings.write_string(&b, "];")
	return strings.to_string(b)
}
