#!/usr/bin/env python3
"""Build and validate GitHub PR review payloads without hand-escaped Markdown."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


VALID_EVENTS = {"APPROVE", "COMMENT", "REQUEST_CHANGES"}


def _read_text(path: str | Path) -> str:
    return Path(path).read_text(encoding="utf-8")


def _reject_literal_newlines(label: str, text: str) -> None:
    if "\\n" in text:
        raise ValueError(
            f"{label} contains literal '\\\\n'. Use real Markdown line breaks, "
            "not double-escaped newline sequences."
        )


def _load_comments(path: str | None) -> list[dict[str, Any]]:
    if not path:
        return []
    comments_path = Path(path)
    comments = json.loads(comments_path.read_text(encoding="utf-8"))
    if not isinstance(comments, list):
        raise ValueError("comments file must contain a JSON array")

    out: list[dict[str, Any]] = []
    for index, raw in enumerate(comments, start=1):
        if not isinstance(raw, dict):
            raise ValueError(f"comment {index} must be a JSON object")
        comment = dict(raw)
        body_file = comment.pop("body_file", None)
        if body_file:
            body_path = Path(body_file)
            if not body_path.is_absolute():
                body_path = comments_path.parent / body_path
            comment["body"] = body_path.read_text(encoding="utf-8")
        body = comment.get("body")
        if not isinstance(body, str) or not body.strip():
            raise ValueError(f"comment {index} must include non-empty body or body_file")
        _reject_literal_newlines(f"comment {index} body", body)
        out.append(comment)
    return out


def _validate_payload(payload: dict[str, Any]) -> None:
    event = payload.get("event")
    if event not in VALID_EVENTS:
        raise ValueError(f"event must be one of {sorted(VALID_EVENTS)}, got {event!r}")
    body = payload.get("body")
    if not isinstance(body, str) or not body.strip():
        raise ValueError("body must be a non-empty string")
    _reject_literal_newlines("review body", body)
    comments = payload.get("comments", [])
    if not isinstance(comments, list):
        raise ValueError("comments must be a JSON array")
    for index, comment in enumerate(comments, start=1):
        if not isinstance(comment, dict):
            raise ValueError(f"comment {index} must be a JSON object")
        comment_body = comment.get("body")
        if not isinstance(comment_body, str) or not comment_body.strip():
            raise ValueError(f"comment {index} must include non-empty body")
        _reject_literal_newlines(f"comment {index} body", comment_body)


def build(args: argparse.Namespace) -> None:
    body = _read_text(args.body_file)
    _reject_literal_newlines("review body", body)
    payload: dict[str, Any] = {
        "commit_id": args.commit_id,
        "event": args.event,
        "body": body,
        "comments": _load_comments(args.comments_file),
    }
    _validate_payload(payload)
    Path(args.output).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def check(args: argparse.Namespace) -> None:
    payload = json.loads(Path(args.payload).read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("payload must be a JSON object")
    _validate_payload(payload)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    build_parser = subparsers.add_parser("build", help="build a review payload")
    build_parser.add_argument("--commit-id", required=True)
    build_parser.add_argument("--event", required=True, choices=sorted(VALID_EVENTS))
    build_parser.add_argument("--body-file", required=True)
    build_parser.add_argument("--comments-file")
    build_parser.add_argument("--output", default=".git/review-pr.json")
    build_parser.set_defaults(func=build)

    check_parser = subparsers.add_parser("check", help="validate an existing payload")
    check_parser.add_argument("payload")
    check_parser.set_defaults(func=check)

    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    try:
        args = parse_args(argv)
        args.func(args)
    except Exception as exc:  # noqa: BLE001
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
