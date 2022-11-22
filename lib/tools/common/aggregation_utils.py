import fnmatch
import os

AGGREGATION_SEARCH_ROOT_ABSOLUTE_DIRS = []
DEBOOTSTRAP_SEARCH_RELATIVE_DIRS = []
CLI_SEARCH_RELATIVE_DIRS = []
DESKTOP_ENVIRONMENTS_SEARCH_RELATIVE_DIRS = []
DESKTOP_APPGROUPS_SEARCH_RELATIVE_DIRS = []
SELECTED_CONFIGURATION = None
DESKTOP_APPGROUPS_SELECTED = []
SRC = None


def calculate_potential_paths(root_dirs, relative_dirs, sub_dirs, artifact_file, initial_paths=None):
	if initial_paths is None:
		potential_paths = {"paths": []}
	else:
		potential_paths = initial_paths
	for root_dir in root_dirs:
		for rel_dir in relative_dirs:
			for sub_dir in sub_dirs:
				looked_for_file = f"{root_dir}/{rel_dir}/{sub_dir}/{artifact_file}"
				# simplify the path, removing any /./ or /../
				potential_paths["paths"].append(os.path.normpath(looked_for_file))
	# print(f"DEBUG Potential paths: {potential_paths['paths']}")
	return potential_paths


def process_common_path_for_potentials(potential_paths):
	# find the common prefix across potential_paths, and remove it from all paths.
	potential_paths["common_path"] = SRC + "/"  # os.path.commonprefix(potential_paths["paths"])
	potential_paths["paths"] = [path[len(potential_paths["common_path"]):] for path in potential_paths["paths"]]
	return potential_paths


def aggregate_packages_from_potential(potential_paths):
	aggregation_results = {}  # {"potential_paths": potential_paths}
	for path in potential_paths["paths"]:
		full_path = potential_paths["common_path"] + path
		if not os.path.isfile(full_path):
			# print(f"Skipping {path}, not a file")
			continue

		# Resolve the real path of the file, eliminating symlinks; remove the common prefix again.
		resolved_path = os.path.realpath(full_path)[len(potential_paths["common_path"]):]
		# the path in the debugging information is either just the path, or the symlink indication.
		symlink_to = None if resolved_path == path else resolved_path
		# print(f"Reading {path}")
		with open(full_path, "r") as f:
			line_counter = 0
			for line in f:
				line_counter += 1
				line = line.strip()
				if line == "" or line.startswith("#"):
					continue
				if line not in aggregation_results:
					aggregation_results[line] = {"content": line, "refs": []}
				aggregation_results[line]["refs"].append(
					{"path": path, "line": line_counter, "symlink_to": symlink_to})
	return aggregation_results


def aggregate_simple_contents_potential(potential_paths):
	aggregation_results = {}  # {"potential_paths": potential_paths}
	for path in potential_paths["paths"]:
		full_path = potential_paths["common_path"] + path
		if not os.path.isfile(full_path):
			continue

		# Resolve the real path of the file, eliminating symlinks; remove the common prefix again.
		resolved_path = os.path.realpath(full_path)[len(potential_paths["common_path"]):]
		# the path in the debugging information is either just the path, or the symlink indication.
		symlink_to = None if resolved_path == path else resolved_path

		# Read the full contents of the file full_path as a string
		with open(full_path, "r") as f:
			contents = f.read()
		aggregation_results[path] = {"contents": contents, "refs": []}
		aggregation_results[path]["refs"].append({"path": path, "symlink_to": symlink_to})
	return aggregation_results


def find_files_in_directory(directory, glob_pattern):
	files = []
	for root, dir_names, filenames in os.walk(directory):
		for filename in fnmatch.filter(filenames, glob_pattern):
			files.append(os.path.join(root, filename))
	return files


def aggregate_apt_sources(potential_paths):
	aggregation_results = {}  # {"potential_paths": potential_paths}
	for path in potential_paths["paths"]:
		full_path = potential_paths["common_path"] + path
		if not os.path.isdir(full_path):
			continue
		# Resolve the real path of the file, eliminating symlinks; remove the common prefix again.
		resolved_path = os.path.realpath(full_path)[len(potential_paths["common_path"]):]
		# the path in the debugging information is either just the path, or the symlink indication.
		symlink_to = None if resolved_path == path else resolved_path

		# find *.source in the directory
		files = find_files_in_directory(full_path, "*.source")
		for full_filename in files:
			source_name = os.path.basename(full_filename)[:-7]
			base_path = os.path.relpath(full_filename[:-len(".source")], SRC)
			if source_name not in aggregation_results:
				aggregation_results[source_name] = {"content": base_path, "refs": []}
			aggregation_results[source_name]["refs"].append({"path": path, "symlink_to": symlink_to})
	return aggregation_results


