import os
import re
from collections import defaultdict

src_dir = r'c:\Users\emras\OneDrive\Рабочий стол\TweaksForEveryOne\src'

globals_found = defaultdict(list)
functions_found = defaultdict(list)

# Regex to catch global declarations: global var1, var2 := ...
global_re = re.compile(r'^\s*global\s+([^;]+)', re.IGNORECASE)
# Regex to catch function definitions: FuncName(...) {
func_re = re.compile(r'^\s*([a-zA-Z0-9_]+)\s*\([^\)]*\)\s*\{')

for root, _, files in os.walk(src_dir):
    for file in files:
        if file.endswith('.ahk'):
            filepath = os.path.join(root, file)
            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                for line_no, line in enumerate(f, 1):
                    # Check globals
                    m = global_re.match(line)
                    if m:
                        vars_part = m.group(1)
                        # Split by comma, but ignore commas inside parentheses/brackets (rudimentary)
                        # A simpler way: extract all identifiers before := or just all identifiers
                        # Actually, just regex for identifiers:
                        # Handle cases like global MyVar := Map(...)
                        # we can split by comma.
                        parts = vars_part.split(',')
                        for p in parts:
                            p = p.split(':=')[0].strip()
                            if p and re.match(r'^[a-zA-Z0-9_]+$', p):
                                globals_found[p.lower()].append((p, file, line_no))
                            else:
                                # further extract identifiers
                                words = re.findall(r'\b[a-zA-Z0-9_]+\b', p)
                                if words:
                                    globals_found[words[0].lower()].append((words[0], file, line_no))
                    
                    # Check functions
                    m2 = func_re.match(line)
                    if m2:
                        func_name = m2.group(1)
                        if func_name.lower() not in ['if', 'while', 'for', 'loop', 'switch', 'catch']:
                            functions_found[func_name.lower()].append((func_name, file, line_no))

print('--- Global Name Conflicts (different cases or duplicates) ---')
for lower_name, instances in globals_found.items():
    cases = set(x[0] for x in instances)
    files = set(x[1] for x in instances)
    if len(cases) > 1 or len(instances) > 1:
        # Ignore things that are just duplicate 'global var' declarations in different functions
        # Wait, if they are the exact same case, and in different files, it might be expected (just importing/accessing).
        # But if they are DIFFERENT cases, that's highly suspicious.
        if len(cases) > 1:
            print(f"CONFLICT IN CASING for '{lower_name}':")
            for inst in instances:
                print(f"  {inst[0]} in {inst[1]}:{inst[2]}")
        else:
            # Check if defined with assignment multiple times
            pass

print('\n--- Global vs Function Conflicts ---')
for lower_name, func_instances in functions_found.items():
    if lower_name in globals_found:
        print(f"NAME COLLISION (Global & Function) for '{lower_name}':")
        for inst in globals_found[lower_name]:
            print(f"  Global: {inst[0]} in {inst[1]}:{inst[2]}")
        for inst in func_instances:
            print(f"  Function: {inst[0]} in {inst[1]}:{inst[2]}")

