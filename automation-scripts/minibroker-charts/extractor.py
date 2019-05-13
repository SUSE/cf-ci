#!/usr/bin/env python

# Script to extract working versions of minibroker database charts from helm stable repo's index.yaml.
# Make sure the YAML parsing lib is installed: `pip install ruamel.yaml`.
# 
# Usage:
# 1. Update the versions.yaml with the minibroker DB versions known to be working with current CAP release.
# 2. Run `python extractor.py`

import os
from ruamel.yaml import YAML

os.system("curl -s https://kubernetes-charts.storage.googleapis.com/index.yaml > helm_stable_index.yaml")

def read_yaml(file):
    try:
        with open(file, 'r') as stream:
            yaml = YAML()
            return yaml.load(stream)
    except yaml.YAMLError as exc:
        print(exc)

all_versions = read_yaml("helm_stable_index.yaml")

def dump_yaml(data):
    with open('index.yaml', 'w') as outfile:
        yaml = YAML()
        data = {"apiVersion": all_versions["apiVersion"], "entries": data}
        yaml.dump(data, outfile)

def exists(db_working_versions, db_version):
    for dwv in db_working_versions:
        if "version" in db_version and "appVersion" in db_version:
            if dwv["appVersion"] == db_version["appVersion"] \
                and dwv["version"] == db_version["version"]:
                    return True

def main():
    entries = {}
    working_versions = read_yaml("versions.yaml")

    for db in working_versions:
        temp_list = []
        db_working_versions = working_versions[db]
        for db_version in all_versions["entries"][db]:
            if exists(db_working_versions, db_version):
                temp_list.append(db_version)
        entries[db] = temp_list
    
    dump_yaml(entries)

if __name__ == "__main__":
    main()
    