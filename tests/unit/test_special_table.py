"""Unit tests for the `branches.special` table (6.0.0 `table` task).

python3 -m unittest discover -s tests/unit -v

Covers the defaults, validation, the merge with project overrides, `"TYPE": false`, the shell
export (and its parity with `qs_policy_defaults`), the model 5 -> 6 migration and the schema.
"""

import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "engine"))

import policy  # noqa: E402
import rules  # noqa: E402

LIB = os.path.join(ROOT, "scripts", "git-flow-lib.sh").replace("\\", "/")
DUMP = 'for v in $(compgen -v QS_SP_); do printf "%s=%s\\n" "$v" "${!v}"; done'
ALL_TYPES = [
    "MIGRATION",
    "DOCS",
    "REFACTOR",
    "FORMAT",
    "TESTS",
    "SPIKE",
    "ATTEMPT",
    "REVIEW",
    "QUARANTINE",
    "CHECKPOINT",
]


def special(**types):
    """Rules data with a `branches.special` section.

    Args:
        **types: TYPE=value pairs (an object of properties, or False).

    Returns:
        dict: {"branches": {"special": types}}.
    """
    return {"branches": {"special": types}}


def errors_text(data):
    """All validation messages of a rules data, as one string.

    Args:
        data: the rules data.

    Returns:
        str: the messages joined with newlines.
    """
    return "\n".join(policy.validate(data))


class DefaultsTest(unittest.TestCase):
    """TB1: DEFAULTS holds the table of the spec."""

    def test_types_and_order(self):
        """The ten types are in the table, in order; TESTING is not (testing_leaf)."""
        table = policy.DEFAULTS["branches"]["special"]
        self.assertEqual(list(table), ALL_TYPES)
        self.assertNotIn("TESTING", table)
        self.assertEqual(policy.DEFAULTS["branches"]["testing_leaf"], "TESTING")

    def test_every_entry_has_every_property(self):
        """Each entry has exactly the properties of SPECIAL_PROPS and valid values."""
        for name, entry in policy.DEFAULTS["branches"]["special"].items():
            self.assertEqual(list(entry), list(policy.SPECIAL_PROPS), name)
        self.assertEqual(policy.validate({}), [])

    def test_default_values(self):
        """Spot checks of the default table, one per rule of the spec."""
        t = policy.DEFAULTS["branches"]["special"]
        self.assertEqual((t["MIGRATION"]["order"], t["MIGRATION"]["locks"]), ("first", True))
        self.assertEqual(t["MIGRATION"]["push_checks"], "full")
        self.assertNotIn("feat", t["MIGRATION"]["types"])
        self.assertNotIn("revert", t["MIGRATION"]["types"])
        self.assertEqual((t["DOCS"]["at"], t["DOCS"]["children"]), ("version", False))
        self.assertEqual((t["DOCS"]["paths"], t["DOCS"]["on_release"]), (["@docs"], "required"))
        self.assertEqual((t["REFACTOR"]["order"], t["REFACTOR"]["level"]), ("last", "strict"))
        self.assertEqual((t["FORMAT"]["order"], t["FORMAT"]["rebase"]), ("alone", False))
        self.assertEqual(t["TESTS"]["paths"], ["@tests"])
        self.assertEqual(t["SPIKE"]["on_release"], "delete")
        self.assertEqual((t["ATTEMPT"]["suffix"], t["ATTEMPT"]["integrates"]), ("n", "choose"))
        self.assertEqual(t["QUARANTINE"]["trailers"], ["Generated-by"])
        self.assertEqual((t["CHECKPOINT"]["push"], t["CHECKPOINT"]["level"]), ("never", "format"))
        self.assertEqual({t[n]["at"] for n in ("ATTEMPT", "REVIEW", "QUARANTINE")}, {"task"})
        self.assertEqual(policy.DEFAULTS["branches"]["model"], 6)

    def test_defaults_not_shared(self):
        """get() and special_table() return copies: changing them never changes DEFAULTS."""
        before = copy.deepcopy(policy.DEFAULTS)
        policy.get({}, "branches")["special"]["DOCS"]["paths"].append("x")
        policy.special_table({})["TESTS"]["paths"].append("y")
        self.assertEqual(policy.DEFAULTS, before)


