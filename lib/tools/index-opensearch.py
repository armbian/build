#!/usr/bin/env python3
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
import json
import sys

from opensearchpy import OpenSearch  # pip3 install opensearch-py


def eprint(*args, **kwargs):
	print(*args, file=sys.stderr, **kwargs)


# Read JSON from stdin
# - should be an array of objects
# - loop over array and index each obj into OS in to the passed index
# read_from_stdin = sys.stdin.read()

json_object = json.load(sys.stdin)

eprint("Loaded {} objects from stdin...".format(len(json_object)))

host = '127.0.0.1'
port = 9200

# Create the OpenSearch client.
client = OpenSearch(hosts=[{'host': host, 'port': port}], http_compress=False, use_ssl=False)

# Create an index with non-default settings.
index_name = 'board-vars-build'
index_body = {'settings': {'index': {'number_of_shards': 1, 'number_of_replicas': 0}}}

# Delete the index; remove old data.
try:
	delete_response = client.indices.delete(index=index_name)
	eprint('\nDeleting index...')
# print(delete_response)
except:
	eprint("Failed to delete index {}".format(index_name))

eprint('\nCreating index...')
response_create = client.indices.create(index_name, body=index_body)
# print(response_create)

for obj in json_object:
	# print(obj)
	response = client.index(index=index_name, body=obj)

eprint("\nRefreshing index...")
client.indices.refresh(index=index_name)

eprint("\nDone.")
