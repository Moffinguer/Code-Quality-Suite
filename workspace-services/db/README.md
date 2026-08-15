# Configuration database (agent and model hierarchy)

Keeps the model catalog, keys, and agent/responsibility hierarchy out of the code.
A loader (`generate_config.py`) reads it and generates the LiteLLM config plus the
role definitions for the orchestrator.

## Data model

- `providers` - providers (free/trial/paid/local) and their LiteLLM prefix.
- `api_keys` - environment-variable reference (the secret is never stored).
- `models` - models with `quality_tier` (1-5), cost, quotas, `supports_tools`, priority.
- `agent_roles` - hierarchy level 0 (orchestrator) to 3 (cheap worker); each role
  carries its `system_prompt` (its AGENTS.md / skill) and `min_quality_tier`.
- `task_types` - responsibility types, with required quality and budget.
- `role_task_types` - which role handles which responsibility.

## Selection rules (what the loader does)

1. Model with a key present in the environment -> included.
2. Model without a key -> skipped.
3. Model dead at runtime -> parked by LiteLLM cooldown.

Per-role ladder: among the models meeting the role's minimum quality, order free
first (cost asc) then best quality first, so good free models stay in the upper
layers and paid ones are the last resort.

## Usage

```bash
./svc up          # brings up the services (Postgres included)
./svc db-init     # load schema + sample data
./svc db-load     # generate config.yaml from the DB and restart the gateway
```

Fill only the keys you have in `.env`. Adding a model/provider/role is an `INSERT`
plus `./svc db-load` - no code changes.

Loader host requirement: `pip install "psycopg[binary]" pyyaml`.

## Security

Keys are not stored in the DB, only the name of their environment variable; the
secret lives in `.env`. A DB dump never exposes credentials.
