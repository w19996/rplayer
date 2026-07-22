import re


def jsonpath(data, expr):
    tokens = _tokens(expr)
    if not tokens:
        return False
    values = [data]
    for kind, value in tokens:
        next_values = []
        for item in values:
            if kind == "field":
                if isinstance(item, dict) and value in item:
                    next_values.append(item[value])
            elif kind == "recursive":
                next_values.extend(_recursive_field(item, value))
            elif kind == "index":
                if isinstance(item, list) and -len(item) <= value < len(item):
                    next_values.append(item[value])
            elif kind == "wildcard":
                if isinstance(item, dict):
                    next_values.extend(item.values())
                elif isinstance(item, list):
                    next_values.extend(item)
        values = next_values
        if not values:
            return False
    return values


def _recursive_field(item, name):
    found = []
    if isinstance(item, dict):
        if name in item:
            found.append(item[name])
        for value in item.values():
            found.extend(_recursive_field(value, name))
    elif isinstance(item, list):
        for value in item:
            found.extend(_recursive_field(value, name))
    return found


def _tokens(expr):
    if not isinstance(expr, str):
        return []
    value = expr.strip()
    if not value.startswith("$"):
        return []
    tokens = []
    index = 1
    while index < len(value):
        if value.startswith("..", index):
            index += 2
            match = re.match(r"[A-Za-z0-9_\-]+", value[index:])
            if not match:
                return []
            tokens.append(("recursive", match.group(0)))
            index += len(match.group(0))
        elif value[index] == ".":
            index += 1
            match = re.match(r"[A-Za-z0-9_\-]+", value[index:])
            if not match:
                return []
            tokens.append(("field", match.group(0)))
            index += len(match.group(0))
        elif value[index] == "[":
            end = value.find("]", index)
            if end < 0:
                return []
            part = value[index + 1:end].strip()
            if part == "*":
                tokens.append(("wildcard", None))
            elif (part.startswith("'") and part.endswith("'")) or (
                part.startswith('"') and part.endswith('"')
            ):
                tokens.append(("field", part[1:-1]))
            else:
                try:
                    tokens.append(("index", int(part)))
                except ValueError:
                    return []
            index = end + 1
        else:
            return []
    return tokens
