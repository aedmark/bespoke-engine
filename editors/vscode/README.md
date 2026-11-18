# BeSpoke Language

Highlights `.bespoke` scripts in Visual Studio Code. The extension ships a TextMate grammar and runs no extension code. It does not validate scripts; use `bespoke check` for compiler diagnostics.

## Try it from the engine checkout

From the repository root, open VS Code's Extension Development Host with a sample:

```bash
code --extensionDevelopmentPath="$PWD/editors/vscode" scenarios/tavern_heist.bespoke
```

The language indicator should read **BeSpoke**. Open the command palette and run **Developer: Inspect Editor Tokens and Scopes** to inspect a keyword, string, or comment.

## Install in your regular editor

With the [VS Code packaging tool](https://code.visualstudio.com/api/working-with-extensions/publishing-extension#packaging-extensions) (`vsce`) installed, run these commands from the engine root in a Unix shell:

```bash
bespoke_extension_tmp=$(mktemp -d)
cp -R editors/vscode "$bespoke_extension_tmp/bespoke-language"
cp LICENSE "$bespoke_extension_tmp/bespoke-language/LICENSE"
cd "$bespoke_extension_tmp/bespoke-language"
vsce package --out bespoke-language.vsix
code --install-extension bespoke-language.vsix
```

You can also use **Extensions: Install from VSIX** in the command palette and select that file. There is no Marketplace install step. For other TextMate-compatible editors, the grammar is `syntaxes/bespoke.tmLanguage.json` with scope `source.bespoke`.

## Contributor checks

From the engine root, run `python3 tools/build_editor_grammar.py` after changing the lexer keyword map. Commit the generated JSON. CI runs `python3 tools/build_editor_grammar.py --check` and the grammar tests to catch drift.
