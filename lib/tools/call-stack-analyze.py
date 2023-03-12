#!/usr/bin/env python3
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
import os
import sys

import graphviz

# define an array with some functions which do callbacks; those complicate the 
# graph too much, and you don't need them in to understand the flow.
skip_functions = [
	"call_extension_method", "do_with_logging", "do_with_hooks", "do_with_ccache_statistics",
	"write_hook_point_metadata"  # this one does no callbacks, but is called a lot, and not in logging module
]
# same logic, but per-group.
skip_groups = ["logging"]


def get_group_from_filename(file):
	if file == "<extension_magic>":
		return "extension_magic"
	if file == "<START_HERE>":
		return "start_here"
	if file.startswith("lib/functions/general/extensions.sh"):
		return "extensions_infra"
	if file.startswith("extensions/"):
		return "core_extensions"
	if file.startswith("config/sources/families"):
		return "family_code"
	if file.startswith("config/"):
		return "config_code"
	if file.startswith("lib/functions/compilation/uboot.sh"):
		return "compilation-u-boot"
	if file.startswith("lib/functions/compilation/kernel-debs.sh"):
		return "compilation-kernel"
	if file.startswith("lib/functions/compilation/kernel.sh"):
		return "compilation-kernel"
	if file.startswith("lib/functions/"):
		components = file.split("/")
		# return all the components, joined by a slash, except the first two and the last
		return "/".join(components[2:-1])
	return "unknown"


def prepare_file_for_screen(file):
	# if it starts with "lib/functions/", remove that
	if file.startswith("lib/functions/"):
		return file[14:]
	return file


def cleanup_filename(filename, common_prefix):
	real_filename = filename.replace(common_prefix, "")
	if real_filename.startswith(".tmp/") and real_filename.endswith("/extension_function_definition.sh"):
		real_filename = "<extension_magic>"
	return real_filename


def eprint(*args, **kwargs):
	print(*args, file=sys.stderr, **kwargs)


def split_by_spaces(value):
	return value.split(" ")


file_handle = open("output/call-traces/calls.txt", 'r')
file_lines = file_handle.readlines()
file_handle.close()

# eprint the number of lines
eprint("Number of lines: " + str(len(file_lines)))

bare_calls = []

# loop over the lines
for line in file_lines:
	# split by "|" character
	line_parts = line.split("|", maxsplit=3)

	# Make sure we've 4 parts
	if len(line_parts) != 4:
		eprint("Error: line_parts length is not 4")
		eprint("line_parts: " + str(line_parts))
		continue

	# first element is the function name, second is the line number, third is the file name; assign each to variables
	function_names = split_by_spaces(line_parts[0])
	line_numbers = split_by_spaces(line_parts[1])
	file_names = split_by_spaces(line_parts[2])
	current_line_no = int(line_parts[3])
	# print out
	# eprint("Function names: " + str(function_names))
	# eprint("Line numbers: " + str(line_numbers))
	# eprint("File names: " + str(file_names))

	# Ok now parse the stacktrace into an array, taking bashisms into consideration.
	# The shell function ${FUNCNAME[$i]} is defined in the file ${BASH_SOURCE[$i]} and called from ${BASH_SOURCE[$i+1]}
	stack = []
	for i in range(len(function_names) - 1):
		stack.append({
			"function": function_names[i],
			"called_by_line": line_numbers[i],
			"called_by_file": file_names[i + 1]
		})

	# eprint("Stack: " + str(stack))

	# Some unwanted functions, in an array
	# unwanted_functions = ["call_extension_method", "do_with_logging"]

	# filter the stack; remove unwanted functions
	# stack = [x for x in stack if x["function"] not in unwanted_functions]

	# Add to the bare calls array.
	if len(stack) == 1:
		caller = "<START_HERE>"
	else:
		caller = (stack[1]["function"])
	bare_calls.append({
		"callee": (stack[0]["function"]),
		"caller": caller,
		"callpoint_file": (stack[0]["called_by_file"]),
		"callpoint_line": (int(stack[0]["called_by_line"])),
		"callee_return_line": current_line_no,
		"callee_return_file": file_names[0].strip(),
		"stack": stack
	})

