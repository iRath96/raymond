def flat_matrix(matrix):
    return [ x for row in matrix for x in row ]


def find_unique_name(used: set[str], name: str):
    unique_name = name
    index = 0

    while unique_name in used:
        unique_name = f"{name}.{index:03d}"
        index += 1
    
    return unique_name