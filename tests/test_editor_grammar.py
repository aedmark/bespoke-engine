import json
import re
import unittest

from tools import build_editor_grammar as generator


class EditorGrammarTests(unittest.TestCase):
    def setUp(self):
        self.lexer = generator.LEXER.read_text(encoding="utf-8")
        self.text = generator.GRAMMAR.read_text(encoding="utf-8")
        self.grammar = json.loads(self.text)
        self.patterns = {rule["name"]: rule for rule in self.grammar["patterns"]}

    def test_extension_registers_the_grammar_for_bespoke_files(self):
        extension_dir = generator.GRAMMAR.parents[1]
        manifest = json.loads((extension_dir / "package.json").read_text(encoding="utf-8"))
        contributions = manifest["contributes"]
        language, = contributions["languages"]
        grammar, = contributions["grammars"]
        self.assertIn(".bespoke", language["extensions"])
        self.assertEqual(language["id"], grammar["language"])
        self.assertEqual(self.grammar["scopeName"], grammar["scopeName"])
        self.assertEqual(generator.GRAMMAR, (extension_dir / grammar["path"]).resolve())
        self.assertNotIn("main", manifest)
        self.assertNotIn("browser", manifest)

    def test_generated_grammar_covers_every_keyword_spelling(self):
        # Read the table independently of the generator's line parser, including aliases.
        table = self.lexer.split("pub fn keyword_map()", 1)[1].split("fn resolve_keyword", 1)[0]
        spellings = set(re.findall(r'"([^"]+)"\s*,\s*\.kw_[a-z0-9_]+', table))
        self.assertTrue({"say", "says", "toward", "towards"} <= spellings)
        keyword = self.patterns["keyword.other.bespoke"]["match"]
        for word in spellings:
            with self.subTest(word=word):
                self.assertIsNotNone(re.fullmatch(keyword, word))
        self.assertEqual(self.text, generator.render(sorted(spellings)))

    def test_keyword_rule_does_not_split_name_prefixes(self):
        keyword = re.compile(self.patterns["keyword.other.bespoke"]["match"])
        for name in ("walkway", "walk-toward", "wait_2", "Wait"):
            with self.subTest(name=name):
                self.assertIsNone(keyword.match(name))
        # A full identifier starts earlier than the potential keyword inside it.
        ident = re.compile(self.patterns["variable.other.bespoke"]["match"])
        self.assertEqual("Look-toward", ident.match("Look-toward").group())

    def test_unfamiliar_keyword_map_row_fails_instead_of_silently_omitting_it(self):
        modified = self.lexer.replace('.{ "walk", .kw_walk },', '.{ keyword_constant, .kw_walk },')
        with self.assertRaisesRegex(ValueError, "unsupported lexer keyword row"):
            generator.read_keywords(modified)
