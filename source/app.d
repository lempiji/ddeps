module app;

import std.stdio;
import std.algorithm;
import std.conv;
import std.container.rbtree;
import std.array;
import std.file;
import std.getopt;
import std.range;
import std.ascii : isAlphaNum, isDigit;
import std.array : appender;

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
		string[] excludeNames = ["object"]; // default exclude
		string formatName = "dot";

		// dfmt off
		auto helpInformation = getopt(args,
				"i|input", "deps file name", &depsfile,
				"o|output", "graph file name.\n\tIf not specified, it is standard output.", &outfile,
				"u|update", "update lock file", &forceUpdate,
				"l|lock", "lock file name", &lockfile,
				"f|focus", "filtering target name", &focusName,
				"d|depth", "depth for dependency search", &filterCost,
				"e|exclude", "exclude module names", &excludeNames,
				"format", "output format: dot or mermaid", &formatName
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

		auto diff = makeDiff(beforeGraph, afterGraph, DiffSettings(focusName,
				filterCost, excludeNames));

		auto moduleSet = buildModuleSet(diff);
		auto f = outfile ? File(outfile, "w") : stdout;
		scope (exit)
			f.close();

		switch (formatName)
		{
		case "dot":
			renderDot(f, diff, moduleSet);
			break;
		case "mermaid":
			renderMermaid(f, diff, moduleSet);
			break;
		default:
			stderr.writefln!"Unknown format: %s (use dot or mermaid)"(formatName);
			return 2;
		}

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

enum ModuleEditType
{
	Keep,
	Remove,
	Add,
}

struct DiffSettings
{
	this(string filterName, int filterCost)
	{
		this(filterName, filterCost, null);
	}

	this(string filterName, int filterCost, string[] excludeNames)
	{
		this.filterName = filterName;
		this.filterCost = filterCost;
		this.excludeNames = excludeNames;
	}

	string filterName;
	int filterCost;
	string[] excludeNames;
}

GraphDiff makeDiff(DependenciesGraph before, DependenciesGraph after, DiffSettings settings)
{
	GraphDiff result;

	auto beforeTempCost = makeNodeCostDic(before.dependencies,
			settings.filterName, settings.filterCost);
	auto afterTempCost = makeNodeCostDic(after.dependencies,
			settings.filterName, settings.filterCost);

	auto beforeEdges = before.dependencies.filter!(e => isOutputTarget(e,
			beforeTempCost, settings.filterCost, settings.excludeNames)).array();
	auto afterEdges = after.dependencies.filter!(e => isOutputTarget(e,
			afterTempCost, settings.filterCost, settings.excludeNames)).array();

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

ModuleEditType[string] buildModuleSet(GraphDiff diff)
{
	ModuleEditType[string] moduleSet;
	foreach (m; diff.keptNodes)
		moduleSet[m.name] = ModuleEditType.Keep;
	foreach (m; diff.removedNodes)
		moduleSet[m.name] = ModuleEditType.Remove;
	foreach (m; diff.addedNodes)
		moduleSet[m.name] = ModuleEditType.Add;
	return moduleSet;
}

unittest
{
	// Add node and edge
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

	assert(diff.keptEdges.length == 2);
	assert(diff.keptEdges[0].module_.name == "app");
	assert(diff.keptEdges[0].import_.name == "object");
	assert(diff.keptEdges[1].module_.name == "app");
	assert(diff.keptEdges[1].import_.name == "std.stdio");
	assert(diff.removedEdges.length == 0);
	assert(diff.addedEdges.length == 1);
	assert(diff.addedEdges[0].module_.name == "app");
	assert(diff.addedEdges[0].import_.name == "std.algorithm");
}

unittest
{
	// Remove node and edge
	auto before = toGraph(`
app (/app.d) : private : object (/object.d)
app (/app.d) : private : std.stdio (/std/stdio.d)
app (/app.d) : private : std.algorithm (/std/algorithm.d)
std.stdio (/std/stdio.d) : private : object (/object.d)
`);
	auto after = toGraph(`
app (/app.d) : private : object (/object.d)
app (/app.d) : private : std.stdio (/std/stdio.d)
std.stdio (/std/stdio.d) : private : object (/object.d)
`);

	auto diff = makeDiff(before, after, DiffSettings("app", 1));

	assert(diff.keptNodes.length == 3);
	assert(diff.keptNodes[0].name == "app");
	assert(diff.keptNodes[1].name == "object");
	assert(diff.keptNodes[2].name == "std.stdio");
	assert(diff.removedNodes.length == 1);
	assert(diff.removedNodes[0].name == "std.algorithm");
	assert(diff.addedNodes.length == 0);

	assert(diff.keptEdges.length == 2);
	assert(diff.keptEdges[0].module_.name == "app");
	assert(diff.keptEdges[0].import_.name == "object");
	assert(diff.keptEdges[1].module_.name == "app");
	assert(diff.keptEdges[1].import_.name == "std.stdio");
	assert(diff.removedEdges.length == 1);
	assert(diff.removedEdges[0].module_.name == "app");
	assert(diff.removedEdges[0].import_.name == "std.algorithm");
	assert(diff.addedEdges.length == 0);
}

unittest
{
	// Add node and edge with excludeNames,
	// then omit about the std.conv
	auto before = toGraph(`
app (/app.d) : private : object (/object.d)
app (/app.d) : private : std.stdio (/std/stdio.d)
std.stdio (/std/stdio.d) : private : object (/object.d)
`);
	auto after = toGraph(`
app (/app.d) : private : object (/object.d)
app (/app.d) : private : std.conv (/std/conv.d)
app (/app.d) : private : std.stdio (/std/stdio.d)
std.stdio (/std/stdio.d) : private : object (/object.d)
`);

	auto diff = makeDiff(before, after, DiffSettings("app", 2, ["std.conv"]));

	assert(diff.keptNodes.length == 3);
	assert(diff.keptNodes[0].name == "app");
	assert(diff.keptNodes[1].name == "object");
	assert(diff.keptNodes[2].name == "std.stdio");
	assert(diff.removedNodes.length == 0);
	assert(diff.addedNodes.length == 0);

	assert(diff.keptEdges.length == 3);
	assert(diff.keptEdges[0].module_.name == "app");
	assert(diff.keptEdges[0].import_.name == "object");
	assert(diff.keptEdges[1].module_.name == "app");
	assert(diff.keptEdges[1].import_.name == "std.stdio");
	assert(diff.keptEdges[2].module_.name == "std.stdio");
	assert(diff.keptEdges[2].import_.name == "object");
	assert(diff.removedEdges.length == 0);
	assert(diff.addedEdges.length == 0);
}

unittest
{
	// Remove node and edge with excludeNames,
	// then omit about the std.conv
	auto before = toGraph(`
app (/app.d) : private : object (/object.d)
app (/app.d) : private : std.conv (/std/conv.d)
app (/app.d) : private : std.stdio (/std/stdio.d)
std.stdio (/std/stdio.d) : private : object (/object.d)
`);
	auto after = toGraph(`
app (/app.d) : private : object (/object.d)
app (/app.d) : private : std.stdio (/std/stdio.d)
std.stdio (/std/stdio.d) : private : object (/object.d)
`);

	auto diff = makeDiff(before, after, DiffSettings("app", 2, ["std.conv"]));

	assert(diff.keptNodes.length == 3);
	assert(diff.keptNodes[0].name == "app");
	assert(diff.keptNodes[1].name == "object");
	assert(diff.keptNodes[2].name == "std.stdio");

	assert(diff.keptEdges.length == 3);
	assert(diff.keptEdges[0].module_.name == "app");
	assert(diff.keptEdges[0].import_.name == "object");
	assert(diff.keptEdges[1].module_.name == "app");
	assert(diff.keptEdges[1].import_.name == "std.stdio");
	assert(diff.keptEdges[2].module_.name == "std.stdio");
	assert(diff.keptEdges[2].import_.name == "object");
	assert(diff.addedEdges.length == 0);
	assert(diff.removedEdges.length == 0);
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

bool isOutputTarget(Node node, int[string] cost, int filter, string[] excludeNames = null)
{
	foreach (excludeName; excludeNames)
	{
		if (node.name == excludeName || node.name.startsWith(chain(excludeName, ".")))
			return false;
	}

	return node.getCost(cost) <= filter;
}

unittest
{
	int[string] cost = ["app" : 0, "std.stdio" : 1, "core.atomic" : 2, "object" : 3];
	assert(isOutputTarget(Node("app"), cost, 1));
	assert(isOutputTarget(Node("std.stdio"), cost, 1));
	assert(!isOutputTarget(Node("core.atomic"), cost, 1));
	assert(!isOutputTarget(Node("object"), cost, 1));

	assert(isOutputTarget(Node("app"), cost, 2));
	assert(isOutputTarget(Node("std.stdio"), cost, 2));
	assert(isOutputTarget(Node("core.atomic"), cost, 2));
	assert(!isOutputTarget(Node("object"), cost, 2));

	assert(isOutputTarget(Node("app"), cost, 1, ["std.stdio"]));
	assert(!isOutputTarget(Node("std.stdio"), cost, 1, ["std.stdio"]));
}

bool isOutputTarget(Edge edge, int[string] cost, int filter, string[] excludeNames = null)
{
	foreach (excludeName; excludeNames)
	{
		if (edge.module_.name == excludeName
				|| edge.module_.name.startsWith(chain(excludeName, ".")))
			return false;
		if (edge.import_.name == excludeName
				|| edge.import_.name.startsWith(chain(excludeName, ".")))
			return false;
	}

	if (edge.import_.getCost(cost) > filter)
		return false;
	if (edge.module_.getCost(cost) >= filter)
		return false;

	return true;
}

unittest
{
	int[string] cost = ["app" : 0, "std.stdio" : 1, "core.atomic" : 2, "object" : 3];
	assert(isOutputTarget(Edge("module", Node("app"), Node("std.stdio")), cost, 1));
	assert(!isOutputTarget(Edge("module", Node("std.stdio"), Node("core.atomic")), cost, 1));
	assert(isOutputTarget(Edge("module", Node("std.stdio"), Node("core.atomic")), cost, 2));

	assert(isOutputTarget(Edge("module", Node("app"), Node("std.stdio")), cost, 1, ["std.conv"]));
	assert(!isOutputTarget(Edge("module", Node("app"), Node("std.stdio")), cost, 1, ["std.stdio"]));
	assert(!isOutputTarget(Edge("module", Node("std.stdio"),
			Node("core.atomic")), cost, 1, ["std.stdio"]));
	assert(!isOutputTarget(Edge("module", Node("std.stdio"),
			Node("core.atomic")), cost, 2, ["std.stdio"]));
}

string sanitizeId(string name)
{
	auto w = appender!string();
	foreach (i, ch; name)
	{
		if (isAlphaNum(ch) || ch == '_')
		{
			w.put(ch);
			continue;
		}
		w.put('_');
	}

	auto result = w.data;
	if (result.length == 0)
		return "_";
	if (isDigit(result[0]))
		result = "_" ~ result;
	return result;
}

unittest
{
	assert(sanitizeId("std.stdio") == "std_stdio");
	assert(sanitizeId("rx/subject") == "rx_subject");
	assert(sanitizeId("1st.core") == "_1st_core");
	assert(sanitizeId("alpha") == "alpha");
}

void renderDot(File f, GraphDiff diff, ModuleEditType[string] moduleSet)
{
	f.writeln("digraph {");
	if (diff.keptNodes.length > 0)
	{
		f.writeln("    {");
		foreach (m; diff.keptNodes)
		{
			f.writefln!"        \"%s\"" (m.name);
		}
		f.writeln("    }");
	}
	if (diff.removedNodes.length > 0)
	{
		f.writeln("    {");
		f.writeln(`        node [style=filled color="#fdaeb7" fillcolor="#ffeef0"];`);
		foreach (m; diff.removedNodes)
		{
			f.writefln!"        \"%s\"" (m.name);
		}
		f.writeln("    }");
	}
	if (diff.addedNodes.length > 0)
	{
		f.writeln("    {");
		f.writeln(`        node [style=filled color="#bef5cb" fillcolor="#e6ffed"];`);
		foreach (m; diff.addedNodes)
		{
			f.writefln!"        \"%s\"" (m.name);
		}
		f.writeln("    }");
	}

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
}

struct MermaidNode
{
	string id;
	string label;
	ModuleEditType kind;
}

void renderMermaid(File f, GraphDiff diff, ModuleEditType[string] moduleSet)
{
	f.writeln("graph TD");
	f.writeln("  classDef kept stroke:#24292e,stroke-width:1px,fill:#ffffff;");
	f.writeln("  classDef added stroke:#2cbe4e,stroke-width:2px,fill:#e6ffed;");
	f.writeln("  classDef removed stroke:#cb2431,stroke-width:2px,fill:#ffeef0;");

	MermaidNode[] nodes;
	void pushNodes(Node[] src, ModuleEditType kind)
	{
		foreach (n; src)
		{
			nodes ~= MermaidNode(sanitizeId(n.name), n.name, kind);
		}
	}
	pushNodes(diff.keptNodes, ModuleEditType.Keep);
	pushNodes(diff.addedNodes, ModuleEditType.Add);
	pushNodes(diff.removedNodes, ModuleEditType.Remove);

	bool[string] seen;
	foreach (n; nodes)
	{
		if (n.id in seen)
			continue;
		seen[n.id] = true;
		f.writefln!"  %s[\"%s\"]"(n.id, n.label);
		final switch (n.kind)
		{
		case ModuleEditType.Keep:
			f.writefln!"  class %s kept;"(n.id);
			break;
		case ModuleEditType.Add:
			f.writefln!"  class %s added;"(n.id);
			break;
		case ModuleEditType.Remove:
			f.writefln!"  class %s removed;"(n.id);
			break;
		}
	}

	size_t edgeIndex = 0;
	void writeEdge(Edge e, string color = null)
	{
		auto fromId = sanitizeId(e.module_.name);
		auto toId = sanitizeId(e.import_.name);
		f.writefln!"  %s --> %s"(fromId, toId);
		if (color.length)
		{
			f.writefln!"  linkStyle %s stroke:%s,stroke-width:2px;"(edgeIndex, color);
		}
		edgeIndex++;
	}

	foreach (m; diff.keptEdges)
	{
		final switch (moduleSet[m.import_.name]) with (ModuleEditType)
		{
		case Keep:
			writeEdge(m);
			break;
		case Remove:
			writeEdge(m, "#cb2431");
			break;
		case Add:
			writeEdge(m, "#2cbe4e");
			break;
		}
	}
	foreach (m; diff.removedEdges)
		writeEdge(m, "#cb2431");
	foreach (m; diff.addedEdges)
		writeEdge(m, "#2cbe4e");
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
app (/app.d) : private : std.conv (/std/conv.d)
`);

	auto diff = makeDiff(before, after, DiffSettings("app", 1));
	auto moduleSet = buildModuleSet(diff);

	auto tmpPath = "test-mermaid.mmd";
	scope (exit)
	{
		if (exists(tmpPath))
			remove(tmpPath);
	}

	auto f = File(tmpPath, "w");
	renderMermaid(f, diff, moduleSet);
	f.close();

	auto content = readText(tmpPath);
	assert(content.canFind("graph TD"));
	assert(content.canFind("classDef added"));
	assert(content.canFind("app --> std_conv"));
}