# loop over the calls, and show the calls that have a relative path in callpoint_file.
absolute_calls = []
for call in bare_calls:
	if call["callpoint_file"].startswith("/"):
		absolute_calls.append(call)

# loop over the calls, and determine what is the common prefix for the callpoint_file, then remove it across all calls
# first, find the common prefix
common_prefix = os.path.commonpath([call["callpoint_file"] for call in absolute_calls]) + "/"
# print the common prefix
eprint("Common prefix: " + common_prefix)
# now, remove the common prefix from all callpoint_file and callee_return_file
for call in bare_calls:
	call["callpoint_file"] = cleanup_filename(call["callpoint_file"], common_prefix)
	call["callee_return_file"] = cleanup_filename(call["callee_return_file"], common_prefix)
	# loop over the stack and do the same to each
	for stack_item in call["stack"]:
		stack_item["called_by_file"] = cleanup_filename(stack_item["called_by_file"], common_prefix)

# Now create a map between function names and their callee_return_file
function_to_file = {}
for call in bare_calls:
	if call["callee"] not in function_to_file:
		function_to_file[call["callee"]] = {
			"def_file": call["callee_return_file"],
			"def_line": call["callee_return_line"],
			"group": get_group_from_filename(call["callee_return_file"])
		}

# eprint("function_to_file: " + str(function_to_file))

# Now go back to the bare_calls, and add the def_file and def_line to each stack member
for call in bare_calls:
	for stack_member in call["stack"]:
		func = stack_member["function"]
		if function_to_file.get(func) is not None:
			func2file = function_to_file[func]
			stack_member["def_file"] = func2file["def_file"]
			stack_member["def_line"] = func2file["def_line"]
			stack_member["group"] = func2file["group"]
		else:
			eprint("Error: function not found in function_to_file: " + func)
			raise Exception("Error: function not found in function_to_file: " + func)

# Now recompute the calls, dropping from the stack the unwanted groups.
calls = []
for call in bare_calls:
	# skip the whole call if the first element in the stack is in the unwanted groups
	if call["stack"][0]["group"] in skip_groups:
		continue

	# skip the whole call if the first element in the stack is in the skip_functions
	if call["stack"][0]["function"] in skip_functions:
		continue

	size_pre = len(call["stack"])
	# eprint("stack size, pre filter: {}".format(size_pre))

	# filter the stack; remove unwanted groups. why isn't this working?
	# stack = [x for x in call["stack"] if x["group"] != "logging"]

	original_stack = call["stack"]
	new_stack = []
	stack_counter = 0
	previous_stack = None
	for stack_item in call["stack"]:
		# eprint("Stack: {}".format(str(stack_item)))
		if (stack_item["group"] not in skip_groups) and (stack_item["function"] not in skip_functions):
			new_stack.append(stack_item)
		else:
			# eprint("Dropping stack item: {}".format(str(stack_item)))
			if previous_stack is not None:
				previous_stack["called_by_line"] = stack_item["called_by_line"]
				previous_stack["called_by_file"] = stack_item["called_by_file"]

		stack_counter += 1
		previous_stack = stack_item

	stack = new_stack
	call["stack"] = new_stack

	size_post = len(stack)
	# eprint("stack size, post filter: {}".format(size_post))
	# if size_pre != size_post:
	# eprint("*** stack size changed from {} to {}".format(size_pre, size_post))
	# eprint("Original stack: {}".format(str(original_stack)))
	# eprint("New stack: {}".format(str(new_stack)))

	# if the stack is empty, skip this call
	if len(stack) == 0:
		eprint("Empty stack, skipping")
		continue

	# Add to the calls array.
	if len(stack) == 1:
		caller = "<START_HERE>"
	else:
		caller = (stack[1]["function"])
	calls.append({
		"callee": (stack[0]["function"]),
		"caller": caller,
		"callpoint_file": (stack[0]["called_by_file"]),
		"callpoint_line": (int(stack[0]["called_by_line"])),
		"callee_return_line": (int(stack[0]["def_line"])),
		"callee_return_file": ((stack[0]["def_file"])),
		"callee_group": stack[0]["group"],
	})

