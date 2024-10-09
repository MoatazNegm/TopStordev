#!/usr/bin/env python3

import argparse
import re
from etcdget import etcdget

def check_name_uniqueness(name, etcd_host='10.11.11.100'):
    # Define keys for volumes and users
    search_keys = ['volumes', 'users']
    
    for key in search_keys:
        try:
            # Use etcdget to retrieve data for the specified key
            result = etcdget(etcd_host, key, '--prefix')

            # Process the results
            for entry in result:
                volume_key, volume_value = entry
                match = re.search(r'/([^/]+?)_', volume_value)
                if match:
                    extracted_name = match.group(1)
                    if extracted_name == name:
                        print(f"Invalid: The name '{name}' is already in use.")
                        return 1

        except Exception as e:
            print(f"An error occurred while retrieving or processing the data for key '{key}': {e}")
            continue
    
    print(f"Valid: The name '{name}' is available.")
    return 0

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Check if a name is unique.")
    parser.add_argument("name", type=str, help="Name to check for uniqueness.")
    parser.add_argument("--etcd-host", type=str, default='10.11.11.100', help="ETCD host IP address.")
    
    args = parser.parse_args()
    
    name_to_check = args.name
    etcd_host = args.etcd_host
    
    exit_code = check_name_uniqueness(name_to_check, etcd_host)
    exit(exit_code)