def remove_common_path_from_refs(merged):
	all_paths = []
	for item in merged:
		for ref in merged[item]["refs"]:
			if ref["path"].startswith("/"):
				all_paths.append(ref["path"])
	common_path = os.path.commonprefix(all_paths)
	for item in merged:
		for ref in merged[item]["refs"]:
			if ref["path"].startswith("/"):
				# remove the prefix
				ref["path"] = ref["path"][len(common_path):]
	return merged


# Let's produce a list from the environment variables, complete with the references.
def parse_env_for_list(env_name, fixed_ref=None):
	env_list = parse_env_for_tokens(env_name)
	if fixed_ref is None:
		refs = parse_env_for_tokens(env_name + "_REFS")
		# Sanity check: the number of refs should be the same as the number of items in the list.
		if len(env_list) != len(refs):
			raise Exception(f"Expected {len(env_list)} refs for {env_name}, got {len(refs)}")
		# Let's parse the refs; they are in the form of "function:path:line"
		parsed_refs = []
		for ref in refs:
			split = ref.split(":")
			# sanity check, make sure we have 3 parts
			if len(split) != 3:
				raise Exception(f"Expected 3 parts in ref {ref}, got {len(split)}")
			parsed_refs.append({"function": split[0], "path": split[1], "line": split[2]})
	else:
		parsed_refs = [fixed_ref] * len(env_list)
	# Now create a dict; duplicates should be eliminated, and their refs merged.
	merged = {}
	for i in range(len(env_list)):
		item = env_list[i]
		if item in merged:
			merged[item]["refs"].append(parsed_refs[i])
		else:
			merged[item] = {"content": item, "refs": [parsed_refs[i]]}
	return remove_common_path_from_refs(merged)


def merge_lists(base, extra, optype="add"):
	merged = {}
	for item in base:
		merged[item] = base[item]
		if "status" not in merged[item]:
			merged[item]["status"] = "added"
		# loop over the refs, and mark them as "initial"
		for ref in merged[item]["refs"]:
			# if the key 'status' is not present, add it
			if "operation" not in ref:
				ref["operation"] = "initial"
	for item in extra:
		for ref in extra[item]["refs"]:
			# if the key 'status' is not present, add it
			if "operation" not in ref:
				ref["operation"] = optype
		if item in merged:
			resulting = base[item]
			resulting["refs"] += extra[item]["refs"]
			merged[item] = resulting
		else:
			merged[item] = extra[item]
		merged[item]["status"] = optype
	return merged


def aggregate_all_debootstrap(artifact, aggregation_function=aggregate_packages_from_potential):
	potential_paths = calculate_potential_paths(
		AGGREGATION_SEARCH_ROOT_ABSOLUTE_DIRS, DEBOOTSTRAP_SEARCH_RELATIVE_DIRS,
		[".", f"config_{SELECTED_CONFIGURATION}"], artifact)
	return aggregation_function(process_common_path_for_potentials(potential_paths))


def aggregate_all_cli(artifact, aggregation_function=aggregate_packages_from_potential):
	potential_paths = calculate_potential_paths(
		AGGREGATION_SEARCH_ROOT_ABSOLUTE_DIRS, CLI_SEARCH_RELATIVE_DIRS,
		[".", f"config_{SELECTED_CONFIGURATION}"], artifact)
	return aggregation_function(process_common_path_for_potentials(potential_paths))


def aggregate_all_desktop(artifact, aggregation_function=aggregate_packages_from_potential):
	potential_paths = calculate_potential_paths(
		AGGREGATION_SEARCH_ROOT_ABSOLUTE_DIRS, DESKTOP_ENVIRONMENTS_SEARCH_RELATIVE_DIRS, ["."], artifact)
	potential_paths = calculate_potential_paths(
		AGGREGATION_SEARCH_ROOT_ABSOLUTE_DIRS, DESKTOP_APPGROUPS_SEARCH_RELATIVE_DIRS,
		DESKTOP_APPGROUPS_SELECTED, artifact, potential_paths)
	return aggregation_function(process_common_path_for_potentials(potential_paths))


