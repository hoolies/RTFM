# Attributions and third-party material

## Implementation ownership

The shell code in this repository (**`fzf-man-opts.zsh`**, loaders, plugin stub) was written for this project. It is not a fork of another plugin’s codebase. Embedded **awk** programs are part of the same work (not copied wholesale from an external repository).

## Tools and runtimes (dependencies)

These programs are invoked by the plugin but are **separate projects** with their own licenses:

| Tool | Role |
|------|------|
| [Zsh](https://www.zsh.org/) | Line editor (ZLE), widgets, completion integration |
| [fzf](https://github.com/junegunn/fzf) | Fuzzy finder UI |
| `fzf-tmux` (bundled with fzf) | Optional tmux-aware fzf wrapper |
| [ripgrep](https://github.com/BurntSushi/ripgrep) (`rg`) | Fast regex filtering (e.g. usage detection, `fzf --help` probe) |
| `man`, `col -b` | Manual pages and plaintext conversion |
| `awk`, `sort`, `cut`, `find`, `file`, `head`, … | POSIX / common Unix utilities |
| `timeout` (GNU coreutils or similar) | Optional bounded subprocess runs in diagnostics / `sv` probing |
| `fd` (optional) | Faster file enumeration when installed |
| Docker / iproute2 / runit | Their **help and man pages** are parsed at runtime (content © respective projects; programmatic reading only) |

## Documentation and standards consulted (inspiration, not copied code)

Work on this plugin drew on **public documentation and behaviour** of:

- **Zsh**: ZLE, `bindkey`, `zle`, `widgets`, options such as `noshwordsplit`, parameter expansion, `ttyctl`
- **fzf**: CLI flags (`--preview`, `--delimiter`, `--scheme path`, key bindings)
- **ShellCheck**: Bash-dialect hints for cross-checking syntax (this script is **zsh-only**; `shellcheck --shell=bash` is advisory)
- **Manual-page layout**: `man(1)`, common `OPTIONS` / `SYNOPSIS` sections (especially **iproute2** `ip(8)` / `ip-*`, **Docker** CLI help, **runit** `sv(8)`)

## Similar community projects (conceptual reference only)

These projects influenced the **design goal** (“one Tab key, many behaviours”) but are **not** source copies:

- **fzf-tab** and other fzf-based completion UIs — unified fuzzy completion patterns
- **zsh-users** mailing list / wiki discussions — widget and `expand-or-complete` fallback patterns

If you believe a specific snippet should be credited to an earlier author, open an issue with a link and it will be added here.

## License

See [LICENSE](LICENSE) for the repository’s license (MIT).
