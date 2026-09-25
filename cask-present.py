#!/usr/bin/env python3
"""Classify Brewfile casks that are already on disk so brew bundle can skip them."""
import argparse
import json
import os
import subprocess
import sys


def as_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def strings(value):
    return [item for item in as_list(value) if isinstance(item, str)]


def exists(path):
    return os.path.exists(os.path.expanduser(path))


def brewfile_casks(path):
    names = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line.startswith("cask "):
                parts = line.split('"')
                if len(parts) >= 2:
                    names.append(parts[1])
    return names


def brew_listed_casks():
    result = subprocess.run(
        ["brew", "list", "--cask"],
        capture_output=True,
        text=True,
        check=False,
    )
    listed = set()
    for token in result.stdout.split():
        listed.add(token)
        listed.add(token.split("/")[-1])
    return listed


def brew_info(casks):
    if not casks:
        return []
    result = subprocess.run(
        ["brew", "info", "--cask", "--json=v2", *casks],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode == 0 and result.stdout.strip():
        return json.loads(result.stdout).get("casks") or []

    found = []
    for name in casks:
        one = subprocess.run(
            ["brew", "info", "--cask", "--json=v2", name],
            capture_output=True,
            text=True,
            check=False,
        )
        if one.returncode == 0 and one.stdout.strip():
            found.extend(json.loads(one.stdout).get("casks") or [])
    return found


def pkgutil_ok(pkg_id):
    return subprocess.run(
        ["pkgutil", "--pkg-info", pkg_id],
        capture_output=True,
        check=False,
    ).returncode == 0


def app_on_disk(name):
    if name.endswith(".app") and (os.path.isabs(name) or name.startswith("~")):
        return exists(name)
    base = name if name.endswith(".app") else f"{name}.app"
    return exists(f"/Applications/{base}") or exists(
        os.path.expanduser(f"~/Applications/{base}")
    )


def is_helper(path):
    return (
        "/PrivilegedHelperTools/" in path
        or "/SystemExtensions/" in path
        or "/LaunchDaemons/" in path
        or "/LaunchAgents/" in path
        or path.endswith(".systemextension")
    )


def classify_cask(cask):
    app = False
    payload = False
    leftover = False

    for artifact in cask.get("artifacts") or []:
        if not isinstance(artifact, dict):
            continue

        for app_name in strings(artifact.get("app")):
            if app_on_disk(app_name):
                app = True

        target = artifact.get("target")
        if isinstance(target, str) and exists(target):
            if target.endswith(".app") or "/Applications/" in target:
                app = True
            else:
                payload = True

        for uninstall in as_list(artifact.get("uninstall")):
            if not isinstance(uninstall, dict):
                continue
            for pkg_id in strings(uninstall.get("pkgutil")):
                if pkgutil_ok(pkg_id):
                    leftover = True
            for item in strings(uninstall.get("login_item")):
                if app_on_disk(item):
                    app = True
            for path in strings(uninstall.get("delete")):
                if not exists(path):
                    continue
                if path.endswith(".app") or "/Applications/" in path:
                    app = True
                elif is_helper(path):
                    leftover = True
                else:
                    payload = True

    if app or payload:
        return "present"
    if leftover:
        return "leftover"
    return "missing"


def index_casks(info):
    by_name = {}
    for cask in info:
        token = cask.get("token")
        full = cask.get("full_token") or token
        if token:
            by_name[token] = cask
        if full:
            by_name[full] = cask
    return by_name


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip", action="store_true")
    parser.add_argument("--classify", action="store_true")
    parser.add_argument("--brewfile")
    parser.add_argument("casks", nargs="*")
    args = parser.parse_args()

    names = list(args.casks)
    if args.brewfile:
        names = brewfile_casks(args.brewfile) if not names else names

    listed = brew_listed_casks()
    lookup = index_casks(brew_info(names))
    skip = []

    for name in names:
        short = name.split("/")[-1]
        if args.skip and (name in listed or short in listed):
            continue
        cask = lookup.get(name) or lookup.get(short)
        if not cask:
            state = "missing"
        else:
            state = classify_cask(cask)
        if args.classify:
            print(f"{name}\t{state}")
        elif args.skip and state in ("present", "leftover"):
            skip.append(name)

    if args.skip:
        print(" ".join(skip))


if __name__ == "__main__":
    sys.exit(main() or 0)
