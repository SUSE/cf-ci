#!/usr/bin/env python

# Script to extract working versions of minibroker database charts from helm stable repo's index.yaml.
# Make sure the ruamel.yaml and requests is installed: `pip install ruamel.yaml/requests`.
# 
# Usage:
# 1. Update the versions.yaml with the minibroker DB versions known to be working with current CAP release.
# 2. Run `python extractor.py <path/to/versions.yaml> <path/to/output/index.yaml>`
#

import requests
from sys import argv
from ruamel.yaml import YAML

HELM_REPO_URL="https://kubernetes-charts.storage.googleapis.com/index.yaml"

def create_key(arg_list):
    """
    Method to create key from passed args
    """
    return "%".join(arg_list)

def process_needles():
    """
    Method to load and process known working versions in versions.yaml.
    """
    try:
        with open(argv[1], 'r') as stream:
            yaml = YAML(typ='safe')
            return yaml.load(stream)
    except yaml.YAMLError as exc:
        print(exc)

def process_haystack(databases):
    """
    Method to load and process helm stable repo index.yaml.
    """
    req = requests.get(HELM_REPO_URL)
    yaml = YAML()
    data = yaml.load(req.content)
    haystack = {}
    
    for db in databases:
        for item in data["entries"][db]:
            if "appVersion" in item and "version" in item:
                key = create_key([db, item["appVersion"], item["version"]])
                haystack[key] = item

    return haystack

def dump_yaml(data):
    """
    Method to dump output index.yaml file.
    """
    with open(argv[2], 'w') as outfile:
        yaml = YAML()
        yaml.dump(data, outfile)

def main():
    if len(argv) < 3:
        print("Please provide correct arguments...")
        print("Usage: python extractor.py <path/to/versions.yaml> <path/to/output/index.yaml>")
    else:    
        needles = process_needles()
        databases = needles.keys()
        haystack = process_haystack(databases)
        output = {}
        for db in databases:
            for item in needles[db]:
                needle = create_key([db,item["appVersion"],item["version"]])
                # Check if provided version exists in helm stable repo.
                if needle in haystack:
                    if db not in output:
                        output[db] = [haystack[needle]]
                    else:
                        output[db].append(haystack[needle])

        data = {"apiVersion": "v1", "entries": output}
        dump_yaml(data)

if __name__ == "__main__":
    main()
