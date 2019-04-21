import std.stdio;
import std.algorithm;
import std.conv;
import std.container.rbtree;
import std.array;
import std.file;
import std.getopt;

version (unittest)
{
}
else
{
	int main(string[] args)
	{
		string outfile;
		string depsfile = "deps.txt";
		string lockfile = "deps-lock.txt";
		string focusName = "app";
		int filterCost = 1;
		bool forceUpdate;

		// dfmt off
		auto helpInformation = getopt(args,
				"i|input", "deps file name", &depsfile,
				"o|output", "graph file name.\n\tIf not specified, it is standard output.", &outfile,
				"u|update", "update lock file", &forceUpdate,
				"l|lock", "lock file name", &lockfile,
				"f|focus", "filtering target name", &focusName,
				"d|depth", "depth for dependency search", &filterCost
			);
		// dfmt on

		if (helpInformation.helpWanted)
		{
			defaultGetoptPrinter("", helpInformation.options);
			return 0;
		}

		if (forceUpdate)
		{
			writefln!"copy lockfile (%s)"(lockfile);
			copy(depsfile, lockfile);
			return 0;
		}

		auto beforeGraph = readText(lockfile).toGraph();
		auto afterGraph = readText(depsfile).toGraph();

		auto diff = makeDiff(beforeGraph, afterGraph, DiffSettings(focusName, filterCost));

		auto f = outfile ? File(outfile, "w") : stdout;
		scope (exit)
			f.close();

		f.writeln("digraph {");
		if (diff.keptNodes.length > 0)
		{
			f.writeln("    {");
			foreach (m; diff.keptNodes)
			{
				f.writefln!"        \"%s\""(m.name);
			}
			f.writeln("    }");
		}
		if (diff.removedNodes.length > 0)
		{
			f.writeln("    {");
			f.writeln(`        node [style=filled color="#fdaeb7" fillcolor="#ffeef0"];`);
			foreach (m; diff.removedNodes)
			{
				f.writefln!"        \"%s\""(m.name);
			}
			f.writeln("    }");
		}
		if (diff.addedNodes.length > 0)
		{
			f.writeln("    {");
			f.writeln(`        node [style=filled color="#bef5cb" fillcolor="#e6ffed"];`);
			foreach (m; diff.addedNodes)
			{
				f.writefln!"        \"%s\""(m.name);
			}
			f.writeln("    }");
		}

		////////////////////////////////////////////////////////////////////////////
		enum ModuleEditType
		{
			Keep,
			Remove,
			Add,
		}

		ModuleEditType[string] moduleSet;
		foreach (m; diff.keptNodes)
			moduleSet[m.name] = ModuleEditType.Keep;
		foreach (m; diff.removedNodes)
			moduleSet[m.name] = ModuleEditType.Remove;
		foreach (m; diff.addedNodes)
			moduleSet[m.name] = ModuleEditType.Add;

		if (diff.keptEdges.length > 0)
		{
			foreach (m; diff.keptEdges)
			{
				switch (moduleSet[m.import_.name]) with (ModuleEditType)
				{
				case Keep:
					f.writefln!`    "%s" -> "%s";`(m.module_.name, m.import_.name);
					break;
				case Remove:
					f.writefln!`    "%s" -> "%s" [color="#cb2431"];`(m.module_.name,
							m.import_.name);
					break;
				case Add:
					f.writefln!`    "%s" -> "%s" [color="#2cbe4e"];`(m.module_.name,
							m.import_.name);
					break;
				default:
					writeln("// unknown edge: ", m);
					break;
				}
			}
		}
		if (diff.removedEdges.length > 0)
		{
			foreach (m; diff.removedEdges)
				f.writefln!`    "%s" -> "%s" [color="#cb2431"];`(m.module_.name, m.import_.name);
		}
		if (diff.addedEdges.length > 0)
		{
			foreach (m; diff.addedEdges)
				f.writefln!`    "%s" -> "%s" [color="#2cbe4e"];`(m.module_.name, m.import_.name);
		}
		f.writeln("}");

		return 0;
	}
}

DependenciesGraph toGraph(string value)
{
	auto nodes = new RedBlackTree!Node();
	auto edges = new RedBlackTree!Edge();

	foreach (line; value.splitter("\n"))
	{
		if (line.length == 0)
			continue;

		auto tokens = splitter(line, " : ");
		auto sourceText = tokens.pop();
		auto importType = tokens.pop();
		auto targetText = tokens.pop();

		auto sourceName = until(sourceText, " ").to!string();
		auto sourceModule = Node(sourceName);
		nodes.insert(sourceModule);
		auto targetName = targetText.until(" ").to!string();
		auto targetModule = Node(targetName);
		nodes.insert(targetModule);

		edges.insert(Edge("module", sourceModule, targetModule, importType));
	}

	// TODO 省略できる気がする
	auto tempNodes = nodes[].array();
	tempNodes.sort();
	auto tempEdges = edges[].array();
	tempEdges.sort();
	return new DependenciesGraph(tempNodes, tempEdges);
}

