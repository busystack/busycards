import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location("audit", pathlib.Path(__file__).parents[1] / "audit_dependencies.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class AuditTests(unittest.TestCase):
    def test_resolved_versions_and_pagination(self):
        queries = audit.coordinates("+- com.microsoft.azure:msal4j:jar:1.26.0:compile")
        responses = iter([{"results": [{"vulns": [{"id": "GHSA-test-fixture"}], "next_page_token": "fixture"}]},
                          {"results": [{}]}])
        self.assertEqual(audit.audit(queries, lambda _: next(responses)),
                         [("com.microsoft.azure:msal4j", "1.26.0", "GHSA-test-fixture")])

    def test_incomplete_or_unsafe_response_fails(self):
        queries = audit.coordinates("a:b:jar:1.0:runtime")
        for response in [{"results": []}, {"results": [{"vulns": [{"id": "private@example.test"}]}]}]:
            with self.assertRaises(ValueError):
                audit.audit(queries, lambda _: response)

    def test_no_empty_graph_or_infinite_pagination(self):
        with self.assertRaises(ValueError):
            audit.coordinates("")
        with self.assertRaises(ValueError):
            audit.audit(audit.coordinates("a:b:jar:1.0:test"),
                        lambda _: {"results": [{"next_page_token": "fixture"}]})


if __name__ == "__main__":
    unittest.main()
