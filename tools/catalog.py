#!/usr/bin/env python3
"""Generate and validate the Heitorgkk bucket from groups.json.

Commands
  generate            Rewrite bucket/*.json and the README tool table from groups.json.
  check               Verify that bucket/*.json and README.md are in sync with groups.json
                      and run every offline consistency check.
  validate            'check' + Scoop JSON schema validation + online checks (every
                      referenced Scoop manifest exists in its official bucket, the npm
                      package exists, the metapackage payload hash matches).

Only the Python standard library is required, except 'validate', which uses the
'jsonschema' package for schema validation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "groups.json"
BUCKET_DIR = ROOT / "bucket"
README = ROOT / "README.md"
PAYLOAD = ROOT / "meta" / "metapackage.txt"

METAPACKAGE_VERSION = "1.2.0"
LICENSE = "Unlicense"
SOURCES = {"scoop", "npm", "uv-tool", "winget", "claude-plugin", "claude-skill"}
# Post-install configuration steps implemented in scripts/lib/Integrations.ps1.
INTEGRATIONS = {"rtk", "graphify", "headroom-mcp", "msys2-rust"}
DIRECT_ARCHS = {"x64", "arm64"}
SCHEMA_URL = "https://raw.githubusercontent.com/ScoopInstaller/Scoop/master/schema.json"
README_BEGIN = "<!-- BEGIN GENERATED TOOLS TABLE (tools/catalog.py generate) -->"
README_END = "<!-- END GENERATED TOOLS TABLE -->"


class CatalogError(Exception):
    pass


def load_catalog() -> dict:
    with CATALOG.open(encoding="utf-8") as fh:
        return json.load(fh)


def payload_url(catalog: dict) -> str:
    repo = catalog["bucket"]["url"].replace("https://github.com/", "")
    return f"https://raw.githubusercontent.com/{repo}/HEAD/meta/metapackage.txt"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def group_tools(catalog: dict, group: str, _seen: tuple = ()) -> list[dict]:
    """Return every tool of a group, expanding 'includes' recursively."""
    if group in _seen:
        raise CatalogError(f"circular include: {' -> '.join(_seen + (group,))}")
    g = catalog["groups"][group]
    tools = list(g.get("tools", []))
    for inc in g.get("includes", []):
        tools += group_tools(catalog, inc, _seen + (group,))
    return tools


def build_manifest(catalog: dict, name: str) -> dict:
    g = catalog["groups"][name]
    bucket = catalog["bucket"]["name"]
    tools = g.get("tools", [])
    depends = [t["package"] for t in tools if t["source"] == "scoop"]
    depends += [r for r in g.get("requires", []) if r not in depends]
    depends += [f"{bucket}/{inc}" for inc in g.get("includes", [])]

    notes = []
    scoop_names = [t["name"] for t in tools if t["source"] == "scoop"]
    if scoop_names:
        notes.append(f"{bucket}/{name} ({g['title']}): {', '.join(scoop_names)}.")
    elif g.get("includes"):
        notes.append(f"{bucket}/{name} ({g['title']}): {', '.join(g['includes'])}.")
    else:
        notes.append(f"{bucket}/{name} ({g['title']}): prerequisites {', '.join(g.get('requires', []))}.")
    external = [t for t in group_tools(catalog, name) if t["source"] != "scoop"]
    if external:
        notes.append("Not available through Scoop; install with scripts/install.ps1 -Group " + name + ":")
        notes += [f"  {t['name']}: {t['source']} {t['package']}" for t in external]

    return {
        "##": "Metapackage generated from groups.json by tools/catalog.py. Edit groups.json, not this file.",
        "version": METAPACKAGE_VERSION,
        "description": g["description"],
        "homepage": catalog["bucket"]["url"],
        "license": LICENSE,
        "url": payload_url(catalog),
        "hash": sha256(PAYLOAD.read_bytes()),
        "depends": depends,
        "notes": notes,
    }


def dump(obj: dict) -> str:
    return json.dumps(obj, indent=4, ensure_ascii=False) + "\n"


def source_label(t: dict) -> str:
    if t["source"] == "scoop":
        return f"Scoop `{t['package']}`"
    if t["source"] == "npm":
        return f"npm `{t['package']}`"
    if t["source"] == "uv-tool":
        return f"uv tool `{t['package']}`"
    if t["source"] == "claude-plugin":
        return f"Claude plugin `{t['package']}`"
    if t["source"] == "claude-skill":
        return f"Claude skill `{t['package']}`"
    label = f"WinGet `{t['package']}`"
    if t.get("direct"):
        label += " or official MSIX"
    return label


def build_readme_table(catalog: dict) -> str:
    lines = [
        README_BEGIN,
        "| Group | Tool | Description | Source | Notes |",
        "|---|---|---|---|---|",
    ]
    for gname, g in catalog["groups"].items():
        for t in g.get("tools", []):
            notes = t.get("requirements", "").replace("|", "\\|")
            lines.append(
                f"| `{gname}` | [{t['name']}]({t['homepage']}) | {t['summary']} | {source_label(t)} | {notes} |"
            )
    lines.append(README_END)
    return "\n".join(lines)


def render_readme(catalog: dict, text: str) -> str:
    try:
        before, rest = text.split(README_BEGIN, 1)
        _, after = rest.split(README_END, 1)
    except ValueError:
        raise CatalogError(f"README.md is missing the generated table markers ({README_BEGIN!r})")
    return before + build_readme_table(catalog) + after


# --------------------------------------------------------------------------- checks

def check_catalog(catalog: dict) -> list[str]:
    errors: list[str] = []
    buckets = catalog.get("buckets", {})
    own = catalog["bucket"]["name"]
    groups = catalog.get("groups", {})
    seen_names: dict[str, str] = {}
    seen_packages: dict[str, str] = {}

    marketplaces = catalog.get("claudeMarketplaces", {})
    for gname, g in groups.items():
        for ref in g.get("requires", []):
            if ref.count("/") != 1 or ref.split("/")[0] not in buckets:
                errors.append(f"group '{gname}': requires '{ref}' must be 'bucket/package' with a declared bucket")
        if gname != gname.lower():
            errors.append(f"group '{gname}': names must be lowercase")
        if not g.get("tools") and not g.get("includes"):
            errors.append(f"group '{gname}': needs 'tools' or 'includes'")
        for inc in g.get("includes", []):
            if inc not in groups:
                errors.append(f"group '{gname}': includes unknown group '{inc}'")
        for t in g.get("tools", []):
            for key in ("name", "source", "package", "summary", "homepage"):
                if not t.get(key):
                    errors.append(f"group '{gname}': tool {t.get('name')!r} lacks '{key}'")
            src = t.get("source")
            if src not in SOURCES:
                errors.append(f"tool '{t.get('name')}': unknown source {src!r}")
            if t["name"] in seen_names:
                errors.append(f"tool '{t['name']}' is declared in '{seen_names[t['name']]}' and '{gname}'")
            seen_names[t["name"]] = gname
            if t["package"] in seen_packages:
                errors.append(f"package '{t['package']}' is declared in '{seen_packages[t['package']]}' and '{gname}'")
            seen_packages[t["package"]] = gname
            if src == "claude-plugin":
                plugin, _, mp = t["package"].partition("@")
                if not plugin or mp not in marketplaces:
                    errors.append(f"tool '{t['name']}': '{t['package']}' must be plugin@marketplace with a marketplace declared in 'claudeMarketplaces'")
            if src == "claude-skill":
                errors += check_skill(t)
            if t.get("integration") and t["integration"] not in INTEGRATIONS:
                errors.append(f"tool '{t['name']}': unknown integration {t['integration']!r} (known: {', '.join(sorted(INTEGRATIONS))})")
            if "python" in t and src != "uv-tool":
                errors.append(f"tool '{t['name']}': 'python' is only supported for uv-tool tools")
            if src == "uv-tool" and not t.get("command"):
                errors.append(f"tool '{t['name']}': uv-tool tools need 'command' (used to detect installs outside uv)")
            if t.get("direct"):
                errors += check_direct(t)
            refs = [t["package"]] if src == "scoop" else []
            refs += t.get("requires", [])
            for ref in refs:
                if ref.count("/") != 1:
                    errors.append(f"tool '{t['name']}': '{ref}' must use the explicit 'bucket/package' form")
                    continue
                b = ref.split("/")[0]
                if b not in buckets and b != own:
                    errors.append(f"tool '{t['name']}': bucket '{b}' is not declared in 'buckets'")

    # every include graph must be acyclic and 'all' must cover every other group
    for gname in groups:
        try:
            group_tools(catalog, gname)
        except CatalogError as exc:
            errors.append(str(exc))
    if "all" in groups:
        covered = set()
        stack = list(groups["all"].get("includes", []))
        while stack:
            n = stack.pop()
            if n in covered or n not in groups:
                continue
            covered.add(n)
            stack += groups[n].get("includes", [])
        missing = set(groups) - covered - {"all"}
        if missing:
            errors.append(f"group 'all' does not include: {', '.join(sorted(missing))}")
        if groups["all"].get("tools"):
            errors.append("group 'all' must only use 'includes' (no duplicated tool lists)")
    return errors


def check_skill(t: dict) -> list[str]:
    path = ROOT / t["package"]
    skill = path / "SKILL.md"
    if not skill.is_file():
        return [f"skill '{t['name']}': {t['package']}/SKILL.md not found"]
    text = skill.read_text(encoding="utf-8")
    if not text.startswith("---\n") or "\n---" not in text[4:]:
        return [f"skill '{t['name']}': SKILL.md must start with YAML frontmatter"]
    front = text[4:text.index("\n---", 4)]
    fields = dict(line.split(":", 1) for line in front.splitlines() if ":" in line and not line.startswith(" "))
    errors = []
    if fields.get("name", "").strip() != path.name:
        errors.append(f"skill '{t['name']}': frontmatter name must be '{path.name}'")
    if not fields.get("description", "").strip():
        errors.append(f"skill '{t['name']}': frontmatter needs a description")
    return errors


def check_direct(t: dict) -> list[str]:
    d = t["direct"]
    errors = []
    if t["source"] != "winget":
        errors.append(f"tool '{t['name']}': 'direct' is only supported for winget tools")
    if d.get("type") != "msix":
        errors.append(f"tool '{t['name']}': direct.type must be 'msix'")
    urls = d.get("url", {})
    if "x64" not in urls or set(urls) - DIRECT_ARCHS or not all(u.startswith("https://") for u in urls.values()):
        errors.append(f"tool '{t['name']}': direct.url needs https URLs for x64 (and optionally arm64)")
    if not d.get("appxName"):
        errors.append(f"tool '{t['name']}': direct.appxName is required")
    if not d.get("signer") and not d.get("publisher"):
        errors.append(f"tool '{t['name']}': direct needs 'publisher' (exact MSIX publisher) and/or 'signer' (text in the signer name)")
    return errors


def check_generated(catalog: dict) -> list[str]:
    errors = []
    expected = {f"{n}.json" for n in catalog["groups"]}
    actual = {p.name for p in BUCKET_DIR.glob("*.json")}
    for extra in sorted(actual - expected):
        errors.append(f"bucket/{extra} is not described in groups.json")
    for name in catalog["groups"]:
        path = BUCKET_DIR / f"{name}.json"
        if not path.exists():
            errors.append(f"bucket/{name}.json is missing (run: python tools/catalog.py generate)")
            continue
        try:
            current = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            errors.append(f"bucket/{name}.json is not valid JSON: {exc}")
            continue
        if current != build_manifest(catalog, name):
            errors.append(f"bucket/{name}.json is out of sync with groups.json (run: python tools/catalog.py generate)")
    if README.exists():
        text = README.read_text(encoding="utf-8")
        try:
            if render_readme(catalog, text) != text:
                errors.append("README.md tool table is out of sync (run: python tools/catalog.py generate)")
        except CatalogError as exc:
            errors.append(str(exc))
    else:
        errors.append("README.md is missing")
    return errors


def http_get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "scoop-bucket-validator"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def raw_manifest_url(bucket_repo: str, package: str) -> str:
    repo = bucket_repo.replace("https://github.com/", "")
    return f"https://raw.githubusercontent.com/{repo}/HEAD/bucket/{package}.json"


def check_schema(catalog: dict) -> list[str]:
    try:
        import jsonschema
    except ImportError:
        return ["python package 'jsonschema' is required for schema validation (pip install jsonschema)"]
    schema = json.loads(http_get(SCHEMA_URL))
    validator = jsonschema.Draft7Validator(schema)
    errors = []
    for path in sorted(BUCKET_DIR.glob("*.json")):
        manifest = json.loads(path.read_text(encoding="utf-8"))
        for err in validator.iter_errors(manifest):
            loc = "/".join(str(p) for p in err.absolute_path) or "<root>"
            errors.append(f"{path.name}: schema: {loc}: {err.message}")
    return errors


def check_online(catalog: dict) -> list[str]:
    errors = []
    own = catalog["bucket"]["name"]
    refs: dict[str, str] = {}
    for gname, g in catalog["groups"].items():
        for t in g.get("tools", []):
            if t["source"] == "scoop":
                refs[t["package"]] = t["name"]
            for r in t.get("requires", []):
                refs[r] = t["name"]
    checked = set()
    for ref, tool in sorted(refs.items()):
        bucket, package = ref.split("/")
        checked.add(ref)
        if bucket == own:
            continue
        url = raw_manifest_url(catalog["buckets"][bucket], package)
        try:
            manifest = json.loads(http_get(url))
            print(f"  ok   {ref:<26} {manifest.get('version')}")
        except urllib.error.HTTPError as exc:
            errors.append(f"tool '{tool}': {ref} not found in its bucket ({exc.code} {url})")
        except (urllib.error.URLError, json.JSONDecodeError) as exc:
            errors.append(f"tool '{tool}': could not fetch {url}: {exc}")
    for g in catalog["groups"].values():
        for r in g.get("requires", []):
            refs[r] = "group requires"
    for ref, tool in sorted(refs.items()):
        if ref in checked:
            continue
        bucket, package = ref.split("/")
        url = raw_manifest_url(catalog["buckets"][bucket], package)
        try:
            http_get(url)
        except urllib.error.URLError as exc:
            errors.append(f"{tool}: {ref} not found ({exc})")
    market_cache: dict[str, set] = {}
    for gname, g in catalog["groups"].items():
        for t in g.get("tools", []):
            if t["source"] == "claude-plugin":
                plugin, _, mp = t["package"].partition("@")
                if mp not in market_cache:
                    repo = catalog["claudeMarketplaces"][mp]
                    try:
                        data = json.loads(http_get(f"https://raw.githubusercontent.com/{repo}/HEAD/.claude-plugin/marketplace.json"))
                        market_cache[mp] = {p["name"] for p in data.get("plugins", [])}
                        if data.get("name") != mp:
                            errors.append(f"marketplace {repo} is named '{data.get('name')}', not '{mp}'")
                    except (urllib.error.URLError, json.JSONDecodeError) as exc:
                        errors.append(f"marketplace {mp} ({repo}) not readable: {exc}")
                        market_cache[mp] = set()
                if plugin in market_cache[mp]:
                    print(f"  ok   plugin {t['package']}")
                elif market_cache[mp]:
                    errors.append(f"tool '{t['name']}': plugin '{plugin}' not found in marketplace '{mp}'")
            if t.get("direct"):
                for arch, url in t["direct"]["url"].items():
                    try:
                        req = urllib.request.Request(url, headers={"User-Agent": "scoop-bucket-validator", "Range": "bytes=0-0"})
                        with urllib.request.urlopen(req, timeout=60) as resp:
                            print(f"  ok   direct {t['name']} {arch} -> {resp.geturl()}")
                    except urllib.error.URLError as exc:
                        errors.append(f"tool '{t['name']}': direct {arch} URL {url} not reachable: {exc}")
            if t["source"] == "uv-tool":
                dist = t["package"].split("[", 1)[0]
                try:
                    meta = json.loads(http_get(f"https://pypi.org/pypi/{dist}/json"))
                    print(f"  ok   pypi:{dist:<21} {meta['info'].get('version')}")
                except (urllib.error.URLError, json.JSONDecodeError, KeyError) as exc:
                    errors.append(f"tool '{t['name']}': PyPI package {dist} not reachable: {exc}")
            if t["source"] == "npm":
                url = f"https://registry.npmjs.org/{t['package'].replace('/', '%2F')}/latest"
                try:
                    meta = json.loads(http_get(url))
                    print(f"  ok   npm:{t['package']:<22} {meta.get('version')}")
                except urllib.error.URLError as exc:
                    errors.append(f"tool '{t['name']}': npm package {t['package']} not reachable: {exc}")
    return errors


def check_payload_online(catalog: dict) -> list[str]:
    url = payload_url(catalog)
    local = sha256(PAYLOAD.read_bytes())
    try:
        remote = sha256(http_get(url))
    except urllib.error.URLError as exc:
        return [f"metapackage payload not reachable at {url}: {exc} (expected before the first push)"]
    if remote != local:
        return [f"metapackage payload at {url} has sha256 {remote}, local file has {local}"]
    print(f"  ok   payload {url}")
    return []


# --------------------------------------------------------------------------- main

def cmd_generate(catalog: dict) -> int:
    errors = check_catalog(catalog)
    if errors:
        return report(errors)
    BUCKET_DIR.mkdir(exist_ok=True)
    for name in catalog["groups"]:
        (BUCKET_DIR / f"{name}.json").write_text(dump(build_manifest(catalog, name)), encoding="utf-8", newline="\n")
        print(f"wrote bucket/{name}.json")
    if README.exists():
        README.write_text(render_readme(catalog, README.read_text(encoding="utf-8")), encoding="utf-8", newline="\n")
        print("updated README.md tool table")
    return 0


def report(errors: list[str]) -> int:
    for e in errors:
        print(f"ERROR: {e}", file=sys.stderr)
    print(f"{len(errors)} error(s)" if errors else "all checks passed")
    return 1 if errors else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["generate", "check", "validate"])
    parser.add_argument("--allow-missing-payload", action="store_true",
                        help="validate: do not fail when the payload is not yet published")
    args = parser.parse_args(argv)
    catalog = load_catalog()

    if args.command == "generate":
        return cmd_generate(catalog)

    print("catalog / generated files")
    errors = check_catalog(catalog) + check_generated(catalog)
    if args.command == "validate":
        print("scoop schema")
        errors += check_schema(catalog)
        print("referenced packages")
        errors += check_online(catalog)
        print("metapackage payload")
        payload_errors = check_payload_online(catalog)
        if args.allow_missing_payload:
            for e in payload_errors:
                print(f"WARNING: {e}")
        else:
            errors += payload_errors
    return report(errors)


if __name__ == "__main__":
    sys.exit(main())