# switch calls
bare_calls = calls

## remove all calls that have a callee in the skip_functions array
# bare_calls = [call for call in bare_calls if call["callee"] not in skip_functions]

# deduplicate the calls. @TODO: then it's not "bare" anymore; also gotta aggregate the number of calls
bare_calls = [dict(t) for t in {tuple(d.items()) for d in bare_calls}]

# print the calls
# eprint("Bare calls: " + str(bare_calls))

# process the calls, extracting callee into a dictionary of nodes
# note: the father-of-all caller is not included, of course.
nodes = {}
for call in bare_calls:
	# add the callee to the nodes dictionary
	if call["callee"] not in nodes:
		nodes[call["callee"]] = {
			"function": call["callee"],
			"definition_file": call["callee_return_file"], "definition_line": call["callee_return_line"]
		}

grouped_nodes = {}
for node in nodes:
	file = nodes[node]["definition_file"]
	group = get_group_from_filename(file)
	if group not in grouped_nodes:
		grouped_nodes[group] = []
	grouped_nodes[group].append(node)

# print the nodes
# eprint("Nodes: " + str(nodes.keys()))
# eprint("grouped_nodes: " + str(grouped_nodes))

# use the graphviz package to generate a call graph
dot = graphviz.Digraph(comment='Armbian build system call graph')

# An array of colors which we'll use as background colors for the nodes.
colors = [
	"#ff0000", "#00ff00", "#0000ff", "#ffff00", "#00ffff", "#ff00ff", "#ff8000", "#ff0080", "#0080ff", "#8000ff",
	"#008080", "#800080", "#808000", "#008000", "#800000", "#000080", "#808080"
]

# Loop over the colors, determine the foreground to match
color_pairs = []
for color in colors:
	# if the color is too dark, use white text
	if (int(color[1:3], 16) + int(color[3:5], 16) + int(color[5:7], 16)) < 400:
		color_pairs.append({"back": color, "fore": "#ffffff"})
	else:
		color_pairs.append({"back": color, "fore": "#000000"})

group_counter = 0

node_colors = {}
for node_group in grouped_nodes:
	group_counter += 1

	# cycle over a preset palette of colors
	color = color_pairs[group_counter % len(colors)]

	# with dot.subgraph(name="cluster_" + bla, graph_attr={'label': bla, 'bgcolor': color, "margin": "16"}) as sg:
	for node in grouped_nodes[node_group]:
		label = nodes[node]["function"] + "()" + "\n" + prepare_file_for_screen(
			nodes[node]["definition_file"]) + ":" + str(
			nodes[node]["definition_line"]) + "\n" + "[" + node_group + "]"
		dot.node(node, label, style="filled", fillcolor=color["back"], fontcolor=color["fore"])
		node_colors[node] = color["back"]

for call in bare_calls:
	edge_label = prepare_file_for_screen(call["callpoint_file"]) + ":" + str(call["callpoint_line"])
	edge_color = node_colors.get(call["caller"])
	if edge_color is None:
		edge_color = "black"
	dot.edge(call["caller"], call["callee"], label=edge_label, color=edge_color, fontcolor="black")

# dot = dot.unflatten(stagger=3, fanout=True, chain=15)
dot = dot.unflatten(stagger=3, fanout=True, chain=13)

dot.format = 'svg'
dot.render('output/call-traces/call-graph.dot', view=True)

dot.format = 'pdf'
dot.render('output/call-traces/call-graph.dot.exp', view=True)

dot.format = 'png'
dot.render('output/call-traces/call-graph.dot.img', view=True)

# eprint(dot.source)

eprint("Done")
