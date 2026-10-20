"""Device-facing SSE for an agent turn (docs/architecture/agent-turn-contract.md).

Foundry streams Responses API events (`response.created`, `response.output_text.delta`,
`response.completed`; learn.microsoft.com/azure/foundry/how-to/develop/framework-hosted-agents).
The hosted agent answers with a JSON object (kind, text, ...), so raw deltas are not text for the
user. `TextExtractor` pulls the characters of the `text` field out of the partial JSON for display.
That text is display-only: `final` carries the reply the api parsed and grounded, and the device
replaces whatever it showed with it.

Events to the device: `status` {phase: warming|thinking|tool, name?}, `delta` {text},
`tool` {name, ok}, `final` {reply, tool_calls}, `error` {code, message}. Exactly one of final or
error ends the stream. No prompt, token or reply content is logged.
"""

import json
import logging
import queue
import re
import threading
from collections.abc import Callable, Iterable, Iterator
from typing import Any

from app.agents.foundry import AgentError

logger = logging.getLogger(__name__)

WARMING = "x.warming"  # synthetic: no upstream event within the warm-up wait
WARMUP_SECONDS = 3.0
_TEXT_KEY = re.compile(r'"text"\s*:\s*"')
_REPLACEMENT = "\N{REPLACEMENT CHARACTER}"
_ESCAPES = {'"': '"', "\\": "\\", "/": "/", "b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t"}


def sse(event: str, data: dict[str, Any]) -> str:
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


def parse_sse(lines: Iterable[str]) -> Iterator[dict[str, Any]]:
    """Responses API server-sent events -> the JSON object of each `data:` payload."""
    data: list[str] = []
    for line in [*lines, ""]:
        if line.startswith("data:"):
            data.append(line[5:].removeprefix(" "))
        elif line == "" and data:
            payload, data = "\n".join(data), []
            if payload == "[DONE]":
                return
            try:
                event = json.loads(payload)
            except ValueError:
                continue
            if isinstance(event, dict):
                yield event


class TextExtractor:
    """Incrementally decodes the value of the `"text"` string in a streamed JSON object.

    If the output does not start with `{` (the plain-text fallback of `parse_reply`) the deltas are
    passed through unchanged.
    """

    def __init__(self) -> None:
        self._buf = ""
        self._pos = 0
        self._mode = "seek"  # seek | string | plain | done

    def feed(self, chunk: str) -> str:
        self._buf += chunk
        if self._mode == "seek":
            head = self._buf.lstrip()
            if head and not head.startswith("{"):
                self._mode, self._pos = "plain", 0
            elif match := _TEXT_KEY.search(self._buf):
                self._mode, self._pos = "string", match.end()
        if self._mode == "plain":
            out, self._pos = self._buf[self._pos :], len(self._buf)
            return out
        if self._mode != "string":
            return ""
        out: list[str] = []
        buf = self._buf
        while self._pos < len(buf):
            char = buf[self._pos]
            if char == '"':
                self._mode = "done"
                break
            if char != "\\":
                out.append(char)
                self._pos += 1
                continue
            decoded, used = self._escape(buf, self._pos)
            if used == 0:  # incomplete: wait for more input
                break
            out.append(decoded)
            self._pos += used
        return "".join(out)

    @staticmethod
    def _escape(buf: str, pos: int) -> tuple[str, int]:
        if pos + 1 >= len(buf):
            return "", 0
        kind = buf[pos + 1]
        if kind in _ESCAPES:
            return _ESCAPES[kind], 2
        if kind != "u":
            return _REPLACEMENT, 2
        if pos + 6 > len(buf):
            return "", 0
        try:
            code = int(buf[pos + 2 : pos + 6], 16)
        except ValueError:
            return _REPLACEMENT, 2
        if 0xD800 <= code < 0xDC00:  # high surrogate: needs its low half
            rest = buf[pos + 6 : pos + 12]
            if rest in ("", "\\"):
                return "", 0  # cannot tell yet whether a low half follows
            if not rest.startswith("\\u"):
                return _REPLACEMENT, 6
            if len(rest) < 6:
                return "", 0
            try:
                low_code = int(rest[2:], 16)
            except ValueError:
                return _REPLACEMENT, 6
            if 0xDC00 <= low_code < 0xE000:
                return chr(0x10000 + ((code - 0xD800) << 10) + (low_code - 0xDC00)), 12
            return _REPLACEMENT, 6
        if 0xDC00 <= code < 0xE000:
            return _REPLACEMENT, 6  # a lone low surrogate
        return chr(code), 6


