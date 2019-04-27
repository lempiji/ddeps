# DDeps

Source review support tool.

A tool for creating module dependency graphs. And visualize the differences between the two snapshots.

# Screenshot (Example)
![rx](https://raw.githubusercontent.com/lempiji/ddeps/master/screenshot/rx-deps.png)

# Requirements
1. dub
2. Graphviz (for visualize)

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
	- Open the `deps.svg` in browser

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
6. open `deps.svg`


# Arguments

| name | Usage | description | default |
|:-----|:------------|:--|:--|
| input | `-i XXX` or `--input=XXX` | deps file name | `deps.txt` |
| output | `-o XXX` or `--output=XXX` | destination file name | write to stdout |
| update | `-u` or `--update` | update lock file | false |
| lock | `-l XXX` or `--lock=XXX` | lock file name | `deps-lock.txt` |
| focus | `-f XXX` or `--focus=XXX` | filtering target by name | `app` |
| depth | `-d N` or `--depth=N` | search depth | 1 |
| help | `--help` | show help |  |