unittest
{
	auto graph = toGraph(`
app (/app.d) : private : object (/object.d)
app (/app.d) : private : std.stdio (/std/stdio.d)
`);

	assert(graph.modules.length == 3);
	assert(graph.modules[0].name == "app");
	assert(graph.modules[1].name == "object");
	assert(graph.modules[2].name == "std.stdio");

	assert(graph.dependencies.length == 2);
	assert(graph.dependencies[0].module_.name == "app");
	assert(graph.dependencies[0].import_.name == "object");
	assert(graph.dependencies[1].module_.name == "app");
	assert(graph.dependencies[1].import_.name == "std.stdio");
}

struct GraphDiff
{
	Node[] keptNodes;
	Node[] removedNodes;
	Node[] addedNodes;

	Edge[] keptEdges;
	Edge[] removedEdges;
	Edge[] addedEdges;
}

struct DiffSettings
{
	string filterName;
	int filterCost;
}

GraphDiff makeDiff(DependenciesGraph before, DependenciesGraph after, DiffSettings settings)
{
	GraphDiff result;

	auto beforeTempCost = makeNodeCostDic(before.dependencies,
			settings.filterName, settings.filterCost);
	auto afterTempCost = makeNodeCostDic(after.dependencies,
			settings.filterName, settings.filterCost);

	auto beforeEdges = before.dependencies.filter!(e => isOutputTarget(e,
			beforeTempCost, settings.filterCost)).array();
	auto afterEdges = after.dependencies.filter!(e => isOutputTarget(e,
			afterTempCost, settings.filterCost)).array();

	result.keptEdges = setIntersection(beforeEdges, afterEdges).array();
	result.removedEdges = setDifference(beforeEdges, afterEdges).array();
	result.addedEdges = setDifference(afterEdges, beforeEdges).array();

	auto beforeCost = makeNodeCostDic(beforeEdges, settings.filterName, settings.filterCost);
	auto afterCost = makeNodeCostDic(afterEdges, settings.filterName, settings.filterCost);

	auto beforeNodes = before.modules.filter!(m => isOutputTarget(m,
			beforeCost, settings.filterCost)).array();
	auto afterNodes = after.modules.filter!(m => isOutputTarget(m, afterCost,
			settings.filterCost)).array();

	result.keptNodes = setIntersection(beforeNodes, afterNodes).array();
	result.removedNodes = setDifference(beforeNodes, afterNodes).array();
	result.addedNodes = setDifference(afterNodes, beforeNodes).array();

	return result;
}

unittest
{
	auto before = toGraph(`
app (/app.d) : private : object (/object.d)
app (/app.d) : private : std.stdio (/std/stdio.d)
`);
	auto after = toGraph(`
app (/app.d) : private : object (/object.d)
app (/app.d) : private : std.stdio (/std/stdio.d)
app (/app.d) : private : std.algorithm (/std/algorithm.d)
`);

	auto diff = makeDiff(before, after, DiffSettings("app", 1));

	assert(diff.keptNodes.length == 3);
	assert(diff.keptNodes[0].name == "app");
	assert(diff.keptNodes[1].name == "object");
	assert(diff.keptNodes[2].name == "std.stdio");
	assert(diff.removedNodes.length == 0);
	assert(diff.addedNodes.length == 1);
	assert(diff.addedNodes[0].name == "std.algorithm");
}

unittest
{
	auto before = toGraph(`
app (/app.d) : private : object (/object.d)
app (/app.d) : private : std.stdio (/std/stdio.d)
app (/app.d) : private : std.algorithm (/std/algorithm.d)
`);
	auto after = toGraph(`
app (/app.d) : private : object (/object.d)
app (/app.d) : private : std.stdio (/std/stdio.d)
`);

	auto diff = makeDiff(before, after, DiffSettings("app", 1));

	assert(diff.keptNodes.length == 3);
	assert(diff.keptNodes[0].name == "app");
	assert(diff.keptNodes[1].name == "object");
	assert(diff.keptNodes[2].name == "std.stdio");
	assert(diff.removedNodes.length == 1);
	assert(diff.removedNodes[0].name == "std.algorithm");
	assert(diff.addedNodes.length == 0);
}

unittest
{
	auto before = toGraph(`
app (/app.d) : private : object (/object.d)
app (/app.d) : private : std.stdio (/std/stdio.d)
`);
	auto after = toGraph(`
app (/app.d) : private : object (/object.d)
app (/app.d) : private : std.stdio (/std/stdio.d)
std.stdio (/std/stdio.d) : private : object (/object.d)
`);

	auto diff = makeDiff(before, after, DiffSettings("app", 2));

	assert(diff.keptEdges.length == 2);
	assert(diff.keptEdges[0].module_.name == "app");
	assert(diff.keptEdges[0].import_.name == "object");
	assert(diff.keptEdges[1].module_.name == "app");
	assert(diff.keptEdges[1].import_.name == "std.stdio");
	assert(diff.removedEdges.length == 0);
	assert(diff.addedEdges.length == 1);
	assert(diff.addedEdges[0].module_.name == "std.stdio");
	assert(diff.addedEdges[0].import_.name == "object");
}

