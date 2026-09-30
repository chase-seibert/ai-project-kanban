#!/usr/bin/python3
"""Deterministic, offline app-server fixture. Never contacts Codex or another service."""
import json
import pathlib
import re
import sys

thread_id = None
thread_counter = 0
turn_counter = 0
turn_id = None
pending = None

def send(value):
    print(json.dumps(value), flush=True)

def event(method, **params):
    send({"method": method, "params": {"threadId": thread_id, **params}})

def complete(params):
    prompt = params["input"][0]["text"]
    blocked = "BLOCKED_FIXTURE" in prompt
    if "Plan only" in prompt and not blocked:
        path = re.search(r"to-do/[a-f0-9-]+\.md", prompt).group()
        destination = pathlib.Path(params["cwd"]) / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text("# Fixture plan\n\nImplement and verify the fixture.\n")
    event("turn/plan/updated", plan=[{"step": "Verify the fixture", "status": "completed"}])
    text = json.dumps({"outcome": "blocked" if blocked else "completed", "summary": "Fixture is blocked" if blocked else "Fixture verified"})
    event("item/completed", item={"type": "agentMessage", "text": text, "phase": "final_answer"})
    event("turn/completed", turn={"id": turn_id, "status": "completed"})

for line in sys.stdin:
    message = json.loads(line)
    method = message.get("method")
    params = message.get("params", {})
    request_id = message.get("id")
    if method == "initialized":
        continue
    if method == "initialize":
        result = {"userAgent": "StageChase fixture"}
    elif method == "account/read":
        result = {"account": {"type": "apiKey"}, "requiresOpenaiAuth": True}
    elif method == "model/list":
        if params.get("cursor") is None:
            result = {
                "data": [{"id": "gpt-6.9-luna", "displayName": "GPT-6.9 Luna", "hidden": False,
                          "supportedReasoningEfforts": [{"reasoningEffort": "high"}]}],
                "nextCursor": "models-2",
            }
        else:
            result = {
                "data": [
                    {"id": "gpt-6.10-luna", "displayName": "GPT-6.10 Luna", "hidden": False,
                     "supportedReasoningEfforts": [{"reasoningEffort": "high"}]},
                    {"id": "gpt-7-luna-preview", "displayName": "GPT-7 Luna Preview", "hidden": False,
                     "supportedReasoningEfforts": [{"reasoningEffort": "high"}]},
                ],
                "nextCursor": None,
            }
    elif method in ("thread/start", "thread/resume"):
        if params.get("model") != "gpt-6.10-luna":
            send({"id": request_id, "error": {"code": -32602, "message": "missing or wrong thread model"}})
            continue
        if method == "thread/start":
            thread_counter += 1
            thread_id = f"fixture-thread-{thread_counter}"
        else:
            thread_id = params["threadId"]
        result = {"thread": {"id": thread_id}}
    elif method == "turn/start":
        if params.get("model") != "gpt-6.10-luna" or params.get("effort") != "high":
            send({"id": request_id, "error": {"code": -32602, "message": "missing or wrong turn model/effort"}})
            continue
        turn_counter += 1
        turn_id = f"fixture-turn-{turn_counter}"
        send({"id": request_id, "result": {"turn": {"id": turn_id, "status": "inProgress"}}})
        event("turn/started", turn={"id": turn_id, "status": "inProgress"})
        event("item/completed", item={"type": "commandExecution", "command": "echo fixture", "aggregatedOutput": "fixture\n", "status": "completed"})
        if "APPROVAL_FIXTURE" in params["input"][0]["text"]:
            pending = params
            send({"id": "approval-1", "method": "item/commandExecution/requestApproval", "params": {"threadId": thread_id, "command": "echo fixture", "cwd": params["cwd"], "reason": "Fixture requires approval"}})
        elif "STOP_FIXTURE" not in params["input"][0]["text"] and "CLOSE_FIXTURE" not in params["input"][0]["text"]:
            complete(params)
        continue
    elif method == "turn/interrupt":
        result = {}
    elif request_id == "approval-1":
        if message.get("result", {}).get("decision") == "accept":
            complete(pending)
        else:
            event("turn/completed", turn={"id": turn_id, "status": "interrupted"})
        continue
    else:
        result = {}
    if request_id is not None:
        send({"id": request_id, "result": result})
