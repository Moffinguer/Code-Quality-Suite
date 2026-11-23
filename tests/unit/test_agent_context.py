"""Unit test: the one-developer-per-final-branch rule ships in the agent context files.

python3 -m unittest discover -s tests/unit -v
"""

import os
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEMPLATE = os.path.join(ROOT, "ai-template")
TEAM_FLOW = os.path.join(TEMPLATE, ".agents", "skills", "team-flow", "SKILL.md")
BRANCH_WORKFLOW = os.path.join(TEMPLATE, ".agents", "skills", "branch-workflow", "SKILL.md")
AGENTS = os.path.join(TEMPLATE, "AGENTS.md")


def read(path):
    """Return the text of a file.

    Args:
        path: absolute path of a UTF-8 file.

    Returns:
        The file content.

    Raises:
        OSError: when the file cannot be read.
    """
    with open(path, encoding="utf-8") as handle:
        return handle.read()


class ParallelRuleTest(unittest.TestCase):
    """The parallel development rule is present and the line limits hold."""

    def test_team_flow_has_rule(self):
        """team-flow states the per-branch, per-phase and dependency rules."""
        text = read(TEAM_FLOW)
        for word in ("one developer per final", "in parallel", "dependencies", "3-4 agents"):
            self.assertIn(word, text)

    def test_agents_lead_row(self):
        """The lead row of the AGENTS.md template states the rule."""
        text = read(AGENTS)
        self.assertIn("one developer per final branch", text)
        self.assertIn("dependencies are integrated", text)

    def test_branch_workflow_pointer(self):
        """branch-workflow points to team-flow for parallel work."""
        self.assertIn("one developer per final branch", read(BRANCH_WORKFLOW))

    def test_line_limits(self):
        """Both skills stay at 80 lines or fewer."""
        for path in (TEAM_FLOW, BRANCH_WORKFLOW):
            self.assertLessEqual(len(read(path).splitlines()), 80, path)


if __name__ == "__main__":
    unittest.main()
