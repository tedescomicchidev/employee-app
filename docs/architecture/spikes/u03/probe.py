"""U-03 spike probe: what does Work IQ return for a calendar window?

Spike code only: not production, not imported anywhere. Run by the human in their own
account with a test user. Never prints or stores a token or any event content; the result
file holds statuses, tool names, key names, counts and salted hashes only.

  python3 -I probe.py --tenant <tenant-id> --client-id <public-client-id> [--days 7]
"""
import argparse, base64, hashlib, json, os, sys, urllib.error, urllib.request
from datetime import datetime, timedelta, timezone

MCP_URL = "https://workiq.svc.cloud.microsoft/mcp"
WORKIQ_SCOPE = "api://workiq.svc.cloud.microsoft/WorkIQAgent.Ask"
GRAPH_SCOPE = "https://graph.microsoft.com/Calendars.Read"
OUT = "/Users/Shared/handoff/u03-result.json"
SALT = os.urandom(8).hex()


def h(value):
    return hashlib.sha256((SALT + str(value)).encode()).hexdigest()[:10]


def shape(node, depth=0):
    """Key names and list lengths only, never values."""
    if depth > 4:
        return "..."
    if isinstance(node, dict):
        return {k: shape(v, depth + 1) for k, v in node.items()}
    if isinstance(node, list):
        return [f"list[{len(node)}]", shape(node[0], depth + 1)] if node else "list[0]"
    return type(node).__name__


def _err(text):
    try:
        e = json.loads(text)
        e = e.get("error", e)
        return e.get("code") if isinstance(e, dict) else str(e)[:80]
    except ValueError:
        return "non-json"


def post(token, body, session=None):
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json",
               "Accept": "application/json, text/event-stream"}
    if session:
        headers["Mcp-Session-Id"] = session
    req = urllib.request.Request(MCP_URL, json.dumps(body).encode(), headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw, status, sid = r.read().decode(), r.status, r.headers.get("Mcp-Session-Id")
    except urllib.error.HTTPError as e:
        return {"status": e.code, "error_code": _err(e.read().decode())}, None
    payload = None
    for line in raw.splitlines():  # SSE or plain JSON
        line = line[5:].strip() if line.startswith("data:") else line.strip()
        if line.startswith("{"):
            payload = json.loads(line)
    return {"status": status, "payload": payload}, sid


def rpc(token, session, method, params, rid):
    return post(token, {"jsonrpc": "2.0", "id": rid, "method": method, "params": params}, session)


def call_tool(token, session, rid, name, arguments):
    res, _ = rpc(token, session, "tools/call", {"name": name, "arguments": arguments}, rid)
    out = {"status": res["status"], "error_code": res.get("error_code")}
    p = res.get("payload") or {}
    if "error" in p:
        out["rpc_error"] = {"code": p["error"].get("code"), "message_len": len(p["error"].get("message", ""))}
    result = p.get("result") or {}
    out["isError"] = result.get("isError")
    out["content_types"] = [c.get("type") for c in result.get("content", [])]
    texts = [c.get("text", "") for c in result.get("content", []) if c.get("type") == "text"]
    out["text_chars"] = sum(len(t) for t in texts)
    parsed = None
    for t in texts:
        try:
            parsed = json.loads(t)
            break
        except ValueError:
            pass
    out["json_parseable"] = parsed is not None
    out["events"] = None
    if parsed is not None:
        out["shape"] = shape(parsed)
        events = parsed.get("value") if isinstance(parsed, dict) else parsed
        if isinstance(events, list):
            out["events"] = [h(e.get("iCalUId") or e.get("id")) for e in events if isinstance(e, dict)]
            out["has_next_link"] = isinstance(parsed, dict) and any("nextLink" in k for k in parsed)
    return out


def finish(result):
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        json.dump(result, f, indent=2)
    print(f"wrote {OUT}", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tenant", required=True)
    ap.add_argument("--client-id", required=True)
    ap.add_argument("--days", type=int, default=7)
    a = ap.parse_args()
    import msal  # pip install msal (human's environment)

    app = msal.PublicClientApplication(a.client_id, authority=f"https://login.microsoftonline.com/{a.tenant}")
    flow = app.initiate_device_flow(scopes=[WORKIQ_SCOPE])
    print(flow["message"], file=sys.stderr)
    tok = app.acquire_token_by_device_flow(flow)
    result = {"started": datetime.now(timezone.utc).isoformat(), "window_days": a.days}
    if "access_token" not in tok:
        result["token"] = {"ok": False, "error": tok.get("error"), "codes": tok.get("error_codes")}
        return finish(result)
    wiq = tok["access_token"]
    claims = json.loads(base64.urlsafe_b64decode(wiq.split(".")[1] + "=="))
    result["token"] = {"ok": True, "tid_matches": claims.get("tid") == a.tenant,
                       "scp": claims.get("scp"), "has_app_only_roles": bool(claims.get("roles"))}

    start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    end = start + timedelta(days=a.days)
    s, e = start.isoformat(), end.isoformat()

    # Ground truth: Graph calendarView, same user, same window (separate delegated token).
    gt = None
    gflow = app.initiate_device_flow(scopes=[GRAPH_SCOPE])
    print(gflow["message"], file=sys.stderr)
    gtok = app.acquire_token_by_device_flow(gflow)
    if "access_token" in gtok:
        req = urllib.request.Request(
            f"https://graph.microsoft.com/v1.0/me/calendarView?startDateTime={s}&endDateTime={e}&$top=100&$select=iCalUId",
            headers={"Authorization": f"Bearer {gtok['access_token']}"})
        with urllib.request.urlopen(req, timeout=60) as r:
            gt = [h(x["iCalUId"]) for x in json.load(r)["value"]]
    result["graph_ground_truth"] = {"count": None if gt is None else len(gt)}

    init, sid = rpc(wiq, None, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                    "clientInfo": {"name": "u03-probe", "version": "0"}}, 1)
    result["initialize"] = {"status": init["status"], "error_code": init.get("error_code")}
    if init["status"] != 200:
        return finish(result)
    post(wiq, {"jsonrpc": "2.0", "method": "notifications/initialized"}, sid)
    tl, _ = rpc(wiq, sid, "tools/list", {}, 2)
    tools = ((tl.get("payload") or {}).get("result") or {}).get("tools", [])
    result["tools"] = [{"name": t["name"], "input_keys": sorted((t.get("inputSchema") or {}).get("properties", {}))}
                       for t in tools]

    # Argument names are a guess; tools/list above is the source of truth. Adjust after reading it.
    variants = {
        "fetch_events_plain": {"path": "/me/events"},
        "fetch_calendarView_path": {"path": f"/me/calendarView?startDateTime={s}&endDateTime={e}"},
        "fetch_events_filter": {"path": f"/me/events?$filter=start/dateTime ge '{s}' and end/dateTime le '{e}'&$top=100"},
    }
    result["fetch"] = {}
    for i, (name, args) in enumerate(variants.items(), start=10):
        r = call_tool(wiq, sid, i, "fetch", args)
        if gt is not None and r["events"] is not None:
            got = set(r["events"])
            r["vs_graph"] = {"missing": len(set(gt) - got), "extra": len(got - set(gt)),
                             "duplicates": len(r["events"]) - len(got)}
        result["fetch"][name] = r
    ask = call_tool(wiq, sid, 20, "ask", {"question": f"List every calendar event between {s} and {e}."})
    ask.pop("events", None)
    result["ask_contrast"] = ask
    finish(result)


if __name__ == "__main__":
    main()
