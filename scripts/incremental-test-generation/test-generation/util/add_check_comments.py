# Adds "//UNDEFINED" or "//SUCCESS" to the Goblint checks "__goblint_check(exp);".
# Stores the file with the same name when adding "//SUCCESS".
# Stores the file with the appendix _u when adding "//UNDEFINED".
# Run with ´python3 script.py example.txt -u´ or ´python3 script.py example.txt -s´.

import argparse
import re

def add_check_comments(file_path: str, undefined_instead_of_success: bool, verbose = False):
    if verbose:
        if undefined_instead_of_success:
            print("Add \"//UNDEFINED\" to the Goblint checks __goblint_check(exp);")
        else:
            print("Add \"//SUCCESS\" to the Goblint checks __goblint_check(exp);")

    with open(file_path, 'r') as file:
        lines = file.readlines()
        modified_lines = []
        
        for line in lines:
            if '__goblint_check(' in line:
                match = re.search(r'(__goblint_check\(.*?\);)', line)
                if match:
                    modified_line = match.group(1)
                    if undefined_instead_of_success:
                        modified_line += ' //UNDEFINED'
                    else:
                        modified_line += ' //SUCCESS'
                    line = line.replace(match.group(1), modified_line)
            modified_lines.append(line)
        
        if undefined_instead_of_success:
            new_file_name = file_path.rsplit('.', 1)[0] + '_u.c'
            with open(new_file_name, 'w') as new_file:
                new_file.writelines(modified_lines)
            if verbose:
                print("Processing complete. Modified lines have been added to the new file:", new_file_name)
        else:
            with open(file_path, 'w') as file:
                file.writelines(modified_lines)
            if verbose:
                print("Processing complete. Modified lines have been added to the existing file:", file_path)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("file", help="Path to the C file")
    parser.add_argument("-u", "--undefined", action="store_true", help="Option for //UNDEFINED")
    parser.add_argument("-s", "--success", action="store_true", help="ption for //SUCCESS")
    args = parser.parse_args()

    if not (args.undefined or args.success):
        parser.error("Error: Invalid option. Provide -u for \"//UNDEFINED\" or -s for \"//SUCCESS\".")

    add_check_comments(args.file, args.undefined, True)