# Source of the VS Code workbench

This folder is the source of the extension, so it can be read, changed and rebuilt.

```
extension/     the VS Code extension (TypeScript, no framework, no bundled runtime deps)
```

## Build it

Fifteen modules of the extension are the same code as `extension/src/` in
[agent-setup](https://github.com/Skryx-L-A/agent-setup) and are not part of this repository, see
`../../../NOTICE.md`. Copy them in first:

```bash
cd extension
scripts/fetch-shared.sh /path/to/agent-setup
npm install
npm run check      # typecheck + tests + build
npm run package    # produces the .vsix
code --install-extension claude-workbench-0.1.0.vsix --force
```

`npm run check` is the gate: it typechecks, runs the whole suite and builds. The versions of the
fifteen modules in agent-setup may have moved on since this source was written; if the type check
fails after fetching them, the extension code has to be adapted to them.

## What differs from the machine this came from

The setup this was extracted from used a private name for its second machine; here it is simply
`peer` throughout, and the example user in fixtures is `alice`.
