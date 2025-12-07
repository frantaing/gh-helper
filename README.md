# gh-helper

A TUI for managing GitHub repos from your terminal. Because some things just aren't possible through the web UI.

## Roadmap

- [ ] Deployment cleanup
- [ ] Actions cache management
- [ ] Bulk workflow run cleanup
- [ ] Stale branch pruning (across multiple repos)

## Installation

You'll need:
- [GitHub CLI (`gh`)](https://cli.github.com/)
- [gum](https://github.com/charmbracelet/gum)
- [jq](https://stedolan.github.io/jq/)

Then:
```bash
git clone https://github.com/frantaing/gh-helper.git
cd gh-helper
chmod +x gh-helper.sh

# Optional: add to your PATH
sudo ln -s "$(pwd)/gh-helper.sh" /usr/local/bin/gh-helper
```

## Usage

Authenticate with GitHub CLI first:
```bash
gh auth login
```

Then run:
```bash
gh-helper
```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.