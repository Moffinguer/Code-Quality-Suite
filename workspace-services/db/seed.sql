-- Seed data. Adjust to your real providers/keys.
-- quality_tier: 5=frontier, 4=very good, 3=good, 2=medium, 1=light.

-- Providers
INSERT INTO providers (name, litellm_prefix, category, base_url, requires_key, notes) VALUES
 ('gemini',    'gemini/',    'free',  NULL, TRUE,  'Cuota por proyecto, no por key. Contexto grande.'),
 ('groq',      'groq/',      'free',  NULL, TRUE,  'Muy rapido. TPM bajo (12k) en free.'),
 ('cerebras',  'cerebras/',  'free',  NULL, TRUE,  '~1M tokens/dia. Catalogo volatil.'),
 ('openrouter','openrouter/','free',  NULL, TRUE,  'Agregador. 50 req/dia free.'),
 ('github',    'github/',    'free',  NULL, TRUE,  'Prototipado. PAT.'),
 ('nvidia',    'nvidia_nim/','free',  NULL, TRUE,  '40 RPM. Verificacion telefono.'),
 ('mistral',   'mistral/',   'free',  NULL, TRUE,  'Coding. Opt-in a training.'),
 ('deepseek',  'deepseek/',  'paid',  NULL, TRUE,  'Baratisimo. Sin limites de free.'),
 ('anthropic', 'anthropic/', 'paid',  NULL, TRUE,  'Calidad alta.'),
 ('ollama',    'ollama/',    'local', 'http://host.docker.internal:11434', FALSE, 'Local, ilimitado.')
ON CONFLICT (name) DO NOTHING;

-- Keys (environment-variable reference)
INSERT INTO api_keys (provider_id, env_var, label) VALUES
 ((SELECT id FROM providers WHERE name='gemini'),    'GEMINI_API_KEY',    'personal'),
 ((SELECT id FROM providers WHERE name='groq'),      'GROQ_API_KEY',      'personal'),
 ((SELECT id FROM providers WHERE name='cerebras'),  'CEREBRAS_API_KEY',  'personal'),
 ((SELECT id FROM providers WHERE name='openrouter'),'OPENROUTER_API_KEY','personal'),
 ((SELECT id FROM providers WHERE name='github'),    'GITHUB_API_KEY',    'personal'),
 ((SELECT id FROM providers WHERE name='nvidia'),    'NVIDIA_NIM_API_KEY','personal'),
 ((SELECT id FROM providers WHERE name='mistral'),   'MISTRAL_API_KEY',   'personal'),
 ((SELECT id FROM providers WHERE name='deepseek'),  'DEEPSEEK_API_KEY',  'personal'),
 ((SELECT id FROM providers WHERE name='anthropic'), 'ANTHROPIC_API_KEY', 'personal')
ON CONFLICT DO NOTHING;

-- Models (slug = what follows the LiteLLM prefix)
INSERT INTO models (provider_id, slug, alias, quality_tier, context_window, cost_in_mtok, cost_out_mtok, supports_tools, priority) VALUES
 ((SELECT id FROM providers WHERE name='gemini'),   'gemini-3.5-flash',          'gemini-35',  5, 1000000, 0, 0, TRUE, 10),
 ((SELECT id FROM providers WHERE name='gemini'),   'gemini-2.5-flash',          'gemini-25',  4, 1000000, 0, 0, TRUE, 20),
 ((SELECT id FROM providers WHERE name='gemini'),   'gemini-2.5-flash-lite',     'gemini-l25', 2, 1000000, 0, 0, TRUE, 60),
 ((SELECT id FROM providers WHERE name='cerebras'), 'gpt-oss-120b',              'cere-oss',   4, 128000,  0, 0, TRUE, 15),
 ((SELECT id FROM providers WHERE name='groq'),     'openai/gpt-oss-120b',       'groq-oss',   4, 128000,  0, 0, TRUE, 25),
 ((SELECT id FROM providers WHERE name='groq'),     'llama-3.3-70b-versatile',   'groq-l70',   3, 128000,  0, 0, TRUE, 30),
 ((SELECT id FROM providers WHERE name='groq'),     'llama-3.1-8b-instant',      'groq-l8',    1, 128000,  0, 0, TRUE, 80),
 ((SELECT id FROM providers WHERE name='openrouter'),'deepseek/deepseek-r1:free','or-r1',      4, 64000,   0, 0, TRUE, 35),
 ((SELECT id FROM providers WHERE name='github'),   'gpt-4o-mini',               'gh-4omini',  3, 128000,  0, 0, TRUE, 40),
 ((SELECT id FROM providers WHERE name='mistral'),  'codestral-latest',          'mistral-cod',3, 256000,  0, 0, TRUE, 45),
 ((SELECT id FROM providers WHERE name='deepseek'), 'deepseek-chat',             'ds-chat',    4, 128000,  0.27, 1.10, TRUE, 200),
 ((SELECT id FROM providers WHERE name='anthropic'),'claude-sonnet-4-5',         'claude-son', 5, 200000,  3.0, 15.0, TRUE, 210),
 ((SELECT id FROM providers WHERE name='ollama'),   'qwen2.5-coder:14b',         'local-qwen', 2, 32000,   0, 0, TRUE, 300)
