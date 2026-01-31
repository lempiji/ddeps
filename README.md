# DDeps

Source review support tool

A tool to create a module dependency graph for the D language.
The feature is that you can record snapshots in two versions and compare them to visualize the differences.

# Screenshot (Example)

**basic**

![rx](https://raw.githubusercontent.com/lempiji/ddeps/master/screenshot/rx-deps.png)

**no core, no std**

![rx-nostd](https://raw.githubusercontent.com/lempiji/ddeps/master/screenshot/rx-deps-nostd.png)

**exclude rx.subject**

![rx-nosubject](https://raw.githubusercontent.com/lempiji/ddeps/master/screenshot/rx-deps-nosubject.png)

# Requirements
1. dub
2. Graphviz (for DOT/SVG output)
3. Mermaid-capable viewer/editor (only when using `--format=mermaid`)

# Settings

## For library (example)
```json
	"configurations": [
		{
			"name": "default"
		},
		{
			"name": "diff",
			"postGenerateCommands": [
				"dub build -c makedeps",
				"dub fetch ddeps",
				"dub run ddeps -- --focus=rx -o deps.dot",
				"dot -Tsvg -odeps.svg deps.dot"
			]
		},
		{
			"name": "diff-update",
			"postGenerateCommands": [
				"dub fetch ddeps",
				"dub run ddeps -- --update"
			]
		},
		{
			"name": "makedeps",
			"dflags": ["-deps=deps.txt"]
		}
  ]
```

## For executable
```json
	"configurations": [
		{
			"name": "default"
		},
		{
			"name": "diff",
			"postGenerateCommands": [
				"dub build -c makedeps",
				"dub fetch ddeps",
				"dub run ddeps -- -o deps.dot",
				"dot -Tsvg -odeps.svg deps.dot"
			]
		},
		{
			"name": "diff-update",
			"postGenerateCommands": [
				"dub fetch ddeps",
				"dub run ddeps -- --update"
			]
		},
		{
			"name": "makedeps",
			"dflags": ["-deps=deps.txt"]
		}
  ]
```

### For Mermaid output (example)
Use the same configurations but swap the post command to emit Mermaid instead of DOT/SVG:

```json
{
	"name": "diff-mermaid",
	"postGenerateCommands": [
		"dub build -c makedeps",
		"dub fetch ddeps",
		"dub run ddeps -- --format=mermaid --output=deps.mmd"
	]
}
```

# Usage

## At first
create lock file

```bash
dub build -c makedeps
dub build -c diff-update
```

## Basic
1. Modify source
2. Update diff
	- `dub build -c diff`
3. Do review with the dependency graph diff
	- Open the `deps.svg` in browser, or generate Mermaid with `dub run ddeps -- --format=mermaid --output=deps.mmd` and view it in a Mermaid-enabled editor.

## Compare 2 versions

1. checkout a target version
	- `git reset --hard XXX` or `git checkout XXXXX`
2. reset to source version
	- `git reset --hard HEAD~10` (e.g. 10 versions ago)
3. create `deps-lock.txt`
	- `dub build -c makedeps`
	- `dub build -c diff-update`
	- if `dub.json` / `dub.sdl` has not configure then add these.  
4. reset to target version
	- `git reset --hard ORIG_HEAD`
5. make diff
	- `dub build -c diff`
6. open `deps.svg` (or produce Mermaid: `dub run ddeps -- --format=mermaid --output=deps.mmd`)


# Arguments

| name | Usage | description | default |
|:-----|:------------|:--|:--|
| input | `-i XXX` or `--input=XXX` | deps file name | `deps.txt` |
| output | `-o XXX` or `--output=XXX` | destination file name | write to stdout |
| update | `-u` or `--update` | update lock file | false |
| lock | `-l XXX` or `--lock=XXX` | lock file name | `deps-lock.txt` |
| focus | `-f XXX` or `--focus=XXX` | filtering target by name | `app` |
| depth | `-d N` or `--depth=N` | search depth | 1 |
| exclude | `-e XXX [-e YYY]` or `--exclude=XXX [--exclude=YYY]` | exclude module names | `object` |
| format | `--format=dot|mermaid` | output format | `dot` |
| help | `--help` | show help |  |

# Mermaid output

You can render the diff as a Mermaid graph (useful in Markdown viewers that support Mermaid):

```bash
dub run ddeps -- --format=mermaid --output=deps.mmd
```

Open `deps.mmd` in a Mermaid-capable viewer/editor to inspect the graph. Added nodes/edges are green, removed are red, kept are neutral. Graphviz is not required for Mermaid output.
