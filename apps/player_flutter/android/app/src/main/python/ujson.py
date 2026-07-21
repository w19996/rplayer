import json


def loads(value, *args, **kwargs):
    return json.loads(value, *args, **kwargs)


def dumps(value, *args, **kwargs):
    return json.dumps(value, *args, **kwargs)
