-- =============================================================================
-- Esquema: catalogo de modelos + claves + jerarquia de agentes/responsabilidades.
-- El cargador (generate_config.py) lo lee y genera la config del orquestador.
-- =============================================================================

CREATE TABLE IF NOT EXISTS providers (
  id             SERIAL PRIMARY KEY,
  name           TEXT UNIQUE NOT NULL,                 -- 'groq', 'gemini'
  litellm_prefix TEXT NOT NULL,                        -- 'groq/', 'gemini/'
  base_url       TEXT,                                 -- para OpenAI-compatibles
  category       TEXT NOT NULL CHECK (category IN ('free','trial','paid','local')),
  requires_key   BOOLEAN NOT NULL DEFAULT TRUE,
  notes          TEXT
);

-- Claves por referencia a variable de entorno (NO se guarda el secreto en claro).
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
  quality_tier   INT NOT NULL CHECK (quality_tier BETWEEN 1 AND 5),  -- 5 = mejor
  context_window INT,
  rpm INT, rpd INT, tpm INT, tpd INT,                  -- cuotas conocidas (informativo)
  cost_in_mtok   NUMERIC NOT NULL DEFAULT 0,           -- coste €/M tokens entrada (0 = gratis)
  cost_out_mtok  NUMERIC NOT NULL DEFAULT 0,
  supports_tools BOOLEAN NOT NULL DEFAULT TRUE,        -- necesario para agentes que editan
  priority       INT NOT NULL DEFAULT 100,             -- desempate en la escalera (menor = antes)
  enabled        BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (provider_id, slug)
);

-- Jerarquia de agentes: nivel 0 orquestador ... 3 worker barato/local.
CREATE TABLE IF NOT EXISTS agent_roles (
  id               SERIAL PRIMARY KEY,
  name             TEXT UNIQUE NOT NULL,               -- 'orchestrator','architect','java-worker'
  level            INT NOT NULL CHECK (level BETWEEN 0 AND 3),
  description      TEXT,
  system_prompt    TEXT,                               -- el "AGENTS.md especifico" / skill del rol
  min_quality_tier INT NOT NULL DEFAULT 1,             -- calidad minima de modelo que puede usar
  prefer_free      BOOLEAN NOT NULL DEFAULT TRUE,      -- gratis primero aunque sea capa alta
  enabled          BOOLEAN NOT NULL DEFAULT TRUE
);

-- Tipos de responsabilidad / tarea.
CREATE TABLE IF NOT EXISTS task_types (
  id                    SERIAL PRIMARY KEY,
  name                  TEXT UNIQUE NOT NULL,          -- 'architecture','generate-dto','write-tests'
  required_quality_tier INT NOT NULL DEFAULT 1,
  complexity            TEXT NOT NULL CHECK (complexity IN ('low','medium','high','critical')),
  max_tokens            INT,                           -- presupuesto por tarea
  description           TEXT
);

-- Que roles atienden que responsabilidades (N:M).
CREATE TABLE IF NOT EXISTS role_task_types (
  role_id      INT NOT NULL REFERENCES agent_roles(id) ON DELETE CASCADE,
  task_type_id INT NOT NULL REFERENCES task_types(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, task_type_id)
);

-- Vista: modelos disponibles = habilitados y con clave (o locales).
-- La comprobacion de "clave presente en el entorno" la hace el cargador.
CREATE OR REPLACE VIEW v_models AS
SELECT m.*, p.name AS provider, p.litellm_prefix, p.base_url, p.category,
       p.requires_key,
       (SELECT ak.env_var FROM api_keys ak
         WHERE ak.provider_id = p.id AND ak.enabled LIMIT 1) AS env_var
FROM models m JOIN providers p ON p.id = m.provider_id
WHERE m.enabled;