unittest
{
	auto before = toGraph(`
app (/app.d) : private : object (/object.d)
app (/app.d) : private : std.stdio (/std/stdio.d)
std.stdio (/std/stdio.d) : private : object (/object.d)
`);
	auto after = toGraph(`
app (/app.d) : private : object (/object.d)
app (/app.d) : private : std.stdio (/std/stdio.d)
`);

	auto diff = makeDiff(before, after, DiffSettings("app", 2));

	assert(diff.keptEdges.length == 2);
	assert(diff.keptEdges[0].module_.name == "app");
	assert(diff.keptEdges[0].import_.name == "object");
	assert(diff.keptEdges[1].module_.name == "app");
	assert(diff.keptEdges[1].import_.name == "std.stdio");
	assert(diff.addedEdges.length == 0);
	assert(diff.removedEdges.length == 1);
	assert(diff.removedEdges[0].module_.name == "std.stdio");
	assert(diff.removedEdges[0].import_.name == "object");
}

struct Node
{
	string name;

	this(string name)
	{
		this.name = name;
	}

	int opCmp(ref const Node rhs)
	{
		return cmp(name, rhs.name);
	}

	int opCmp(ref const Node rhs) const
	{
		return cmp(name, rhs.name);
	}
}

struct Edge
{
	string kind;
	Node module_;
	Node import_;
	string importType;

	this(string kind, Node module_, Node import_, string importType = "private")
	{
		this.kind = kind;
		this.module_ = module_;
		this.import_ = import_;
		this.importType = importType;
	}

	int opCmp(ref const Edge rhs) const
	{
		auto kind = cmp(this.kind, rhs.kind);
		if (kind != 0)
			return kind;
		auto module_ = cmp(this.module_.name, rhs.module_.name);
		if (module_ != 0)
			return module_;
		auto import_ = cmp(this.import_.name, rhs.import_.name);
		return import_;
	}
}

class DependenciesGraph
{
	Node[] modules;
	Edge[] dependencies;

	this(Node[] modules, Edge[] dependencies)
	{
		this.modules = modules;
		this.dependencies = dependencies;
	}
}

auto pop(R)(auto ref R range)
{
	scope (success)
		range.popFront();

	return range.front;
}

int[string] makeNodeCostDic(Edge[] edges, string filterName, int maxCost = int.max)
{
	typeof(return) result;

	auto nodeSet = new RedBlackTree!string;
	foreach (edge; edges)
	{
		nodeSet.insert(edge.module_.name);
		nodeSet.insert(edge.import_.name);
	}
	foreach (name; nodeSet[])
	{
		result[name] = isFocusTarget(name, filterName) ? 0 : int.max;
	}

	bool changed;
	int currentCost = -1;

	do
	{
		changed = false;
		currentCost++;

		foreach (edge; edges)
		{
			if (result[edge.module_.name] == currentCost)
			{
				result[edge.import_.name] = min(result[edge.import_.name], currentCost + 1);
				changed = true;
			}
		}
	}
	while (changed && currentCost < maxCost);

	return result;
}

unittest
{
	auto cost = makeNodeCostDic([Edge(null, Node("app"), Node("std.stdio"), null)], "app");
	assert(cost["app"] == 0);
	assert(cost["std.stdio"] == 1);
}

bool isFocusTarget(const scope string nodeName, const scope string name)
{
	if (nodeName.length < name.length)
		return false;
	if (nodeName[0 .. name.length] != name)
		return false;

	if (nodeName.length == name.length)
		return true;
	if (nodeName.length >= name.length + 1 && nodeName[name.length] == '.')
		return true;

	return false;
}

unittest
{
	assert(isFocusTarget("app", "app"));
	assert(isFocusTarget("app.common", "app"));
	assert(isFocusTarget("app.testing.utils", "app"));
	assert(!isFocusTarget("std.algorithm", "app"));
	assert(!isFocusTarget("core.atomic", "app"));
	assert(!isFocusTarget("util", "app"));

	assert(isFocusTarget("core.atomic", "core"));

	assert(!isFocusTarget("app", "util"));
}

int getCost(Node node, int[string] cost)
{
	if (!(node.name in cost))
		return int.max;
	return cost[node.name];
}

bool isOutputTarget(Node node, int[string] cost, int filter)
{
	// 暗黙的にimportされるが、グラフが大変見づらいため削除
	if (node.name == "object")
		return false;

	return node.getCost(cost) <= filter;
}

bool isOutputTarget(Edge edge, int[string] cost, int filter)
{
	if (edge.import_.name == "object" || edge.import_.getCost(cost) > filter)
		return false;
	if (edge.module_.name == "object" || edge.module_.getCost(cost) >= filter)
		return false;
	return true;
}
