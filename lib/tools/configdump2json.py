import json
import sys

from common.bash_declare_parser import BashDeclareParser

mode = sys.argv[1]

parser = BashDeclareParser()

if mode == "--args":
	# loop over argv, parse one by one
	everything = {}
	for arg in sys.argv[2:]:
		parsed = parser.parse_one(arg)
		everything.update(parsed)
	# print(json.dumps(everything, indent=4))  # multiline, indented
	print(json.dumps(everything, separators=(',', ':')))  # single line, no indent, compact
else:
	raise Exception(f"Unknown mode '{mode}'")
