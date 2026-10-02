#!/usr/bin/python3
"""Deterministic, offline app-server fixture. Never contacts Codex or another service."""
import json
import pathlib
import re
import sys
import time

thread_id = None
thread_names = {}
thread_counter = 0
turn_counter = 0
turn_id = None
pending = None
pending_kind = None
thread_policies = {}
thread_turns = {}
thread_status = {}

def send(value):
    print(json.dumps(value), flush=True)

def event(method, **params):
    send({"method": method, "params": {"threadId": thread_id, **params}})

def complete(params):
    global thread_turns, thread_status
    prompt = params["input"][0]["text"]
    blocked = "BLOCKED_FIXTURE" in prompt
    if not prompt.startswith("Task: "):
        blocked = True
    if "Task: Plan fixture" in prompt:
        expected_sections = [
            "## User requirements",
            "## Architecture and data model",
            "## Basic test cases",
            "## High-level implementation details",
        ]
        positions = [prompt.find(section) for section in expected_sections]
        if "PLAN_FORMAT_SENTINEL" not in prompt or any(position < 0 for position in positions):
            blocked = True
        elif positions != sorted(positions):
            blocked = True
    if "Task: Implement fixture" in prompt and "PLAN_FORMAT_SENTINEL" in prompt:
        blocked = True
    if "Plan only" in prompt and not blocked:
        reserved = re.search(r"Reserved plan path: (to-do/[^\s`]+\.md)", prompt)
        destinations = re.findall(r"to-do/[^\s`]+\.md", prompt)
        if reserved is None or destinations.count(reserved.group(1)) < 2:
            blocked = True
        path = reserved.group(1) if reserved else ""
        destination = pathlib.Path(params["cwd"]) / path
        if "MISSING_PLAN_FIXTURE" not in prompt:
            destination.parent.mkdir(parents=True, exist_ok=True)
            content = "   \n\t" if "EMPTY_PLAN_FIXTURE" in prompt else "# Fixture plan\n\nImplement and verify the fixture.\n"
            destination.write_text(content)
    event("turn/plan/updated", plan=[{"step": "Verify the fixture", "status": "completed"}])
    text = json.dumps({"outcome": "blocked" if blocked else "completed", "summary": "Fixture is blocked" if blocked else "Fixture verified"})
    event("item/completed", item={"type": "agentMessage", "text": text, "phase": "final_answer"})
    event("turn/completed", turn={"id": turn_id, "status": "completed"})
    thread_status[params["threadId"]] = "idle"
    thread_turns[params["threadId"]] = [{
        "id": turn_id,
        "status": "completed",
        "items": [{"type": "agentMessage", "text": "Fixture verified"}],
    }]

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
            thread_turns[thread_id] = []
            thread_status[thread_id] = "idle"
        else:
            thread_id = params["threadId"]
        thread_policies[thread_id] = params.get("approvalPolicy")
        result = {"thread": {"id": thread_id}}
    elif method == "thread/read":
        if params.get("threadId") == "fixture-read-failure":
            send({"id": request_id, "error": {"code": -32000, "message": "fixture read failure"}})
            continue
        if params.get("threadId") == "fixture-slow-read":
            time.sleep(0.2)
        result = {"thread": {
            "id": params["threadId"],
            "status": {"type": thread_status.get(params["threadId"], "idle")},
            "turns": thread_turns.get(params["threadId"], []),
        }}
    elif method == "turn/start":
        if params.get("model") != "gpt-6.10-luna" or params.get("effort") != "high":
            send({"id": request_id, "error": {"code": -32602, "message": "missing or wrong turn model/effort"}})
            continue
        turn_counter += 1
        turn_id = f"fixture-turn-{turn_counter}"
        prompt = params["input"][0]["text"]
        if not prompt.startswith("Task: "):
            send({"id": request_id, "error": {"code": -32602, "message": "task title is not first in prompt"}})
            continue
        title = prompt.splitlines()[0][len("Task: "):]
        prefix = "Plan: " if "Plan only; do not implement application code." in prompt else "Code: "
        if "NAME_FAILURE_FIXTURE" not in title and thread_names.get(params["threadId"]) != prefix + title:
            send({"id": request_id, "error": {"code": -32602, "message": "thread name does not have the expected prefix and task title"}})
            continue
        if "APPROVAL_FIXTURE" in prompt or "AUTO_APPROVE_FIXTURE" in prompt or "UNSAFE_FIXTURE" in prompt or "DENY_FIXTURE" in prompt:
            expected_policy = "on-request"
        else:
            expected_policy = "never"
        if params.get("approvalPolicy") != expected_policy:
            send({"id": request_id, "error": {"code": -32602, "message": "wrong approval policy"}})
            continue
        if thread_policies.get(params["threadId"]) != expected_policy:
            send({"id": request_id, "error": {"code": -32602, "message": "thread approval policy mismatch"}})
            continue
        sandbox = params.get("sandboxPolicy", {})
        if sandbox != {"type": "workspaceWrite", "writableRoots": [params["cwd"]], "networkAccess": False}:
            send({"id": request_id, "error": {"code": -32602, "message": "sandbox was widened"}})
            continue
        send({"id": request_id, "result": {"turn": {"id": turn_id, "status": "inProgress"}}})
        event("turn/started", turn={"id": turn_id, "status": "inProgress"})
        event("item/completed", item={"type": "commandExecution", "command": "echo fixture", "aggregatedOutput": "fixture\n", "status": "completed"})
        if "APPROVAL_FIXTURE" in prompt or "AUTO_APPROVE_FIXTURE" in prompt or "UNSAFE_FIXTURE" in prompt or "DENY_FIXTURE" in prompt:
            pending = params
            pending_kind = "command"
            approval_params = {"threadId": thread_id, "turnId": turn_id, "itemId": "command-item", "command": "echo fixture", "cwd": params["cwd"], "reason": "Fixture requires approval"}
            if "UNSAFE_FIXTURE" in prompt:
                approval_params["networkApprovalContext"] = {"host": "example.invalid", "protocol": "https"}
            send({"id": "approval-command", "method": "item/commandExecution/requestApproval", "params": approval_params})
        elif "STOP_FIXTURE" not in params["input"][0]["text"] and "CLOSE_FIXTURE" not in params["input"][0]["text"]:
            complete(params)
        continue
    elif method == "turn/interrupt":
        result = {}
    elif method == "thread/name/set":
        if "NAME_FAILURE_FIXTURE" in params.get("name", ""):
            send({"id": request_id, "error": {"code": -32000, "message": "fixture name set failure"}})
            continue
        thread_names[params["threadId"]] = params["name"]
        result = {}
    elif request_id in ("approval-command", "approval-file"):
        decision = message.get("result", {}).get("decision")
        if request_id == "approval-command" and pending_kind == "command" and decision == "accept" and "AUTO_APPROVE_FIXTURE" in pending["input"][0]["text"]:
            pending_kind = "file"
            event("item/started", item={"type": "fileChange", "id": "file-item", "changes": [{"path": "fixture.txt", "diff": "+fixture"}]})
            send({"id": "approval-file", "method": "item/fileChange/requestApproval", "params": {"threadId": thread_id, "turnId": turn_id, "itemId": "file-item", "reason": "Fixture file change"}})
        elif decision == "accept":
            complete(pending)
        else:
            event("turn/completed", turn={"id": turn_id, "status": "interrupted"})
        continue
    else:
        result = {}
    if request_id is not None:
        send({"id": request_id, "result": result})
