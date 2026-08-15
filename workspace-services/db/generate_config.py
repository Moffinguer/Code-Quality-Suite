#!/usr/bin/env python3
"""Loader: read the DB and generate the LiteLLM config plus the role definitions.

Selection rules:
  - model with an env key present -> included
  - model without a key           -> skipped
  - model dead at runtime          -> parked by LiteLLM cooldown

Per-role ladder: among the models meeting the role's minimum quality, order FREE
first (cost asc) then best quality first, so good free models stay in the upper
layers and paid ones are the last resort.

Usage:  DATABASE_URL=postgresql://... python generate_config.py [out_dir]
"""
import json
import os
import sys

import psycopg
import yaml

DB = os.environ["DATABASE_URL"]
OUT = sys.argv[1] if len(sys.argv) > 1 else "."


def has_key(env_var, category):
    if category == "local":
        return True
    return bool(env_var and os.environ.get(env_var))


def litellm_params(m):
    p = {"model": m["litellm_prefix"] + m["slug"]}
    if m["category"] == "local":
        if m["base_url"]:
            p["api_base"] = m["base_url"]
    else:
        p["api_key"] = f"os.environ/{m['env_var']}"
    return p


def ladder(models, min_tier, prefer_free):
    cand = [m for m in models if m["quality_tier"] >= min_tier]
    def key(m):
        cost = float(m["cost_in_mtok"])
        return (cost if prefer_free else 0, -m["quality_tier"], m["priority"])
    return sorted(cand, key=key)


def main():
    with psycopg.connect(DB, row_factory=psycopg.rows.dict_row) as conn:
        models = conn.execute("SELECT * FROM v_models").fetchall()
        roles = conn.execute(
            "SELECT * FROM agent_roles WHERE enabled ORDER BY level, name"
        ).fetchall()
        rtt = conn.execute(
            """SELECT r.name AS role, t.name AS task
               FROM role_task_types x
               JOIN agent_roles r ON r.id = x.role_id
               JOIN task_types  t ON t.id = x.task_type_id"""
        ).fetchall()

    # Include only models whose key is present (locals always qualify).
    available = [m for m in models if has_key(m["env_var"], m["category"])]
    skipped = [m["alias"] for m in models if m not in available]

    model_list = [{"model_name": m["alias"], "litellm_params": litellm_params(m)}
                  for m in available]

    fallbacks = []
    # Global 'auto': best available, free first.
    glob = ladder(available, 1, True)
    if glob:
        top = glob[0]
        model_list.append({"model_name": "auto", "litellm_params": litellm_params(top)})
        fallbacks.append({"auto": [m["alias"] for m in glob[1:]]})

    # One alias per role, each with its own ladder.
    roles_out = {}
    tasks_by_role = {}
    for r in rtt:
        tasks_by_role.setdefault(r["role"], []).append(r["task"])

    for r in roles:
        lad = ladder(available, r["min_quality_tier"], r["prefer_free"])
        if not lad:
            continue
        model_list.append({"model_name": r["name"],
                            "litellm_params": litellm_params(lad[0])})
        fallbacks.append({r["name"]: [m["alias"] for m in lad[1:]]})
        roles_out[r["name"]] = {
            "level": r["level"],
            "description": r["description"],
            "system_prompt": r["system_prompt"],
            "model": r["name"],
            "ladder": [m["alias"] for m in lad],
            "task_types": tasks_by_role.get(r["name"], []),
        }

    config = {
        "model_list": model_list,
        "router_settings": {
            "routing_strategy": "simple-shuffle",
            "cooldown_time": 300,
            "allowed_fails": 1,
            "fallbacks": fallbacks,
        },
        "litellm_settings": {"drop_params": True, "num_retries": 1, "request_timeout": 60},
        "general_settings": {"master_key": "os.environ/LITELLM_MASTER_KEY"},
    }

    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "config.generated.yaml"), "w") as f:
        yaml.safe_dump(config, f, sort_keys=False, allow_unicode=True)
    with open(os.path.join(OUT, "roles.generated.json"), "w") as f:
        json.dump(roles_out, f, indent=2, ensure_ascii=False)

    print(f"Modelos disponibles: {len(available)}  |  saltados (sin clave): {len(skipped)}")
    if skipped:
        print("  saltados:", ", ".join(skipped))
    print(f"Roles con escalera: {len(roles_out)}")
    print(f"Generado: {OUT}/config.generated.yaml y {OUT}/roles.generated.json")


if __name__ == "__main__":
    main()