class ValidateTest(unittest.TestCase):
    """TB1: validate rejects what the spec says."""

    def test_unknown_type(self):
        """HOTFIX (out of scope), a lower-case type and a misspelling are unknown types."""
        for name in ("HOTFIX", "REPRO", "BACKPORT", "docs", "TESTING"):
            text = errors_text(special(**{name: {}}))
            self.assertIn(f"branches.special.{name}: unknown type", text)

    def test_unknown_property(self):
        """A property that is not in the table is refused (parent, from, tree, tests: repro)."""
        for prop in ("parent", "from", "tree", "tests"):
            text = errors_text(special(DOCS={prop: "x"}))
            self.assertIn(f"branches.special.DOCS.{prop}: unknown property", text)

    def test_bad_values(self):
        """Each kind of property reports a bad value."""
        bad = {
            "at": "root",
            "children": "yes",
            "suffix": "x",
            "integrates": "merge",
            "order": "after_children",
            "types": "feat",
            "paths": ["@nothing"],
            "level": "max",
            "push_checks": "all",
            "trailers": ["Bad Name"],
            "locks": 1,
            "on_release": "maybe",
            "changelog": "all",
        }
        for prop, val in bad.items():
            text = errors_text(special(TESTS={prop: val}))
            self.assertIn(f"branches.special.TESTS.{prop}:", text, prop)

    def test_bad_entry_kinds(self):
        """A type must be an object, true or false; the table must be an object."""
        self.assertIn("must be an object, true or false", errors_text(special(DOCS="off")))
        self.assertIn(
            "branches.special: must be an object", errors_text({"branches": {"special": []}})
        )

    def test_good_values(self):
        """Valid overrides pass: null level, [] paths, ['*'] types, own globs, true."""
        data = special(
            TESTS={"paths": ["qa/**", "@tests"], "level": None, "types": ["*"]},
            SPIKE={"paths": [], "trailers": ["Spike-of"]},
            DOCS=True,
        )
        self.assertEqual(policy.validate(data), [])

    def test_paths_inside_repository(self):
        """Absolute paths, '..' and backslashes are refused in paths."""
        for path in ("/etc/**", "../x", "a\\b", ""):
            self.assertIn("paths", errors_text(special(TESTS={"paths": [path]})), path)

    def test_not_configurable(self):
        """FORMAT rebase, ATTEMPT integrates and CHECKPOINT push cannot change."""
        cases = (("FORMAT", "rebase", True), ("ATTEMPT", "integrates", "squash"))
        for name, prop, val in (*cases, ("CHECKPOINT", "push", "normal")):
            text = errors_text(special(**{name: {prop: val}}))
            self.assertIn(f"branches.special.{name}.{prop}: not configurable", text)

    def test_fixed_value_restated(self):
        """Writing the fixed value itself is accepted (a rules file may list the whole entry)."""
        data = special(FORMAT={"rebase": False}, CHECKPOINT={"push": "never"})
        self.assertEqual(policy.validate(data), [])

    def test_full_default_table_is_valid(self):
        """The whole default table, as populate writes it, validates."""
        data = {"branches": {"special": copy.deepcopy(policy.SPECIAL_DEFAULTS)}}
        self.assertEqual(policy.validate(data), [])

    def test_name_clash_with_leaves(self):
        """A type named like parent_leaf, release_leaf or testing_leaf (any case) is refused."""
        for key, val in (
            ("testing_leaf", "docs"),
            ("parent_leaf", "Migration"),
            ("release_leaf", "REFACTOR"),
        ):
            text = errors_text({"branches": {key: val}})
            self.assertIn(f"branches.{key}: must differ from the special type", text, key)

    def test_disabled_type_does_not_clash(self):
        """A disabled type is not reserved, so its name can be a leaf."""
        data = {"branches": {"testing_leaf": "docs", "special": {"DOCS": False}}}
        self.assertEqual(policy.validate(data), [])


