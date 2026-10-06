"""Audit the resolved pinned Maven graph against OSV; fail closed on outages.

Only public package coordinates/versions are sent. No account or cache inputs.
https://google.github.io/osv.dev/post-v1-querybatch/
"""
import json
import pathlib
import re
import sys
import urllib.request


def coordinates(graph):
    entries = set(re.findall(r"([\w.-]+):([\w.-]+):jar:([\w.+-]+):(compile|runtime|test)", graph))
    if not entries:
        raise ValueError("missing dependency graph")
    return [{"package": {"ecosystem": "Maven", "name": f"{group}:{artifact}"}, "version": version}
            for group, artifact, version, _ in sorted(entries)]


def query(queries):
    request = urllib.request.Request("https://api.osv.dev/v1/querybatch",
                                     data=json.dumps({"queries": queries}).encode(),
                                     headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=45) as response:
        payload = response.read(1024 * 1024 + 1)
    if len(payload) > 1024 * 1024:
        raise ValueError("response bound")
    return json.loads(payload)


def audit(queries, transport=query):
    findings = set()
    pending = queries
    for _ in range(8):
        results = transport(pending)["results"]
        if len(results) != len(pending):
            raise ValueError("response count")
        next_queries = []
        for coordinate, result in zip(pending, results):
            for vulnerability in result.get("vulns", []):
                identifier = vulnerability["id"]
                if not re.fullmatch(r"[A-Za-z0-9.-]{1,100}", identifier):
                    raise ValueError("unsafe identifier")
                findings.add((coordinate["package"]["name"], coordinate["version"], identifier))
            if result.get("next_page_token"):
                next_queries.append({**coordinate, "page_token": result["next_page_token"]})
        pending = next_queries
        if not pending:
            return sorted(findings)
    raise ValueError("pagination bound")


def main(arguments):
    try:
        graph = pathlib.Path(arguments[0]).read_text()
        queries = coordinates(graph)
        findings = audit(queries)
        pathlib.Path(arguments[1]).write_text(json.dumps({"packages": queries, "findings": findings}, indent=2) + "\n")
        if findings:
            for package, version, identifier in findings:
                print(f"Dependency audit: {package}:{version} {identifier}")
            return 1
        print(f"Dependency audit passed: {len(queries)} resolved Maven dependencies; OSV.")
        return 0
    except Exception:
        print("Dependency audit unavailable or invalid; verification incomplete.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
