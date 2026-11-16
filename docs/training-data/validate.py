#!/usr/bin/env python3
"""Validate training-data bundles (see docs/training-data-format.md).

Usage:
    python docs/training-data/validate.py                 # check the bundled examples
    python docs/training-data/validate.py bundle.json ... # check your own bundles

A bundle is checked in two steps:

1. JSON Schema (schema.json), with `date-time` and `uuid` formats asserted.
2. Rules a JSON Schema cannot express: unique ids, references that resolve,
   ordering, one entry per exercise, reconciliation consistency and sets that
   fit the exercise type. They only run on bundles that pass step 1.

Without arguments, every file in examples/valid must pass, and every file in
examples/invalid must fail with exactly the rule listed in
examples/invalid/expected.json.

Exit code 0 when everything is as expected, 1 otherwise.
"""

from __future__ import annotations

import json
import re
import sys
import uuid
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Iterator, NamedTuple

from jsonschema import Draft202012Validator, FormatChecker

HERE = Path(__file__).resolve().parent
SCHEMA_PATH = HERE / "schema.json"
VALID_DIR = HERE / "examples" / "valid"
INVALID_DIR = HERE / "examples" / "invalid"
EXPECTED_PATH = INVALID_DIR / "expected.json"

RFC3339 = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$")


class Problem(NamedTuple):
    rule: str
    path: str
    message: str


format_checker = FormatChecker(formats=())


@format_checker.checks("date-time", raises=ValueError)
def _is_instant(value: object) -> bool:
    if not isinstance(value, str):
        return True
    if not RFC3339.match(value):
        raise ValueError("not an RFC 3339 timestamp with an offset")
    datetime.fromisoformat(value.replace("Z", "+00:00"))
    return True


@format_checker.checks("uuid", raises=ValueError)
def _is_uuid(value: object) -> bool:
    if not isinstance(value, str):
        return True
    if str(uuid.UUID(value)) != value:
        raise ValueError("not a canonical lower-case UUID")
    return True


def pointer(parts: object) -> str:
    return "".join(f"/{part}" for part in parts)  # type: ignore[union-attr]


def schema_problems(validator: Draft202012Validator, bundle: object) -> list[Problem]:
    return [
        Problem(f"schema:{error.validator}", pointer(error.absolute_path), error.message)
        for error in sorted(validator.iter_errors(bundle), key=lambda e: list(e.absolute_path))
    ]


def duplicates(values: list) -> list:
    return [value for value, count in Counter(values).items() if count > 1]


