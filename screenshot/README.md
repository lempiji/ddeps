# Settings

| name                | command |
|:--------------------|:------|
| `rx-deps`           | `dub run ddeps -- -f rx -o deps.dot` |
| `rx-deps-nostd`     | `dub run ddeps -- -f rx -o deps.dot -e std -e core` |
| `rx-deps-nosubject` | `dub run ddeps -- -f rx -o deps.dot -e std -e core -e rx.subject` |