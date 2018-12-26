#!/usr/bin/env -S awk -v verbose=0 -v sorted=0 -v implicit=0 -v unsearched_implicit=0 -f

# Licensed under the MIT license

# An "almost-processor" for Makefiles, with the ability to search targets.
#
# Usage:
#    make -n -p | awk -f make-dump.awk SOME_TARGET_TO_SEARCH_FOR
#
# NOTE 1: Sorting can BREAK the Makefile, since some directives affect future ones. Do not attempt to re-run after sorting.
# NOTE 2: Multiline variables will not parse back into themselves, so watch out for those.
# NOTE 3: This tool is not bulletproof; it's mainly meant to help with debugging.

function process(line) {
	if (substr(line, 1, 1) == "#") {
		k1 = index(line, "\n");
		comment = substr(line, 1, k1 - 1);
		line = substr(line, k1 + 1);
		if (length(targets_to_show) == 0) {
			if (comment != prev_comment) {
				if (prev_comment) {
					print("");
				}
				print("####" comment " #####");
				print("");
			}
		}
		if (comment == "# Files") {
			line = unescape_recipe(line);
		}
		if (comment == "# Variables" && substr(line, 1, 1) != "#") {
			gsub(/\\/, "\\\\\\\\", line);
			gsub(/#/, "\\\\#", line);
		}
		if (implicit == 1 && comment == "# Files" || !implicit && comment == "# Implicit Rules") {
			line = "#" line;
			gsub(/\n/, "\n#", line);
			line = color_(line, "32");
		}
		if (color) {
			if (comment == "# Files" || comment == "# Variables") {
				ieq = index(line, comment == "# Variables" ? "=" : ":");
				if (ieq > 0) {
					neq = 1;
					if (ieq > 1 && comment == "# Variables" && index(":+", substr(line, ieq - 1, 1))) {
						++neq;
						--ieq;
					}
					line = color_(substr(line, 1, ieq - 1), "32;1") color_(substr(line, ieq, neq), "35;1") substr(line, ieq + neq);
				}
			}
		}
		if (comment == "# Variables") {
			ieq = index(line, "=");
			if (ieq > 1 && substr(line, ieq - 2, 2 + 1) == " :=") {
				if (ENVIRON[substr(line, 1, ieq - 3)] == substr(line, ieq + 1 + 1)) {
					line = "export " line;
				}
			}
			if (index(line, "MAKEFLAGS") == 1) {
				gsub(/ = \w+/, " =", line);
				gsub(/ -j[0-9]*/, "", line);
			} else if (index(line, "MFLAGS") == 1 || index(line, "MAKEOVERRIDES") == 1 || index(line, "MAKECMDGOALS") == 1) {
				line = "#" line;
			}
		}
		prev_comment = comment;
	}
	if (verbose && processed_lines++) {
		print("");
	}
	if (length(line) > 0) {
		print(line);
	}
}
function unescape_recipe(line) {
	DOLLAR_COLOR_CODE = "33;1";
	itab = index(line, "\t");
	if (itab) {
		line_so_far = substr(line, 1, itab - 1);
		stem_definition_pattern = "# * := ";
		istem_definition = index(line_so_far, stem_definition_pattern);
		if (istem_definition || 1) {
			stem_definition = istem_definition ? substr(substr(line_so_far, istem_definition), 1 + length(stem_definition_pattern)) : color_("$*", DOLLAR_COLOR_CODE);
			gsub(/\n.*/, "", stem_definition);
			if (!verbose) {
				# Remove the comment since it wouldn't have been included in non-verbose output
				if (istem_definition) {
					line_so_far = substr(line_so_far, 1, istem_definition - 1) substr(line_so_far, istem_definition + length(stem_definition_pattern) + length(stem_definition) + 1);
				}
			}
			line_remaining = substr(line, itab);
			while (1) {
				idollar = index(line_remaining, "$");
				if (!idollar) {
					break;
				}
				char_with_dollar = substr(line_remaining, idollar, 2);
				if (char_with_dollar == "$*") {
					char_with_dollar = stem_definition;
				} else if (color) {
					char_with_dollar = char_with_dollar == "$(" || char_with_dollar == "${" ? color_(substr(char_with_dollar, 1, 1), DOLLAR_COLOR_CODE) substr(char_with_dollar, 2) : color_(char_with_dollar, DOLLAR_COLOR_CODE);
				}
				line_so_far = line_so_far substr(line_remaining, 1, idollar - 1) char_with_dollar;
				line_remaining = substr(line_remaining, idollar + 2);
			}
			line = line_so_far line_remaining;
		}
	}
	return line;
}
function color_(text, code) {
	return color ? "\x1B[0;" code "m" text "\x1B[0m" : text;
}
function start_item() {
	keep = 0;
	special = 0;
	implicit_not_done = 0;
	phony = 0;
	stem = 0;
	exists = 0;
	if (length(targets_to_show) == 0) {
		keep = 1;
	} else {
		target = $0;
		j = index(target, ":");
		if (j) {
			target = substr(target, 1, j - 1);
		}
		for (j = 1; j <= length(targets_to_show); ++j) {
			if (target ~ targets_to_show[j]) {
				keep = 1;
				break;
			}
		}
	}
	begin = NR;
	line = "";
}
function finish_item() {
	keep = keep && (special || phony || (!implicit_not_done || unsearched_implicit || stem || exists));
	n = length(line);
	if (n > 0) {
		if (substr(line, n, 1) == "\n") {
			line = substr(line, 1, n - 1);
		}
		if (keep) {
			if (section == "# Variables") {
				gsub(/\\/, "\\\\", line);
				gsub(/\x1B/, "\\x1B", line);
			}
			if (sorted) {
				lines[++i] = line;
			} else {
				process(line);
			}
		}
	}
	line = "";
	begin = 0;
}
BEGIN {
	if (length(verbose) == 0) {
		verbose = 0;
	}
	if (length(ARGV) > 1) {
		targets_to_show[1] = ARGV[1];
		delete ARGV[1];
	}
	if (length(color) == 0) {
		if (system("test -t 1") == 0) {
			color = 1;
		}
	}
}
/^#/ && section == "# Directories" {
	finish_item();
	keep = verbose > 1 || !index($0, ", no impossibilities");
}
/^# (files hash-table stats:|\d+ .* in \d+ directories\.|\d+ implicit_not_done rules, \d+ ([^()]*%) terminal.)$/ {
	finish_item();
	section = 0;
}
/^# Not a target:$/ {
	keep = 0;
}
/^[^#\t\r\n]/ && section ~ /^# (Implicit Rules|Files|Directories)$/ {
	finish_item();
	start_item();
}
/^#/ && section ~ /^# (Variables)$/ {
	finish_item();
	start_item();
}
/^$/ && section == "# Files" {
	finish_item();
	start_item();
}
(verbose > 0 || !/^#/ || /^# \* := /) && (verbose > 1 || !/[@%+|<^?] := / && !/#\s*((Successfully|File has been) updated\.|Also makes:|Last modified |Implicit\/static pattern stem:)/) && (section == "# Variables" && begin || !/^$/) && !/^#\s*([@%+|<^?*] := $|File is an intermediate prerequisite\.|Precious file|Implicit rule search has been done\.|automatic|recipe to execute|variable set hash-table|Load=.*%)/ && section {
	line = (length(line) == 0 ? section "\n" : "") line $0 "\n";
}
/^#  Implicit rule search has not been done\.$/ {
	implicit_not_done = NR;
}
/^#  Phony target/ {
	phony = NR;
}
/^#  Implicit\/static pattern stem:/ {
	stem = NR;
}
/^#  Last modified / {
	exists = NR;
}
section == "# Files" && /^\.[A-Z]+:/ {
	special = NR;
}
/^# (Implicit Rules|Files|Directories|Variables|Pattern-specific Variable Values)$/ {
	section = $0;
}
END {
	finish_item();
	if (sorted) { asort(lines); }
	for (j = 1; j <= i; ++j) {
		process(lines[j]);
	}
	if (length(targets_to_show) == 0) {
		print "# NOTE: Environment variables declared inside Makefiles cannot be reliably detected, so you'll need to set them manually before running the output."
	}
}
