#!/usr/bin/env rdmd
module scripts.sample_outputs;

import std.stdio;
import std.file;
import std.path;
import std.process;
import std.string;
import std.range;
import std.array;
import std.conv;

struct CaseSpec
{
	string name;
	string[] args;
}

string repoRoot()
{
	return absolutePath(dirName(__FILE__).dirName);
}

int run(string[] args, string cwd)
{
	writeln("[run] ", cwd, "$ ", args.join(" "));
	auto res = execute(args, null, Config.stderrPassThrough, size_t.max, cwd);
	if (res.output.length)
		write(res.output);
	return res.status;
}

bool hasDot()
{
	auto res = execute(["dot", "-V"], null, Config.stderrPassThrough, size_t.max, ".");
	return res.status == 0;
}

bool ensureRepo(string name, string destDir, bool shallow = true)
{
	if (exists(destDir))
	{
		writeln("[repo] reuse ", destDir);
		return true;
	}

	mkdirRecurse(destDir.dirName);
	string[] cloneArgs = shallow
		? ["git", "clone", "--depth", "1", "https://github.com/lempiji/" ~ name ~ ".git", destDir]
		: ["git", "clone", "https://github.com/lempiji/" ~ name ~ ".git", destDir];
	auto code = run(cloneArgs, repoRoot());
	return code == 0 && exists(destDir);
}

bool ensureDepsFiles(string repoDir)
{
	auto deps = buildPath(repoDir, "deps.txt");
	if (!exists(deps))
	{
		auto rc = run(["dub", "build", "-c", "makedeps"], repoDir);
		if (rc != 0 || !exists(deps))
		{
			writeln("[deps] fallback: dub build -- -deps=deps.txt");
			rc = run(["dub", "build", "--", "-deps=deps.txt"], repoDir);
		}
		if ((rc != 0 || !exists(deps)))
		{
			writeln("[deps] fallback: DFLAGS=-deps=deps.txt dub build");
			string[string] env;
			env["DFLAGS"] = "-deps=" ~ deps;
			auto res = execute(["dub", "build"], env, Config.stderrPassThrough, size_t.max, repoDir);
			if (res.output.length)
				write(res.output);
			rc = res.status;
		}
		if (rc != 0 || !exists(deps))
		{
			writeln("[deps] failed to build deps.txt in ", repoDir);
			return false;
		}
	}

	auto lock = buildPath(repoDir, "deps-lock.txt");
	if (!exists(lock))
	{
		copy(deps, lock);
		writeln("[deps] created deps-lock.txt");
	}
	return true;
}

CaseSpec[] makeCases(string repo)
{
	switch (repo)
	{
	case "golem":
		return [
			CaseSpec("baseline", ["--focus=golem"]),
			CaseSpec("baseline-exclude", ["--focus=golem", "--exclude=core", "--exclude=std"]),
			CaseSpec("full", ["--focus=golem", "--group=external=mir.*,numir,msgpack.*", "--exclude=core", "--exclude=std"]),
		];
	case "openai-d":
		return [
			CaseSpec("baseline", ["--focus=openai"]),
			CaseSpec("baseline-exclude", ["--focus=openai", "--exclude=core", "--exclude=std"]),
			CaseSpec("full", ["--focus=openai", "--group=openai.clients", "--group=openai.administration", "--group=mir", "--exclude=core", "--exclude=std"]),
		];
	case "md":
		return [
			CaseSpec("baseline", ["--focus=app"]),
			CaseSpec("baseline-exclude", ["--focus=app", "--exclude=core", "--exclude=std"]),
			CaseSpec("full", ["--focus=app", "--group=external=jcli.*,commonmarkd.*", "--depth=2", "--exclude=core", "--exclude=std"]),
		];
	case "rx":
		return [
			CaseSpec("baseline", ["--focus=rx"]),
			CaseSpec("baseline-exclude", ["--focus=rx", "--exclude=core", "--exclude=std"]),
			CaseSpec("full", ["--focus=rx", "--group=rx.algorithm", "--group=rx.range", "--group=core", "--group=std"])
		];
	default:
		return [CaseSpec("baseline", ["--focus=" ~ repo])];
	}
}

