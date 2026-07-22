import json
import os
import base64
import sys
import traceback
from urllib.parse import urljoin

ROOT = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(ROOT, "python_lib")
sys.path.insert(0, LIB)

import app


def _dep_url(base_url, api):
    dep = api if api.endswith(".py") else api + ".py"
    return urljoin(base_url, dep)


def _load_spider(api, key, ext, cache_dir, config_json):
    os.makedirs(cache_dir, exist_ok=True)
    if config_json:
        try:
            for site in json.loads(config_json).get("sites", []):
                site_key = site.get("api") or ""
                site_ext = site.get("ext") or ""
                if site_key and site_ext:
                    app.gParam["SpiderPath"][site_key] = site_ext
        except Exception:
            pass
    path = app.downloadPlugin(cache_dir + os.sep, api)
    spider = app.loadFromDisk(path)
    spider.siteKey = key
    for dep in app.getDependence(spider):
        dep_path = app.downloadPlugin(cache_dir + os.sep, _dep_url(api, dep))
        app.registerPluginAlias(dep, dep_path)
    app.init(spider, ext or "")
    return spider


def _call(spider, action, args):
    if action == "home":
        return app.homeContent(spider, True)
    if action == "category":
        return app.categoryContent(
            spider,
            str(args.get("typeId", "")),
            str(args.get("page", "1")),
            True,
            "{}",
        )
    if action == "detail":
        return app.detailContent(spider, json.dumps([str(args.get("id", ""))]))
    if action == "search":
        return app.searchContent(spider, str(args.get("keyword", "")), False)
    if action == "player":
        return app.playerContent(
            spider,
            str(args.get("flag", "")),
            str(args.get("id", "")),
            "[]",
        )
    if action == "action":
        method = getattr(spider, "action", None)
        value = method(str(args.get("value", ""))) if callable(method) else None
        return json.dumps(value or {}, ensure_ascii=False)
    if action == "proxy":
        result = app.localProxy(spider, json.dumps(args, ensure_ascii=False))
        return json.dumps(_proxy_result(result), ensure_ascii=False)
    raise ValueError("unknown action: " + action)


def _proxy_result(result):
    if result is None:
        return []
    values = list(result)
    if len(values) < 3:
        return values
    body = values[2]
    if isinstance(body, bytes):
        values[2] = base64.b64encode(body).decode("ascii")
        values.append({"buffer": 2})
    elif hasattr(body, "read"):
        values[2] = base64.b64encode(body.read()).decode("ascii")
        values.append({"buffer": 2})
    return values


def main():
    request = json.loads(sys.stdin.read())
    spider = _load_spider(
        request.get("api", ""),
        request.get("key", ""),
        request.get("ext", ""),
        request.get("cacheDir", os.path.join(ROOT, "cache")),
        request.get("configJson", ""),
    )
    result = _call(spider, request.get("action", ""), request.get("args", {}))
    print(json.dumps({"ok": True, "result": result}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print(json.dumps({"ok": False, "error": traceback.format_exc()}, ensure_ascii=False))
        sys.exit(1)
