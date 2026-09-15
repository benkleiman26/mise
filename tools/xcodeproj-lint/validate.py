#!/usr/bin/env python3
"""Parses an old style (NeXTSTEP) plist and checks a pbxproj for integrity.

There is no Xcode in this environment to open the file, so this stands in for
"does it at least parse and does every reference resolve".
"""
import re, sys, pathlib

class P:
    def __init__(self, text):
        self.s = text
        self.i = 0

    def ws(self):
        while self.i < len(self.s):
            if self.s[self.i] in " \t\r\n":
                self.i += 1
            elif self.s.startswith("//", self.i):
                self.i = self.s.find("\n", self.i)
                if self.i < 0: self.i = len(self.s)
            elif self.s.startswith("/*", self.i):
                end = self.s.find("*/", self.i)
                if end < 0: raise ValueError("unterminated comment")
                self.i = end + 2
            else:
                return

    def value(self):
        self.ws()
        c = self.s[self.i]
        if c == "{": return self.dict()
        if c == "(": return self.array()
        if c == '"': return self.quoted()
        return self.bare()

    def dict(self):
        assert self.s[self.i] == "{"; self.i += 1
        out = {}
        while True:
            self.ws()
            if self.s[self.i] == "}":
                self.i += 1
                return out
            key = self.value()
            self.ws()
            if self.s[self.i] != "=":
                raise ValueError(f"expected = after {key!r} at {self.i}")
            self.i += 1
            out[key] = self.value()
            self.ws()
            if self.s[self.i] != ";":
                raise ValueError(f"expected ; after {key!r} at {self.i}")
            self.i += 1

    def array(self):
        assert self.s[self.i] == "("; self.i += 1
        out = []
        while True:
            self.ws()
            if self.s[self.i] == ")":
                self.i += 1
                return out
            out.append(self.value())
            self.ws()
            if self.s[self.i] == ",":
                self.i += 1

    def quoted(self):
        assert self.s[self.i] == '"'; self.i += 1
        buf = []
        while True:
            c = self.s[self.i]
            if c == "\\":
                buf.append(self.s[self.i + 1]); self.i += 2
            elif c == '"':
                self.i += 1
                return "".join(buf)
            else:
                buf.append(c); self.i += 1

    def bare(self):
        m = re.compile(r"[A-Za-z0-9_$./\-*@~<>:]+").match(self.s, self.i)
        if not m: raise ValueError(f"bad token at {self.i}: {self.s[self.i:self.i+40]!r}")
        self.i = m.end()
        return m.group()

path = pathlib.Path(sys.argv[1])
text = path.read_text()
if not text.startswith("// !$*UTF8*$!"):
    sys.exit("missing the UTF8 header line")

p = P(text)
root = p.value()
p.ws()
if p.i != len(text):
    sys.exit(f"trailing content at byte {p.i}")

objects = root["objects"]
problems = []

for key in ("archiveVersion", "objectVersion", "rootObject", "classes"):
    if key not in root: problems.append(f"root is missing {key}")

ids = set(objects)
for oid, obj in objects.items():
    if len(oid) != 24: problems.append(f"{oid} is not 24 characters")
    if not isinstance(obj, dict) or "isa" not in obj:
        problems.append(f"{oid} has no isa")

def refs(value):
    if isinstance(value, str):
        if re.fullmatch(r"[0-9A-F]{24}", value): yield value
    elif isinstance(value, list):
        for v in value: yield from refs(v)
    elif isinstance(value, dict):
        for v in value.values(): yield from refs(v)

for oid, obj in objects.items():
    for ref in refs(obj):
        if ref not in ids:
            problems.append(f"{oid} ({obj.get('isa')}) references {ref}, which is not defined")

if root["rootObject"] not in ids:
    problems.append("rootObject is not defined")

project = objects[root["rootObject"]]
if project["isa"] != "PBXProject": problems.append("rootObject is not a PBXProject")

for ref in refs(root["rootObject"]):
    pass

# Nothing should be orphaned: every object must be reachable from the root.
reachable = set()
def walk(oid):
    if oid in reachable: return
    reachable.add(oid)
    for ref in refs(objects[oid]):
        if ref in ids: walk(ref)
walk(root["rootObject"])
for oid in ids - reachable:
    problems.append(f"{oid} ({objects[oid].get('isa')}) is not reachable from the project")

# Sanity checks specific to what this project needs.
targets = [objects[t] for t in project["targets"]]
names = sorted(t["name"] for t in targets)
if names != ["Mise", "MiseTests"]: problems.append(f"unexpected targets: {names}")
for target in targets:
    for phase in target["buildPhases"]:
        if phase not in ids: problems.append(f"{target['name']} has a dangling build phase")
    if "fileSystemSynchronizedGroups" not in target:
        problems.append(f"{target['name']} has no synchronized group")
    configs = objects[target["buildConfigurationList"]]["buildConfigurations"]
    if sorted(objects[c]["name"] for c in configs) != ["Debug", "Release"]:
        problems.append(f"{target['name']} is missing a configuration")

app = next(t for t in targets if t["name"] == "Mise")
settings = objects[objects[app["buildConfigurationList"]]["buildConfigurations"][0]]["buildSettings"]
if settings["PRODUCT_BUNDLE_IDENTIFIER"] != "com.benkleiman.mise":
    problems.append("wrong bundle identifier")
project_settings = objects[objects[project["buildConfigurationList"]]["buildConfigurations"][0]]["buildSettings"]
if project_settings["IPHONEOS_DEPLOYMENT_TARGET"] != "18.0":
    problems.append("wrong deployment target")

if problems:
    print("\n".join(problems))
    sys.exit(f"\n{len(problems)} problems.")
print(f"parsed cleanly: {len(objects)} objects, targets {names}, all references resolve")
