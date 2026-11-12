# jorgenbs/homebrew-tap (private)

Personal Homebrew tap. Private, so it's tapped over SSH and casks fetch private release assets
with `HOMEBREW_GITHUB_API_TOKEN`:

```sh
brew tap jorgenbs/tap git@github.com:jorgenbs/homebrew-tap.git
HOMEBREW_GITHUB_API_TOKEN=$(gh auth token) brew install --cask jorgenbs/tap/clipboard-history
```

| Cask | Description |
| --- | --- |
| `clipboard-history` | Menu bar clipboard history with search, preview and auto-paste |

Casks are updated automatically by each project's release workflow (via a deploy key).