def with_warmup(upstream: Iterator[dict[str, Any]], wait: float = WARMUP_SECONDS) -> Iterator[Any]:
    """Pass events through; yield one WARMING marker if the first one takes longer than `wait`.

    Foundry may hold the connection while a hosted agent's sandbox starts. The upstream iterator
    runs on a thread so the device can be told it is a cold start instead of seeing silence.
    """
    box: queue.Queue[tuple[str, Any]] = queue.Queue()
    stop = threading.Event()

    def pump() -> None:
        try:
            for event in upstream:
                if stop.is_set():
                    break
                box.put(("event", event))
            box.put(("end", None))
        except Exception as exc:  # delivered to the consumer, which maps it to an error event
            box.put(("error", exc))
        finally:
            close = getattr(upstream, "close", None)
            if close:
                close()

    threading.Thread(target=pump, daemon=True).start()
    seen_first = warned = False
    try:
        while True:
            try:
                kind, value = box.get(timeout=None if seen_first or warned else wait)
            except queue.Empty:
                warned = True
                yield {"type": WARMING}
                continue
            seen_first = True
            if kind == "event":
                yield value
            elif kind == "error":
                raise value
            else:
                return
    finally:
        stop.set()


def turn_events(
    upstream: Iterator[dict[str, Any]],
    agent: str,
    finish: Callable[[dict[str, Any]], dict[str, Any]],
) -> Iterator[str]:
    """Translate Foundry events into device events. `finish` turns the completed response into
    the final body (record the run, parse, ground). Always ends with one `final` or `error`."""
    extractor = TextExtractor()
    thinking = False
    try:
        for event in upstream:
            kind = str(event.get("type", ""))
            item = event.get("item") if isinstance(event.get("item"), dict) else {}
            is_call = str(item.get("type", "")).endswith("_call")
            if kind == WARMING:
                yield sse("status", {"phase": "warming"})
            elif kind in ("response.created", "response.in_progress") and not thinking:
                thinking = True
                yield sse("status", {"phase": "thinking"})
            elif kind == "response.output_item.added" and is_call:
                yield sse("status", {"phase": "tool", "name": str(item.get("name", ""))})
            elif kind == "response.output_item.done" and is_call:
                ok = not item.get("error")
                yield sse("tool", {"name": str(item.get("name", "")), "ok": ok})
            elif kind == "response.output_text.delta":
                if text := extractor.feed(str(event.get("delta", ""))):
                    yield sse("delta", {"text": text})
            elif kind == "response.completed":
                response = event.get("response")
                if not isinstance(response, dict) or response.get("status") != "completed":
                    raise AgentError("agent_incomplete")
                yield sse("final", finish(response))
                return
            elif kind in ("response.failed", "response.incomplete", "error"):
                raise AgentError(kind.removeprefix("response."))
        raise AgentError("stream_ended")
    except Exception as exc:  # the stream must always end with one final or one error
        # The stable code only (never a token, prompt or reply): foundry_403, stream_ended, or the
        # exception's class name for anything unexpected (an httpx stream error, a grounding bug).
        code = exc.code if isinstance(exc, AgentError) else type(exc).__name__
        logger.warning("agent stream failed: agent=%s code=%s", agent, code)
        yield sse(
            "error", {"code": "AGENT_UNAVAILABLE", "message": "The assistant could not be reached"}
        )