def parse_instant(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def rule_problems(bundle: dict) -> Iterator[Problem]:
    exercises = bundle["exercises"]
    routines = bundle.get("routines", [])
    sessions = bundle["sessions"]
    entries = [(f"/sessions/{s}/entries/{e}", entry)
               for s, session in enumerate(sessions)
               for e, entry in enumerate(session["entries"])]
    sets = [(f"{path}/sets/{i}", item)
            for path, entry in entries
            for i, item in enumerate(entry.get("sets", []))]

    # unique-id: one id never names two items of the same kind.
    collections = {
        "exercises": exercises,
        "routines": routines,
        "sessions": sessions,
        "entries": [entry for _, entry in entries],
        "sets": [item for _, item in sets],
    }
    for name, items in collections.items():
        for value in duplicates([item["id"] for item in items]):
            yield Problem("unique-id", f"/{name}", f"id {value} is used more than once")

    # unique-external-ref: the key imports are de-duplicated on.
    for name, items in collections.items():
        refs = [(item["externalRef"]["provider"], item["externalRef"]["id"])
                for item in items if "externalRef" in item]
        for provider, value in duplicates(refs):
            yield Problem("unique-external-ref", f"/{name}",
                          f"external id {value!r} of {provider!r} is used more than once")

    # exercise-reference / routine-reference: bundles are self-contained.
    exercise_ids = {exercise["id"] for exercise in exercises}
    routine_ids = {routine["id"] for routine in routines}
    for path, entry in entries:
        for key in ("exerciseId", "replacedExerciseId"):
            if key in entry and entry[key] not in exercise_ids:
                yield Problem("exercise-reference", f"{path}/{key}", f"unknown exercise {entry[key]}")
    for r, routine in enumerate(routines):
        for i, item in enumerate(routine["items"]):
            if item["exerciseId"] not in exercise_ids:
                yield Problem("exercise-reference", f"/routines/{r}/items/{i}/exerciseId",
                              f"unknown exercise {item['exerciseId']}")
    for s, session in enumerate(sessions):
        if "routineId" in session and session["routineId"] not in routine_ids:
            yield Problem("routine-reference", f"/sessions/{s}/routineId",
                          f"unknown routine {session['routineId']}")

    # order: positions are unique within their parent.
    for s, session in enumerate(sessions):
        if duplicates([entry["order"] for entry in session["entries"]]):
            yield Problem("order", f"/sessions/{s}/entries", "two entries share an order")
    for r, routine in enumerate(routines):
        if duplicates([item["order"] for item in routine["items"]]):
            yield Problem("order", f"/routines/{r}/items", "two items share an order")
    for path, entry in entries:
        # Manual and imported sets are numbered independently.
        if duplicates([(item["source"], item["order"]) for item in entry.get("sets", [])]):
            yield Problem("order", f"{path}/sets", "two sets of the same source share an order")

    # one-entry-per-exercise: what makes "same exercise, same session" a single place.
    for s, session in enumerate(sessions):
        done = [entry["exerciseId"] for entry in session["entries"] if entry["status"] == "done"]
        for value in duplicates(done):
            yield Problem("one-entry-per-exercise", f"/sessions/{s}/entries",
                          f"exercise {value} is done in more than one entry")

    # reconciliation: present exactly when both sources are there, and consistent.
    for path, entry in entries:
        entry_sets = entry.get("sets", [])
        sources = {item["source"] for item in entry_sets}
        decision = entry.get("reconciliation")
        if (len(sources) == 2) != (decision is not None):
            yield Problem("reconciliation", path,
                          "reconciliation must be present exactly when an entry mixes manual and imported sets")
            continue
        for i, item in enumerate(entry_sets):
            should_be_superseded = decision is not None and item["source"] != decision["keep"]
            if item.get("superseded", False) != should_be_superseded:
                yield Problem("reconciliation", f"{path}/sets/{i}",
                              "superseded must be true only for sets of the source that was not kept")

    # exercise-type: sets carry the fields their exercise is logged with.
    exercise_types = {exercise["id"]: exercise["type"] for exercise in exercises}
    for path, entry in entries:
        kind = exercise_types.get(entry["exerciseId"])
        for i, item in enumerate(entry.get("sets", [])):
            if kind == "cardio" and ("durationSeconds" not in item or "reps" in item or "weight" in item):
                yield Problem("exercise-type", f"{path}/sets/{i}",
                              "a cardio set has durationSeconds and neither reps nor weight")
            if kind in ("strength", "bodyweight") and "distanceMeters" in item:
                yield Problem("exercise-type", f"{path}/sets/{i}",
                              "only cardio sets have distanceMeters")

    # range: values that must agree with each other.
    for r, routine in enumerate(routines):
        for i, item in enumerate(routine["items"]):
            reps = item.get("targetReps")
            if reps and reps["min"] > reps["max"]:
                yield Problem("range", f"/routines/{r}/items/{i}/targetReps", "min is greater than max")
    for s, session in enumerate(sessions):
        completed = parse_instant(session["completedAt"])
        if "startedAt" in session:
            elapsed = (completed - parse_instant(session["startedAt"])).total_seconds()
            if elapsed < 0:
                yield Problem("range", f"/sessions/{s}", "startedAt is after completedAt")
            elif session.get("durationSeconds", 0) > elapsed:
                yield Problem("range", f"/sessions/{s}/durationSeconds",
                              "durationSeconds is longer than the time between startedAt and completedAt")
        for e, entry in enumerate(session["entries"]):
            if "completedAt" in entry and parse_instant(entry["completedAt"]) > completed:
                yield Problem("range", f"/sessions/{s}/entries/{e}/completedAt",
                              "an entry is completed after its session")


def check(validator: Draft202012Validator, path: Path) -> list[Problem]:
    try:
        bundle = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [Problem("unreadable", "", str(error))]
    problems = schema_problems(validator, bundle)
    return problems or list(rule_problems(bundle))


def describe(problems: list[Problem]) -> str:
    return "\n".join(f"      {p.rule} at {p.path or '/'}: {p.message}" for p in problems)


def check_examples(validator: Draft202012Validator) -> bool:
    ok = True
    valid_files = sorted(VALID_DIR.glob("*.json"))
    invalid_files = sorted(path for path in INVALID_DIR.glob("*.json") if path != EXPECTED_PATH)
    expected = json.loads(EXPECTED_PATH.read_text(encoding="utf-8"))

    if not valid_files or not invalid_files:
        print("FAIL  no examples found")
        return False

    for path in valid_files:
        problems = check(validator, path)
        print(f"{'FAIL' if problems else 'ok  '}  valid/{path.name}")
        if problems:
            ok = False
            print(describe(problems))

    listed = set(expected)
    present = {path.name for path in invalid_files}
    for name in sorted(listed ^ present):
        ok = False
        print(f"FAIL  invalid/{name}: listed in expected.json and present on disk must match")

    for path in invalid_files:
        want = expected.get(path.name)
        if want is None:
            continue
        problems = check(validator, path)
        got = {(p.rule, p.path) if "path" in want else (p.rule,) for p in problems}
        wanted = {(want["rule"], want["path"]) if "path" in want else (want["rule"],)}
        passed = got == wanted
        print(f"{'ok  ' if passed else 'FAIL'}  invalid/{path.name} -> {want['rule']}")
        if not passed:
            ok = False
            print(f"      expected exactly {want}, got:")
            print(describe(problems) or "      no problems")
    return ok


def check_files(validator: Draft202012Validator, paths: list[str]) -> bool:
    ok = True
    for name in paths:
        problems = check(validator, Path(name))
        print(f"{'FAIL' if problems else 'ok  '}  {name}")
        if problems:
            ok = False
            print(describe(problems))
    return ok


def main(argv: list[str]) -> int:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema, format_checker=format_checker)
    ok = check_files(validator, argv) if argv else check_examples(validator)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
