#!/usr/bin/env python3
import json
import sys

from opensearchpy import OpenSearch  # pip install opensearch-py


def eprint(*args, **kwargs):
	print(*args, file=sys.stderr, **kwargs)


# info = get_info_for_one_board(board, all_params)
print(json.dumps({}, indent=4, sort_keys=True))

eprint("Hello")

# Read JSON from stdin
# - should be array of objects
# - loop over array and index each obj into OS in to the passed index
# read_from_stdin = sys.stdin.read()

json_object = json.load(sys.stdin)

eprint("Loaded {} objects from stdin...".format(len(json_object)))

host = '192.168.66.55'
port = 31920

# Create the OpenSearch client.
client = OpenSearch(hosts=[{'host': host, 'port': port}], http_compress=False, use_ssl=False)

# Create an index with non-default settings.
index_name = 'board-vars-build'
index_body = {'settings': {'index': {'number_of_shards': 1, 'number_of_replicas': 0}}}

# Delete the index; remove old data.
try:
	response = client.indices.delete(index=index_name)
	print('\nDeleting index:')
	print(response)
except:
	eprint("Failed to delete index {}".format(index_name))

response = client.indices.create(index_name, body=index_body)
print('\nCreating index:')
print(response)

for obj in json_object:
	# print(obj)
	response = client.index(index=index_name, body=obj, refresh=True)
	print('\nAdding document:')
	print(response)
