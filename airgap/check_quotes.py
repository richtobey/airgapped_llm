import sys

def check_quotes(filename):
    with open(filename, 'r') as f:
        lines = f.readlines()

    in_double_quote = False
    in_single_quote = False
    
    for i, line in enumerate(lines):
        j = 0
        while j < len(line):
            char = line[j]
            
            if char == "'" and not in_double_quote:
                in_single_quote = not in_single_quote
            elif char == '"' and not in_single_quote:
                # Check for escaped quote
                if j > 0 and line[j-1] == '\\':
                    pass
                else:
                    in_double_quote = not in_double_quote
            
            j += 1
            
        if in_double_quote:
            print(f"Line {i+1} ends inside double quote: {line.strip()}")
        if in_single_quote:
            # Single quotes can span lines in bash
            pass

check_quotes("get_bundle.sh")
