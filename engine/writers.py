"""Native config writers: base config (from the image) + rules (from the universal file).

Strategies per format:
  merge    parse base, deep-merge rules (dicts merge, lists replace), render
  append   base text + rendered overlay (the tool applies the last definition)
  generate render rules only (no base file)
"""
import copy
import json
import re
import xml.etree.ElementTree as ET

try:
    import tomllib
except ImportError:  # python < 3.11
    tomllib = None

from builtin import strip_jsonc


def deep_merge(base, over):
    out = copy.deepcopy(base)
    for k, v in (over or {}).items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = deep_merge(out[k], v)
        else:
            out[k] = copy.deepcopy(v)
    return out


# ---------- renderers ----------

def _toml_key(k):
    return k if re.match(r"^[A-Za-z0-9_-]+$", k) else json.dumps(k)


def _toml_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, list):
        return "[" + ", ".join(_toml_val(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{ " + ", ".join(f"{_toml_key(k)} = {_toml_val(x)}" for k, x in v.items()) + " }"
    return json.dumps(str(v))


def render_toml(data, prefix=""):
    lines, tables, arrays = [], [], []
    for k, v in data.items():
        if isinstance(v, dict):
            tables.append((k, v))
        elif isinstance(v, list) and v and all(isinstance(x, dict) for x in v):
            arrays.append((k, v))
        else:
            lines.append(f"{_toml_key(k)} = {_toml_val(v)}")
    out = "\n".join(lines)
    for k, v in tables:
        name = f"{prefix}.{_toml_key(k)}" if prefix else _toml_key(k)
        body = render_toml(v, name)
        scalars = any(not isinstance(x, dict) for x in v.values())
        out += f"\n\n[{name}]\n" + body if scalars or not v else "\n" + body
    for k, v in arrays:
        name = f"{prefix}.{_toml_key(k)}" if prefix else _toml_key(k)
        for item in v:
            out += f"\n\n[[{name}]]\n" + render_toml(item, name)
    return out.strip("\n") + "\n"


def render_yaml(data):
    import yaml
    return yaml.safe_dump(data, sort_keys=False, default_flow_style=False, allow_unicode=True)


def _ini_val(v, style):
    if isinstance(v, bool):
        return {"num": "1" if v else "0", "py": "True" if v else "False"}.get(style, "true" if v else "false")
    if isinstance(v, list):
        return ",".join(str(x) for x in v)
    return str(v)


def render_ini(data, style="lower"):
    lines = [f"{k} = {_ini_val(v, style)}" for k, v in data.items() if not isinstance(v, dict)]
    for sec, body in data.items():
        if isinstance(body, dict):
            lines.append(f"\n[{sec}]")
            lines += [f"{k} = {_ini_val(v, style)}" for k, v in body.items()]
    return "\n".join(lines).strip("\n") + "\n"


def parse_ini(text):
    data = {}
    cur = data
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line[0] in "#;":
            continue
        m = re.match(r"^\[(.+)\]$", line)
        if m:
            cur = data.setdefault(m.group(1), {})
            continue
        if "=" in line:
            k, v = line.split("=", 1)
            cur[k.strip()] = v.strip()
        elif ":" in line:
            k, v = line.split(":", 1)
            cur[k.strip()] = v.strip()
        else:
            cur[line] = ""
    return data


def render_rc(data, sep="="):
    out = []
    for k, v in data.items():
        if isinstance(v, list):
            v = ",".join(str(x) for x in v)
        elif isinstance(v, bool):
            v = "true" if v else "false"
        out.append(f"{k}{sep}{v}")
    return "\n".join(out) + "\n"


def parse_flags(text):
    """perltidyrc-style: one --flag[=value] per line; --noflag -> False; # comments."""
    data = {}
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].strip() if not raw.strip().startswith('--want') else raw.strip()
        if not line.startswith("-"):
            continue
        k, eq, v = line.lstrip("-").partition("=")
        if eq:
            data[k] = v.strip().strip('"') if v.strip().startswith('"') and v.strip().endswith('"') and " " not in v.strip()[1:-1] else v.strip()
        elif k.startswith("no") and len(k) > 2 and k not in ("no-outdent-long-quotes",) and not k.startswith("no-"):
            data[k[2:]] = False
        else:
            data[k] = True
    return data


def render_flags(data, joiner="="):
    out = []
    for k, v in data.items():
        k = k.lstrip("-")
        if v is True:
            out.append(f"--{k}")
        elif v is False:
            out.append(f"--no{k}" if joiner == "=" else f"--{k} false")
        else:
            val = ",".join(map(str, v)) if isinstance(v, list) else v
            out.append(f"--{k}{joiner}{val}" if joiner == "=" else f"--{k} {val}")
    return "\n".join(out) + "\n"


def render_edn(v):
    if isinstance(v, dict):
        return "{" + " ".join(f"{_edn_key(k)} {render_edn(x)}" for k, x in v.items()) + "}"
    if isinstance(v, list):
        return "[" + " ".join(render_edn(x) for x in v) + "]"
    if isinstance(v, bool):
        return "true" if v else "false"
    if v is None:
        return "nil"
    if isinstance(v, (int, float)):
        return str(v)
    s = str(v)
    return s if s.startswith(":") else json.dumps(s)


def _edn_key(k):
    k = str(k)
    return k if k.startswith((":", "'")) or k[:1] in "{[(\"" else ":" + k


def render_lua(data):
    def val(v):
        if isinstance(v, bool):
            return "true" if v else "false"
        if isinstance(v, (int, float)):
            return str(v)
        if isinstance(v, list):
            return "{" + ", ".join(val(x) for x in v) + "}"
        if isinstance(v, dict):
            return "{" + ", ".join(f"[{json.dumps(k)}] = {val(x)}" for k, x in v.items()) + "}"
        return json.dumps(str(v))
    return "\n".join(f"{k} = {val(v)}" for k, v in data.items()) + "\n"


def render_hocon(data, prefix=""):
    out = []
    for k, v in data.items():
        key = f"{prefix}.{k}" if prefix else k
        if isinstance(v, dict):
            out.append(render_hocon(v, key).rstrip("\n"))
        elif isinstance(v, list):
            out.append(f"{key} = [" + ", ".join(json.dumps(x) if isinstance(x, str) else str(x).lower() for x in v) + "]")
        elif isinstance(v, bool):
            out.append(f"{key} = {'true' if v else 'false'}")
        elif isinstance(v, (int, float)):
            out.append(f"{key} = {v}")
        else:
            out.append(f"{key} = {json.dumps(str(v))}")
    return "\n".join(x for x in out if x) + "\n"


def render_editorconfig(data, default_section):
    out = []
    flat = {k: v for k, v in data.items() if not isinstance(v, dict)}
    if flat:
        out.append(f"[{default_section}]")
        out += [f"{k} = {str(v).lower() if isinstance(v, bool) else v}" for k, v in flat.items()]
    for sec, body in data.items():
        if isinstance(body, dict):
            out.append(f"\n[{sec.strip('[]')}]")
            out += [f"{k} = {str(v).lower() if isinstance(v, bool) else v}" for k, v in body.items()]
    return "\n".join(out) + "\n"


def render_psd1(v, indent=0):
    pad = "    " * indent
    if isinstance(v, dict):
        inner = "\n".join(f"{pad}    {k} = {render_psd1(x, indent + 1).lstrip()}" for k, x in v.items())
        return "@{\n" + inner + f"\n{pad}}}"
    if isinstance(v, list):
        return "@(" + ", ".join(render_psd1(x, indent).strip() for x in v) + ")"
    if isinstance(v, bool):
        return "$true" if v else "$false"
    if isinstance(v, (int, float)):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"


def render_exs(data):
    def val(v):
        if isinstance(v, bool):
            return "true" if v else "false"
        if isinstance(v, (int, float)):
            return str(v)
        if isinstance(v, list):
            return "[" + ", ".join(val(x) for x in v) + "]"
        if isinstance(v, dict):
            return "[" + ", ".join(f"{k}: {val(x)}" for k, x in v.items()) + "]"
        s = str(v)
        return s if s.startswith(":") else json.dumps(s)
    return val(data) + "\n"


def render_hcl(data):
    def attr(v):
        if isinstance(v, bool):
            return "true" if v else "false"
        if isinstance(v, (int, float)):
            return str(v)
        if isinstance(v, list):
            return "[" + ", ".join(attr(x) for x in v) + "]"
        return json.dumps(str(v))
    out = []
    for k, v in data.items():
        if k in ("rule", "plugin") and isinstance(v, dict):
            for label, body in v.items():
                out.append(f'{k} "{label}" {{')
                out += [f"  {a} = {attr(b)}" for a, b in body.items()]
                out.append("}")
        elif isinstance(v, dict):
            out.append(f"{k} {{")
            out += [f"  {a} = {attr(b)}" for a, b in v.items()]
            out.append("}")
        else:
            out.append(f"{k} = {attr(v)}")
    return "\n".join(out) + "\n"


def render_verible(data):
    out = []
    for k, v in data.items():
        if v is False:
            out.append(f"-{k}")
        elif v is True or v in ("", None):
            out.append(f"+{k}")
        else:
            out.append(f"+{k}={v}")
    return "\n".join(out) + "\n"


# ---------- XML (Checkstyle / PMD) ----------

def merge_checkstyle(base_text, rules):
    """rules: {Module: false | true | {prop: value}}; Checker-level modules via '@checker' list."""
    doctype = re.search(r"<!DOCTYPE[^>]*>", base_text)
    root = ET.fromstring(re.sub(r"<!DOCTYPE[^>]*>", "", base_text))
    tw = root.find(".//module[@name='TreeWalker']")
    checker_level = set(rules.get("@checker", ["LineLength", "FileLength", "FileTabCharacter",
                                               "NewlineAtEndOfFile", "RegexpSingleline", "SuppressWarningsFilter"]))
    for name, spec in rules.items():
        if name.startswith("@"):
            continue
        found = [(parent, m) for parent in root.iter("module") for m in parent.findall("module")
                 if m.get("name") == name]
        if spec is False:
            for parent, m in found:
                parent.remove(m)
            continue
        if not found:
            host = root if name in checker_level or tw is None else tw
            m = ET.SubElement(host, "module", {"name": name})
            found = [(host, m)]
        if isinstance(spec, dict):
            for _, m in found:
                for prop, val in spec.items():
                    p = next((p for p in m.findall("property") if p.get("name") == prop), None)
                    sval = ",".join(map(str, val)) if isinstance(val, list) else str(val).lower() if isinstance(val, bool) else str(val)
                    if p is None:
                        ET.SubElement(m, "property", {"name": prop, "value": sval})
                    else:
                        p.set("value", sval)
    ET.indent(root)
    body = ET.tostring(root, encoding="unicode")
    head = '<?xml version="1.0"?>\n' + (doctype.group(0) + "\n" if doctype else "")
    return head + body + "\n"


PMD_NS = "http://pmd.sourceforge.net/ruleset/2.0.0"


def merge_pmd(base_text, rules):
    """rules: {"category/java/x.xml": bool, "category/java/x.xml/Rule": bool | {prop: value}}."""
    ET.register_namespace("", PMD_NS)
    root = ET.fromstring(base_text)
    q = lambda t: f"{{{PMD_NS}}}{t}"
    refs = {r.get("ref"): r for r in root.findall(q("rule"))}
    for ref, spec in rules.items():
        parts = ref.split("/")
        is_rule = len(parts) >= 4 and not ref.endswith(".xml")
        if not is_rule:
            if spec is False and ref in refs:
                root.remove(refs.pop(ref))
            elif spec is not False and ref not in refs:
                refs[ref] = ET.SubElement(root, q("rule"), {"ref": ref})
            continue
        cat, name = "/".join(parts[:-1]), parts[-1]
        if cat in refs and spec is not True:
            if not any(e.get("name") == name for e in refs[cat].findall(q("exclude"))):
                ET.SubElement(refs[cat], q("exclude"), {"name": name})
        if spec is False:
            if ref in refs:
                root.remove(refs.pop(ref))
            continue
        el = refs.get(ref)
        if el is None:
            el = ET.SubElement(root, q("rule"), {"ref": ref})
            refs[ref] = el
        if isinstance(spec, dict):
            props = el.find(q("properties")) or ET.SubElement(el, q("properties"))
            for k, v in spec.items():
                p = next((p for p in props.findall(q("property")) if p.get("name") == k), None)
                if p is None:
                    ET.SubElement(props, q("property"), {"name": k, "value": str(v)})
                else:
                    p.set("value", str(v))
    ET.indent(root)
    return '<?xml version="1.0"?>\n' + ET.tostring(root, encoding="unicode") + "\n"


# ---------- dispatcher ----------

def parse(fmt, text):
    if fmt in ("json", "jsonc"):
        return json.loads(strip_jsonc(text)) if text.strip() else {}
    if fmt in ("yaml", "neon"):
        import yaml
        return yaml.safe_load(text) or {}
    if fmt == "toml":
        if tomllib is None:
            raise RuntimeError("tomllib unavailable")
        return tomllib.loads(text)
    if fmt in ("ini", "ini-num", "ini-py"):
        return parse_ini(text)
    if fmt == "flags":
        return parse_flags(text)
    raise ValueError(f"cannot parse format {fmt}")


def render(fmt, data, spec=None):
    spec = spec or {}
    if fmt in ("json", "jsonc"):
        return json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    if fmt in ("yaml", "neon"):
        return render_yaml(data)
    if fmt == "toml":
        return render_toml(data)
    if fmt == "ini":
        return render_ini(data)
    if fmt == "ini-num":
        return render_ini(data, "num")
    if fmt == "ini-py":
        return render_ini(data, "py")
    if fmt == "rc":
        return render_rc(data)
    if fmt == "rc-colon":
        return render_rc(data, ": ")
    if fmt == "flags":
        return render_flags(data)
    if fmt == "flags-space":
        return render_flags(data, " ")
    if fmt == "edn":
        return render_edn(data) + "\n"
    if fmt == "lua":
        return render_lua(data)
    if fmt == "hocon":
        return render_hocon(data)
    if fmt == "editorconfig":
        return render_editorconfig(data, spec.get("section", "*"))
    if fmt == "psd1":
        return render_psd1(data) + "\n"
    if fmt == "exs":
        return render_exs(data)
    if fmt == "hcl":
        return render_hcl(data)
    if fmt == "verible":
        return render_verible(data)
    raise ValueError(f"unknown format {fmt}")


MERGEABLE = {"json", "jsonc", "yaml", "neon", "toml", "ini", "ini-num", "ini-py", "flags"}


def build(cfg, base_text, rules):
    """Return the native config text for a tool given its registry `config` spec."""
    fmt = cfg["format"]
    rules = rules or {}
    if fmt == "checkstyle":
        return merge_checkstyle(base_text, rules) if rules else base_text
    if fmt == "pmd":
        return merge_pmd(base_text, rules) if rules else base_text
    if fmt == "eslint":
        rule_map = {k: v for k, v in rules.items() if not k.startswith("$")}
        extra = rules.get("$config", {})
        obj = dict(extra)
        if rule_map:
            obj["rules"] = rule_map
        return (f'import base from "{cfg["base_abs"]}";\n'
                f"export default [...base{', ' + json.dumps(obj, indent=2) if obj else ''}];\n")
    if fmt == "php-cs-fixer":
        payload = json.dumps(rules).replace("\\", "\\\\").replace("'", "\\'")
        return ("<?php\n"
                f"$config = require '{cfg['base_abs']}';\n"
                f"return $config->setRules(array_merge($config->getRules(), json_decode('{payload}', true)));\n")
    if base_text is not None and fmt in MERGEABLE:
        return render(fmt, deep_merge(parse(fmt, base_text), rules), cfg)
    if base_text is not None:
        return base_text.rstrip("\n") + "\n" + (render(fmt, rules, cfg) if rules else "")
    return render(fmt, rules, cfg)
