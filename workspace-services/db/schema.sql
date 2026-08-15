-- Schema: model catalog + keys + agent/responsibility hierarchy.
-- The loader (generate_config.py) reads it and generates the orchestrator config.

CREATE TABLE IF NOT EXISTS providers (
  id             SERIAL PRIMARY KEY,
  name           TEXT UNIQUE NOT NULL,                 -- 'groq', 'gemini'
  litellm_prefix TEXT NOT NULL,                        -- 'groq/', 'gemini/'
  base_url       TEXT,                                 -- para OpenAI-compatibles
  category       TEXT NOT NULL CHECK (category IN ('free','trial','paid','local')),
  requires_key   BOOLEAN NOT NULL DEFAULT TRUE,
  notes          TEXT
);

-- Keys by environment-variable reference (the secret is never stored in clear).
CREATE TABLE IF NOT EXISTS api_keys (
  id          SERIAL PRIMARY KEY,
  provider_id INT NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  env_var     TEXT NOT NULL,                           -- 'GROQ_API_KEY'
  label       TEXT,                                    -- 'personal', 'proyecto-x'
  enabled     BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (provider_id, env_var)
);

CREATE TABLE IF NOT EXISTS models (
  id             SERIAL PRIMARY KEY,
  provider_id    INT NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  slug           TEXT NOT NULL,                        -- tras el prefijo: 'llama-3.3-70b-versatile'
  alias          TEXT UNIQUE NOT NULL,                 -- nombre en LiteLLM: 'groq-llama70'
  quality_tier   INT NOT NULL CHECK (quality_tier BETWEEN 1 AND 5),  -- 5 = best
  context_window INT,
  rpm INT, rpd INT, tpm INT, tpd INT,                  -- known quotas (informational)
  cost_in_mtok   NUMERIC NOT NULL DEFAULT 0,           -- input cost per Mtok (0 = free)
  cost_out_mtok  NUMERIC NOT NULL DEFAULT 0,
  supports_tools BOOLEAN NOT NULL DEFAULT TRUE,        -- required for editing agents
  priority       INT NOT NULL DEFAULT 100,             -- ladder tie-break (lower = earlier)
  enabled        BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (provider_id, slug)
);

-- Agent hierarchy: level 0 orchestrator ... 3 cheap/local worker.
CREATE TABLE IF NOT EXISTS agent_roles (
  id               SERIAL PRIMARY KEY,
  name             TEXT UNIQUE NOT NULL,               -- 'orchestrator','architect','java-worker'
  level            INT NOT NULL CHECK (level BETWEEN 0 AND 3),
  description      TEXT,
  system_prompt    TEXT,                               -- the role's specific AGENTS.md / skill
  min_quality_tier INT NOT NULL DEFAULT 1,             -- minimum model quality it may use
  prefer_free      BOOLEAN NOT NULL DEFAULT TRUE,      -- free first even in upper layers
  enabled          BOOLEAN NOT NULL DEFAULT TRUE
);

-- Responsibility / task types.
CREATE TABLE IF NOT EXISTS task_types (
  id                    SERIAL PRIMARY KEY,
  name                  TEXT UNIQUE NOT NULL,          -- 'architecture','generate-dto','write-tests'
  required_quality_tier INT NOT NULL DEFAULT 1,
  complexity            TEXT NOT NULL CHECK (complexity IN ('low','medium','high','critical')),
  max_tokens            INT,                           -- per-task budget
  description           TEXT
);

-- Which roles handle which responsibilities (N:M).
CREATE TABLE IF NOT EXISTS role_task_types (
  role_id      INT NOT NULL REFERENCES agent_roles(id) ON DELETE CASCADE,
  task_type_id INT NOT NULL REFERENCES task_types(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, task_type_id)
);

-- View: available models = enabled and keyed (or local).
-- The 'key present in the environment' check is done by the loader.
CREATE OR REPLACE VIEW v_models AS
SELECT m.*, p.name AS provider, p.litellm_prefix, p.base_url, p.category,
       p.requires_key,
       (SELECT ak.env_var FROM api_keys ak
         WHERE ak.provider_id = p.id AND ak.enabled LIMIT 1) AS env_var
FROM models m JOIN providers p ON p.id = m.provider_id
WHERE m.enabled;
