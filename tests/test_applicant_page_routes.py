"""Page URLs must not collide with the Jac server's own endpoints.

In production one server answers both the app's pages and its API. A page whose
path the API also uses (the scheduler's /jobs, for example) is shadowed: opening or
refreshing it shows the API's JSON error instead of the app.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Built-in Jac server paths (see `jac guide reference/plugins/jac-scale-scheduler` and
# the server's /openapi.json).
RESERVED = {
    "jobs", "walker", "walkers", "function", "functions", "user", "sso", "api-key",
    "graph", "cl", "webhook", "ws", "admin", "healthz", "docs", "openapi.json", "static",
}


def page_paths() -> list[str]:
    paths = []
    for file in (ROOT / "pages").rglob("*.jac"):
        parts = [part for part in file.relative_to(ROOT / "pages").with_suffix("").parts
                 if not re.fullmatch(r"\(.*\)", part)]  # route groups add no URL segment
        if parts and parts[-1] in ("index", "layout"):
            parts = parts[:-1]
        paths.append("/" + "/".join(parts))
    return paths


class PageRouteTests(unittest.TestCase):
    def test_no_page_is_shadowed_by_a_server_endpoint(self):
        clashes = [path for path in page_paths() if path.strip("/").split("/")[0] in RESERVED]
        self.assertEqual(clashes, [], "These pages share a URL with a Jac server endpoint")

    def test_the_job_feed_has_a_page(self):
        self.assertIn("/find-jobs", page_paths())


if __name__ == "__main__":
    unittest.main()