void runCase(string repoDir, string repoName, CaseSpec cs, string root, bool svgOk)
{
	auto deps = buildPath(repoDir, "deps.txt");
	auto lock = buildPath(repoDir, "deps-lock.txt");
	string baseName = "deps-" ~ cs.name;

	string[] baseCmd = ["dub", "run", "--root", root, "--",
			"--input=" ~ deps, "--lock=" ~ lock];
	string[] args = baseCmd ~ cs.args;

	// DOT
	auto dotPath = buildPath(repoDir, baseName ~ ".dot");
	auto dotCmd = args ~ ["--format=dot", "--output=" ~ dotPath];
	run(dotCmd, repoDir);
	if (svgOk && exists(dotPath))
	{
		auto svgPath = baseName ~ ".svg";
		run(["dot", "-Tsvg", "-o", svgPath, dotPath], repoDir);
	}

	// Mermaid
	auto mmdPath = buildPath(repoDir, baseName ~ ".mmd");
	auto mmdCmd = args ~ ["--format=mermaid", "--output=" ~ mmdPath];
	run(mmdCmd, repoDir);

	writeln("[case] ", repoName, " ", cs.name, " -> ",
			baseName ~ ".dot, " ~ baseName ~ ".mmd");
}

bool ensureWorktree(string repoDir, string worktreeDir, string refName)
{
	if (exists(worktreeDir))
	{
		writeln("[worktree] reuse ", worktreeDir);
		return true;
	}
	// try worktree
	auto code = run(["git", "-C", repoDir, "worktree", "add", worktreeDir, refName], repoDir);
	if (code == 0)
		return true;
	// fallback clone
	mkdirRecurse(worktreeDir.dirName);
	code = run(["git", "clone", "https://github.com/lempiji/rx.git", worktreeDir], worktreeDir.dirName);
	if (code != 0)
		return false;
	return run(["git", "-C", worktreeDir, "checkout", refName], worktreeDir) == 0;
}

void runRxDiff(string root, bool svgOk)
{
	auto newDir = buildPath(root, "tmp", "test-rx");
	auto oldDir = buildPath(root, "tmp", "test-rx-old");

	// ensure main rx (full history)
	if (!ensureRepo("rx", newDir, false))
		return;
	run(["git", "-C", newDir, "fetch", "--tags"], newDir);
	run(["git", "-C", newDir, "checkout", "HEAD"], newDir);

	// ensure old worktree/clone at v0.7.0
	if (!ensureWorktree(newDir, oldDir, "v0.7.0"))
	{
		writeln("[rx-diff] failed to prepare old ref worktree");
		return;
	}

	// build deps in old
	if (!ensureDepsFiles(oldDir))
	{
		writeln("[rx-diff] failed deps in old ref");
		return;
	}
	auto oldDeps = buildPath(oldDir, "deps.txt");
	auto lockOld = buildPath(newDir, "deps-lock-old.txt");
	copy(oldDeps, lockOld);

	// build deps in new
	if (!ensureDepsFiles(newDir))
	{
		writeln("[rx-diff] failed deps in new ref");
		return;
	}

	string[] args = ["dub", "run", "--root", root, "--",
		"--input=" ~ buildPath(newDir, "deps.txt"),
		"--lock=" ~ lockOld,
		"--focus=rx",
		"--group=rx.algorithm", "--group=rx.range", "--group=core", "--group=std",
		"--exclude=core", "--exclude=std"];

	auto dotPath = buildPath(newDir, "deps-diff-full.dot");
	run(args ~ ["--format=dot", "--output=" ~ dotPath], newDir);
	if (svgOk && exists(dotPath))
		run(["dot", "-Tsvg", "-o", "deps-diff-full.svg", dotPath], newDir);
	run(args ~ ["--format=mermaid", "--output=deps-diff-full.mmd"], newDir);
	writeln("[rx-diff] refs: old=v0.7.0, new=HEAD; outputs deps-diff-full.*");
}

void main()
{
	auto root = repoRoot();
	auto tmpRoot = buildPath(root, "tmp");
	mkdirRecurse(tmpRoot);

	auto svgOk = hasDot();

	string[string] repos = ["rx" : "rx", "golem" : "golem", "openai-d" : "openai-d", "md" : "md"];

	foreach (repoName, folder; repos)
	{
		auto dest = buildPath(tmpRoot, "test-" ~ folder);
		bool shallow = repoName != "rx";
		if (!ensureRepo(repoName, dest, shallow))
			continue;
		if (!ensureDepsFiles(dest))
			continue;

		auto cases = makeCases(folder);
		foreach (cs; cases)
			runCase(dest, folder, cs, root, svgOk);

		writeln("[done] ", folder, " outputs under ", dest);
	}

	// rx diff scenario (fixed refs)
	runRxDiff(root, svgOk);
}