ON CONFLICT (provider_id, slug) DO NOTHING;

-- Agent roles (hierarchy)
INSERT INTO agent_roles (name, level, min_quality_tier, prefer_free, description, system_prompt) VALUES
 ('orchestrator', 0, 4, TRUE,  'Planifica, divide en tareas, asigna y revisa. No escribe codigo masivo.',
   'Eres el orquestador. Entiende el producto, divide en subtareas con dependencias, asigna cada una al rol adecuado y valida resultados. No escribas codigo extenso: delega.'),
 ('architect',    1, 4, TRUE,  'Decisiones de arquitectura, BD, seguridad.',
   'Eres arquitecto. Decide estructura, patrones y contratos. Salida concisa y justificada. No implementes: define.'),
 ('backend',      2, 3, TRUE,  'Implementacion Java/Spring/REST/JPA.',
   'Eres desarrollador backend. Implementa segun el contrato dado. Sigue AGENTS.md. Codigo que pase el gate de calidad.'),
 ('frontend',     2, 3, TRUE,  'Implementacion TS/React/CSS/HTML.',
   'Eres desarrollador frontend. Implementa la UI segun el diseno. Sigue AGENTS.md.'),
 ('boilerplate',  3, 1, TRUE,  'DTOs, getters, tests, docs, refactors mecanicos, SQL, boilerplate.',
   'Generas codigo repetitivo y mecanico (DTOs, tests, docs, migraciones). Rapido y literal. No tomes decisiones de diseno.')
ON CONFLICT (name) DO NOTHING;

-- Responsibility types
INSERT INTO task_types (name, required_quality_tier, complexity, max_tokens, description) VALUES
 ('architecture',   4, 'critical', 50000,  'Decidir estructura del sistema'),
 ('implement-api',  3, 'high',     80000,  'Implementar endpoints/servicios'),
 ('implement-ui',   3, 'medium',   60000,  'Implementar componentes de UI'),
 ('write-tests',    2, 'low',      120000, 'Generar tests unitarios'),
 ('generate-dto',   1, 'low',      40000,  'Generar DTOs/getters/boilerplate'),
 ('write-docs',     1, 'low',      40000,  'Documentacion y README'),
 ('refactor',       2, 'medium',   60000,  'Refactor mecanico')
ON CONFLICT (name) DO NOTHING;

-- Which role handles which responsibility
INSERT INTO role_task_types (role_id, task_type_id)
SELECT r.id, t.id FROM agent_roles r, task_types t WHERE
   (r.name='orchestrator' AND t.name='architecture')
 OR (r.name='architect'   AND t.name='architecture')
 OR (r.name='backend'     AND t.name IN ('implement-api','refactor'))
 OR (r.name='frontend'    AND t.name IN ('implement-ui','refactor'))
 OR (r.name='boilerplate' AND t.name IN ('write-tests','generate-dto','write-docs'))
ON CONFLICT DO NOTHING;