class DisableAndMergeTest(unittest.TestCase):
    """TB2: false disables a type; an override is merged over the defaults."""

    def test_disable_format(self):
        """ "FORMAT": false is valid and FORMAT leaves the table and the names."""
        data = special(FORMAT=False)
        self.assertEqual(policy.validate(data), [])
        self.assertNotIn("FORMAT", policy.special_names(data))
        self.assertEqual(policy.special_names(data), [n for n in ALL_TYPES if n != "FORMAT"])
        env = policy.special_env(data)
        self.assertNotIn("FORMAT", env["QS_SP_NAMES"].split())
        self.assertFalse([k for k in env if k.startswith("QS_SP_FORMAT_")])
        self.assertIn("QS_SP_DOCS_AT", env)

    def test_override_merged(self):
        """TESTS paths override; its other properties stay at the defaults."""
        data = special(TESTS={"paths": ["qa/**"]})
        tests = policy.special_table(data)["TESTS"]
        self.assertEqual(tests["paths"], ["qa/**"])
        self.assertEqual(tests["types"], ["test", "chore"])
        self.assertEqual(tests["integrates"], "squash")
        self.assertEqual(policy.special_env(data)["QS_SP_TESTS_PATHS"], "qa/**")
        self.assertEqual(policy.special_table(data)["DOCS"], policy.SPECIAL_DEFAULTS["DOCS"])

    def test_empty_and_true_mean_defaults(self):
        """An empty object and true leave the type as it is."""
        data = special(DOCS={}, REFACTOR=True)
        table = policy.special_table(data)
        self.assertEqual(table["DOCS"], policy.SPECIAL_DEFAULTS["DOCS"])
        self.assertEqual(table["REFACTOR"], policy.SPECIAL_DEFAULTS["REFACTOR"])

    def test_malformed_table_gives_defaults(self):
        """A non-object `special` does not break the readers; validate reports it."""
        data = {"branches": {"special": "x"}}
        self.assertEqual(policy.special_names(data), ALL_TYPES)
        self.assertTrue(policy.validate(data))

    def test_other_branch_keys_kept(self):
        """get() still merges the other keys of the section."""
        br = policy.get({"branches": {"mainline": "trunk", "special": {"DOCS": False}}}, "branches")
        self.assertEqual(br["mainline"], "trunk")
        self.assertIs(br["special"]["DOCS"], False)
        self.assertEqual(br["special"]["TESTS"], policy.SPECIAL_DEFAULTS["TESTS"])

    def test_expand_paths(self):
        """@docs, @tests and @repo-files expand to globs; other items pass; no duplicates."""
        docs = policy.expand_paths(["@docs"])
        self.assertIn("docs/**", docs)
        self.assertIn("CITATION.cff", docs)
        self.assertNotIn("VERSION", docs)
        self.assertIn("src/test/**", policy.expand_paths(["@tests"]))
        self.assertEqual(policy.expand_paths(["qa/**", "qa/**"]), ["qa/**"])
        self.assertEqual(len(policy.expand_paths(["@docs", "@repo-files"])), len(docs))