def parse_env_for_tokens(env_name):
	result = []
	# Read the environment; if None, return an empty list.
	val = os.environ.get(env_name, None)
	if val is None:
		return result
	# tokenize val; split by whitespace, line breaks, commas, and semicolons.
	# trim whitespace from tokens.
	return [token for token in [token.strip() for token in (val.split())] if token != ""]


def get_from_env(env_name):
	value = os.environ.get(env_name, None)
	if value is not None:
		value = value.strip()
	return value


def get_from_env_or_bomb(env_name):
	value = get_from_env(env_name)
	if value is None:
		raise Exception(f"{env_name} environment var not set")
	if value == "":
		raise Exception(f"{env_name} environment var is empty")
	return value


def yes_or_no_or_bomb(value):
	if value == "yes":
		return True
	if value == "no":
		return False
	raise Exception(f"Expected yes or no, got {value}")


def join_refs_for_bash_single_string(refs):
	single_line_refs = []
	for ref in refs:
		if "operation" in ref and "line" in ref:
			one_line = ref["operation"] + ":" + ref["path"] + ":" + str(ref["line"])
		else:
			one_line = ref["path"]
		if "symlink_to" in ref:
			if ref["symlink_to"] is not None:
				one_line += ":symlink->" + ref["symlink_to"]
		single_line_refs.append(one_line)
	return " ".join(single_line_refs)


def prepare_bash_output_array_for_list(output_array_name, merged_list, extra_dict_function=None):
	values_list = []
	explain_dict = {}
	extra_dict = {}
	for key in merged_list:
		value = merged_list[key]
		# print(f"key: {key}, value: {value}")
		refs = value["refs"]
		# join the refs with a comma
		refs_str = join_refs_for_bash_single_string(refs)
		explain_dict[key] = refs_str
		if value["status"] != "remove":
			values_list.append(key)
			if extra_dict_function is not None:
				extra_dict[key] = extra_dict_function(value["content"])

	# prepare the values as a bash array definition.
	# escape each value with double quotes, and join them with a space.
	values_list_bash = "\n".join([f"\t'{value}'" for value in values_list])
	actual_var = f"declare -r -g -a {output_array_name}=(\n{values_list_bash}\n)\n"

	# Some utilities (like debootstrap) want a list that is comma separated.
	# Since that subject to infernal life in bash, let's do it here.
	values_list_comma = ",".join(values_list)
	comma_var = f"declare -r -g -a {output_array_name}_COMMA='{values_list_comma}'\n"

	explain_list_bash = "\n".join([f"\t['{value}']='{explain_dict[value]}'" for value in explain_dict.keys()])
	explain_var = f"declare -r -g -A {output_array_name}_EXPLAIN=(\n{explain_list_bash}\n)\n"

	# @TODO also an array with all the elements in explain; so we can do a for loop over it.
	extra_dict_decl = ""
	if len(extra_dict) > 0:
		extra_list_bash = "\n".join([f"\t['{value}']='{extra_dict[value]}'" for value in extra_dict.keys()])
		extra_dict_decl = f"declare -r -g -A {output_array_name}_DICT=(\n{extra_list_bash}\n)\n"

	final_value = actual_var + "\n" + extra_dict_decl + "\n" + comma_var + "\n" + explain_var
	# print(final_value)
	return final_value


def prepare_bash_output_single_string(output_array_name, merged_list):
	values_list = []
	for key in merged_list:
		value = merged_list[key]
		refs_str = join_refs_for_bash_single_string(value["refs"])
		# print(f"key: {key}, value: {value}")
		values_list.append("### START Source: " + refs_str + "\n" + value[
			"contents"] + "\n" + "### END Source: " + refs_str + "\n\n")

	values_list_bash = "\n".join(values_list)
	return f"declare -g {output_array_name}" + "\n" + (
		f"{output_array_name}=\"$(cat <<-'EOD_{output_array_name}_EOD'\n" +
		f"{values_list_bash}\nEOD_{output_array_name}_EOD\n)\"\n" + "\n"
	) + f"declare -r -g {output_array_name}" + "\n"


def encode_source_base_path_extra(contents_dict):
	return contents_dict