class ShellEnvTest(unittest.TestCase):
    """TB3: the shell export and its parity with qs_policy_defaults."""

    def test_names_and_variables(self):
        """QS_SP_NAMES lists the enabled types; every type has QS_SP_<TYPE>_<PROP>."""
        env = policy.shell_env({})
        self.assertIn("QS_SP_NAMES='" + " ".join(ALL_TYPES) + "'\n", env)
        self.assertIn("QS_SP_DOCS_PATHS='@docs'\n", env)
        self.assertIn("QS_SP_MIGRATION_LOCKS='1'\n", env)
        self.assertIn("QS_SP_FORMAT_REBASE='0'\n", env)
        self.assertIn("QS_SP_DOCS_LEVEL=''\n", env)
        self.assertIn("QS_SP_TESTS_TYPES='test|chore'\n", env)
        self.assertIn("QS_SP_QUARANTINE_TRAILERS='Generated-by'\n", env)
        self.assertIn("QS_SP_CHECKPOINT_PUSH='never'\n", env)
        self.assertIn("QS_BR_TESTING='TESTING'\n", env)
        count = sum(1 for k in policy.special_env({}) if k != "QS_SP_NAMES")
        self.assertEqual(count, len(ALL_TYPES) * len(policy.SPECIAL_PROPS))

    def test_override_exported(self):
        """A project override reaches the export; a disabled type does not."""
        env = policy.shell_env(special(TESTS={"paths": ["qa/**"]}, FORMAT=False))
        self.assertIn("QS_SP_TESTS_PATHS='qa/**'\n", env)
        self.assertNotIn("QS_SP_FORMAT_", env)

    def dump(self, script, *args):
        """Run a bash snippet that sources the lib and prints every QS_SP_* variable.

        Args:
            script: bash code run after `. git-flow-lib.sh`.
            *args: positional parameters of the snippet.

        Returns:
            dict[str, str]: variable -> value.
        """
        code = f'. "{LIB}"; {script}; {DUMP}'
        res = subprocess.run(
            ["bash", "-c", code, "bash", *args], capture_output=True, text=True, check=True
        )
        pairs = (line.split("=", 1) for line in res.stdout.splitlines() if "=" in line)
        return {k: v for k, v in pairs}

    @unittest.skipUnless(shutil.which("bash"), "bash is required")
    def test_shell_defaults_match(self):
        """qs_policy_defaults sets the same QS_SP_* values as the engine export."""
        with tempfile.TemporaryDirectory() as d:
            env_file = os.path.join(d, "policy.env").replace("\\", "/")
            with open(env_file, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(policy.shell_env({}))
            from_lib = self.dump("qs_policy_defaults")
            from_env = self.dump('. "$1"', env_file)
        self.assertEqual(from_lib, from_env)
        self.assertEqual(from_lib, policy.special_env({}))

    @unittest.skipUnless(shutil.which("bash"), "bash is required")
    def test_policy_env_overrides_defaults(self):
        """Loading an override on top of the defaults changes the value and the names."""
        data = special(TESTS={"paths": ["qa/**"]}, FORMAT=False)
        with tempfile.TemporaryDirectory() as d:
            env_file = os.path.join(d, "policy.env").replace("\\", "/")
            with open(env_file, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(policy.shell_env(data))
            got = self.dump('qs_policy_defaults; . "$1"', env_file)
        self.assertEqual(got["QS_SP_TESTS_PATHS"], "qa/**")
        self.assertNotIn("FORMAT", got["QS_SP_NAMES"].split())

    @unittest.skipUnless(shutil.which("bash"), "bash is required")
    def test_merge_flow_refuses(self):
        """TB6: with branches.flow = merge the guard refuses; with squash it passes."""
        code = f'. "{LIB}"; qs_policy_defaults; QS_BR_FLOW=$1; qs_special_need_squash'
        run = [
            subprocess.run(
                ["bash", "-c", code, "bash", flow], capture_output=True, text=True, check=False
            )
            for flow in ("merge", "squash")
        ]
        self.assertEqual(run[0].returncode, 1)
        self.assertIn("special branches need the squash flow", run[0].stderr)
        self.assertEqual(run[1].returncode, 0)
        self.assertEqual(run[1].stderr, "")


def file_5():
    """A model 5 rules file as 5.0.0-RC1 wrote it: no special table, model 5.

    Returns:
        dict: the rules data.
    """
    br = copy.deepcopy(policy.DEFAULTS["branches"])
    del br["special"]
    br["model"] = 5
    return {"branches": br}


class MigrateTest(unittest.TestCase):
    """TB4: the model 5 -> 6 step."""

    def test_model_5_file(self):
        """A model 5 file gets DOCS.on_release optional, model 6 and the notice."""
        data = file_5()
        msgs = policy.migrate(data)
        br = data["branches"]
        self.assertEqual(br["special"], {"DOCS": {"on_release": "optional"}})
        self.assertEqual(br["model"], 6)
        self.assertEqual(sum(policy.DOCS_NOTICE in m for m in msgs), 1)
        self.assertFalse(any(policy.FLOW_NOTICE in m for m in msgs))
        self.assertEqual(br["flow"], "squash")
        self.assertEqual(policy.validate(data), [])

    def test_second_run_silent(self):
        """A second run changes nothing and prints nothing."""
        data = file_5()
        policy.migrate(data)
        before = copy.deepcopy(data)
        self.assertEqual(policy.migrate(data), [])
        self.assertEqual(data, before)

    def test_effective_mode_after_migration(self):
        """After populate the migrated file keeps optional; the other types come from defaults."""
        data = file_5()
        policy.migrate(data)
        policy.populate(data)
        self.assertEqual(policy.special_table(data)["DOCS"]["on_release"], "optional")
        self.assertEqual(policy.special_table(data)["TESTS"], policy.SPECIAL_DEFAULTS["TESTS"])
        self.assertEqual(data["branches"]["special"], {"DOCS": {"on_release": "optional"}})

    def test_new_file_gets_required(self):
        """A new file gets the whole table with DOCS required, and no migration notice."""
        data = rules.skeleton("x")
        self.assertEqual(data["branches"]["special"]["DOCS"]["on_release"], "required")
        self.assertEqual(data["branches"]["model"], 6)
        self.assertEqual(policy.migrate(data), [])
        self.assertEqual(data["branches"]["special"], policy.SPECIAL_DEFAULTS)

    def test_4x_goes_through_5_then_6(self):
        """A 4.x file (no model) gets flow merge, the 5 changes, then the 6 step."""
        data = file_5()
        for key in ("model", "flow", "ot_ref", "testing_leaf"):
            del data["branches"][key]
        data["branches"]["levels"][1] = r"^[0-9]+$"
        msgs = policy.migrate(data)
        br = data["branches"]
        self.assertEqual((br["model"], br["flow"], br["levels"][1]), (6, "merge", policy.OT_RX))
        self.assertEqual(br["special"]["DOCS"]["on_release"], "optional")
        text = "\n".join(msgs)
        self.assertLess(text.index("branches.model: 5"), text.index("DOCS.on_release"))
        self.assertTrue(any(policy.FLOW_NOTICE in m for m in msgs))
        self.assertTrue(any(policy.DOCS_NOTICE in m for m in msgs))

    def test_project_values_kept(self):
        """An on_release already chosen and a disabled DOCS are not touched."""
        data = file_5()
        data["branches"]["special"] = {"DOCS": {"on_release": "required"}}
        self.assertFalse(any(policy.DOCS_NOTICE in m for m in policy.migrate(data)))
        self.assertEqual(data["branches"]["special"]["DOCS"]["on_release"], "required")
        data = file_5()
        data["branches"]["special"] = {"DOCS": False}
        policy.migrate(data)
        self.assertIs(data["branches"]["special"]["DOCS"], False)
        self.assertEqual(data["branches"]["model"], 6)

    def test_own_special_entries_kept(self):
        """Other entries of an existing special table stay; DOCS is added beside them."""
        data = file_5()
        data["branches"]["special"] = {"TESTS": {"paths": ["qa/**"]}}
        policy.migrate(data)
        self.assertEqual(data["branches"]["special"]["TESTS"], {"paths": ["qa/**"]})
        self.assertEqual(data["branches"]["special"]["DOCS"], {"on_release": "optional"})

    def test_populate_writes_whole_table_once(self):
        """A file without `special` (model already 6) gets the whole table; nothing overwritten."""
        data = {"branches": {"model": 6}}
        self.assertIn("branches.special", policy.populate(data))
        self.assertEqual(data["branches"]["special"], policy.SPECIAL_DEFAULTS)
        data["branches"]["special"]["DOCS"] = False
        self.assertNotIn("branches.special", policy.populate(data))
        self.assertIs(data["branches"]["special"]["DOCS"], False)


class SchemaTest(unittest.TestCase):
    """TB5: the generated schema describes branches.special."""

    def setUp(self):
        """Load the generated schema."""
        path = os.path.join(ROOT, "schema", "quality-rules.schema.json")
        with open(path, encoding="utf-8") as fh:
            self.schema = json.load(fh)

    def test_special_in_schema(self):
        """One entry per type, each false or an object with every property and its default."""
        sp = self.schema["properties"]["branches"]["properties"]["special"]
        self.assertEqual(list(sp["properties"]), ALL_TYPES)
        self.assertFalse(sp["additionalProperties"])
        for name, entry in sp["properties"].items():
            self.assertEqual(entry["oneOf"][0], {"const": False})
            props = entry["oneOf"][1]["properties"]
            self.assertEqual(list(props), list(policy.SPECIAL_PROPS), name)
            for prop, sch in props.items():
                self.assertEqual(sch["default"], policy.SPECIAL_DEFAULTS[name][prop])

    def test_model_default(self):
        """The model default in the schema is the current one."""
        br = self.schema["properties"]["branches"]["properties"]
        self.assertEqual(br["model"]["default"], 6)

    def test_docs_mention_special(self):
        """docs/QUALITY-RULES.md describes branches.special and its properties."""
        with open(os.path.join(ROOT, "docs", "QUALITY-RULES.md"), encoding="utf-8") as fh:
            text = fh.read()
        self.assertIn("branches.special", text)
        for prop in policy.SPECIAL_PROPS:
            self.assertIn(f"`{prop}`", text)


if __name__ == "__main__":
    unittest.main()
