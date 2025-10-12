const std = @import("std");

pub const Symbol = @import("symbol.zig").Symbol;
pub const Rule = @import("rules.zig").Rule;
pub const examples = @import("examples.zig");
pub const validator = @import("validator.zig");

/// Grammar is a deterministic context-free grammar. Written in Backus-Naur form.
/// StaticGrammar – read-only view, no allocation, no deinit. Safe only while
/// the borrowed slices remain alive. Feed it into `GrammarBuilder` to mutate.
pub const StaticGrammar = struct {
    start_symbol: Symbol,
    terminals: []const Symbol,
    non_terminals: []const Symbol,
    rules: []const Rule,

    /// Creates a new static grammar.
    /// To modify the grammar, use GrammarBuilder.
    pub fn from(
        start_symbol: Symbol,
        terminals: []const Symbol,
        non_terminals: []const Symbol,
        rules: []const Rule,
    ) StaticGrammar {
        return StaticGrammar{
            .start_symbol = start_symbol,
            .terminals = terminals,
            .non_terminals = non_terminals,
            .rules = rules,
        };
    }

    pub fn format(self: *const StaticGrammar, writer: *std.io.Writer) !void {
        for (self.rules) |rule| {
            try writer.print("{f} .\n", .{rule});
        }
    }
};

/// Grammar – owning, immutable. Produced by `GrammarBuilder`; must be
/// `deinit`ed or dropped with its arena.  `asStatic()` returns a view.
/// Note: `GrammarBuilder.fromOwned()` moves data out of a Grammar; conversely
/// `builder.toOwnedGrammar()` moves it out of the builder – only one owner at
/// a time.
pub const Grammar = struct {
    start_symbol: Symbol,
    terminals: []Symbol,
    non_terminals: []Symbol,
    rules: []Rule,
    is_augmented: bool = false,

    pub fn deinit(self: *const Grammar, allocator: std.mem.Allocator) void {
        allocator.free(self.terminals);
        allocator.free(self.non_terminals);
        if (self.is_augmented) {
            allocator.free(self.rules[0].rhs);
        }
        allocator.free(self.rules);
    }

    pub fn asStaticView(self: *const Grammar) StaticGrammar {
        return StaticGrammar{
            .start_symbol = self.start_symbol,
            .terminals = self.terminals,
            .non_terminals = self.non_terminals,
            .rules = self.rules,
        };
    }

    pub fn find_rule_idx(self: *const Grammar, rule: Rule) ?usize {
        for (self.rules, 0..) |r, i| {
            if ((Rule.HashContext{}).eql(r, rule)) return i;
        }
        return null;
    }

    pub fn get_terminal_id(self: *const Grammar, symbol: Symbol) ?usize {
        for (self.terminals, 0..) |s, i| {
            if (s.eql(&symbol)) return i;
        }
        return null;
    }

    pub fn get_non_terminal_id(self: *const Grammar, symbol: Symbol) ?usize {
        for (self.non_terminals, 0..) |s, i| {
            if (s.eql(&symbol)) return i;
        }
        return null;
    }

    /// Start rule is the rule which lhs is the start symbol.
    /// Augmented grammars have a new start symbol S' and a new rule S' -> S.
    ///
    /// Unaugmented grammars may have multiple rules with the same lhs as the start symbol.
    /// E.g. S -> A | B. which is basically two rules S -> A and S -> B.
    ///
    /// It means we may not want to use this function for unaugmented grammars.
    pub fn get_start_rule(self: *const Grammar) error{GrammarIsNotAugmented}!Rule {
        if (!self.is_augmented) {
            return error.GrammarIsNotAugmented;
        }

        return self.rules[0];
    }

    pub fn is_terminal(self: *const Grammar, symbol: *const Symbol) bool {
        for (self.terminals) |terminal| {
            if (terminal.eql(symbol)) {
                return true;
            }
        }
        return false;
    }

    pub fn format(self: *const Grammar, writer: *std.io.Writer) !void {
        if (self.is_augmented) try writer.print("(augmented)\n", .{});
        try writer.print("{f}", .{self.asStaticView()});
    }
};

/// GrammarBuilder – stack-local mutable builder. Owns its memory until
/// `toOwnedGrammar()`/`toAugmented()` transfers it to a `Grammar`. Never
/// return a live builder; move its data first.
pub const GrammarBuilder = struct {
    allocator: std.mem.Allocator,
    terminals: std.ArrayList(Symbol),
    non_terminals: std.ArrayList(Symbol),
    rules: std.ArrayList(Rule),
    start_symbol: Symbol,
    was_moved: bool = false, // If the GrammarBuilder was moved, we don't need to free the memory.

    /// Build a mutable builder from a StaticGrammar.
    /// All slices are **copied** with `allocator`, so the input view stays valid.
    ///
    /// @deprecated Use `fromRules` instead, it sets terminals and non-terminals automatically.
    pub fn fromStaticGrammar(
        allocator: std.mem.Allocator,
        grammar: StaticGrammar,
    ) error{OutOfMemory}!GrammarBuilder {
        // Copy slices to owned memory.
        const terminals = try allocator.dupe(Symbol, grammar.terminals);
        const non_terminals = try allocator.dupe(Symbol, grammar.non_terminals);
        const rules = try allocator.dupe(Rule, grammar.rules);

        return GrammarBuilder{
            .allocator = allocator,
            .terminals = std.ArrayList(Symbol).fromOwnedSlice(terminals),
            .non_terminals = std.ArrayList(Symbol).fromOwnedSlice(non_terminals),
            .rules = std.ArrayList(Rule).fromOwnedSlice(rules),
            .start_symbol = grammar.start_symbol,
        };
    }

    /// Improved version that sets terminals and non-terminals automatically from rules.
    pub fn fromRules(allocator: std.mem.Allocator, rules: []const Rule) error{ OutOfMemory, EmptyRules }!GrammarBuilder {
        if (rules.len == 0) {
            return error.EmptyRules; // Grammar needs at least one start symbol, without a rule, there's no start symbol.
        }

        const owned_rules = try allocator.dupe(Rule, rules);
        errdefer allocator.free(owned_rules);

        var lhs_set = Symbol.ArrayHashMap(void).init(allocator);
        defer lhs_set.deinit();

        // We use lhs_set to distinguish terminals from non-terminals, but we fill non_terminals_list using rhs symbols,
        // so that if rules are like:
        // S -> A OP B
        // A -> a
        // B -> d
        // OP -> +
        // we get non-terminals as follows: S, A, OP, B, not S, A, B, OP
        for (owned_rules) |rule| {
            try lhs_set.put(rule.lhs, {});
        }

        var seen_symbols = Symbol.ArrayHashMap(void).init(allocator);
        defer seen_symbols.deinit();
        var terminals_list = std.ArrayList(Symbol).empty;
        var non_terminals_list = std.ArrayList(Symbol).empty;

        for (owned_rules) |rule| {
            if (!seen_symbols.contains(rule.lhs)) {
                try seen_symbols.put(rule.lhs, {});
                try non_terminals_list.append(allocator, rule.lhs);
            }
            for (rule.rhs) |symbol| {
                if (seen_symbols.contains(symbol)) continue;
                try seen_symbols.put(symbol, {});
                if (lhs_set.contains(symbol)) {
                    try non_terminals_list.append(allocator, symbol);
                } else {
                    try terminals_list.append(allocator, symbol);
                }
            }
        }

        return GrammarBuilder{
            .allocator = allocator,
            .terminals = terminals_list,
            .non_terminals = non_terminals_list,
            .rules = std.ArrayList(Rule).fromOwnedSlice(owned_rules),
            .start_symbol = rules[0].lhs,
        };
    }

    /// Build a builder by **moving** data out of an owning Grammar.
    /// After the call `base_grammar`'s slices are empty and the builder now
    /// owns them.
    pub fn fromOwnedGrammar(
        allocator: std.mem.Allocator,
        grammar: Grammar,
    ) error{OutOfMemory}!GrammarBuilder {
        return GrammarBuilder{
            .allocator = allocator,
            .terminals = std.ArrayList(Symbol).fromOwnedSlice(grammar.terminals),
            .non_terminals = std.ArrayList(Symbol).fromOwnedSlice(grammar.non_terminals),
            .rules = std.ArrayList(Rule).fromOwnedSlice(grammar.rules),
            .start_symbol = grammar.start_symbol,
        };
    }

    pub fn deinit(self: *GrammarBuilder) void {
        if (self.was_moved) {
            std.log.warn("GrammarBuilder data was moved, no need to deinit\n", .{});
        }

        self.terminals.deinit(self.allocator);
        self.non_terminals.deinit(self.allocator);
        self.rules.deinit(self.allocator);
    }

    /// Returns a new static grammar. View does not own anything.
    pub fn asStaticView(self: *const GrammarBuilder) StaticGrammar {
        return StaticGrammar{
            .start_symbol = self.start_symbol,
            .terminals = self.terminals.items,
            .non_terminals = self.non_terminals.items,
            .rules = self.rules.items,
        };
    }

    /// Grammar takes ownership of the underlying memory of the GrammarBuilder.
    /// Caller must free the memory.
    pub fn toOwnedGrammar(self: *GrammarBuilder) !Grammar {
        return Grammar{
            .start_symbol = self.start_symbol,
            .terminals = try self.terminals.toOwnedSlice(self.allocator),
            .non_terminals = try self.non_terminals.toOwnedSlice(self.allocator),
            .rules = try self.rules.toOwnedSlice(self.allocator),
        };
    }

    /// Adds a new start symbol S' and a new rule S' -> S.
    /// Returns a new StaticGrammar that takes ownership of the underlying memory of the GrammarBuilder.
    /// Caller must free the memory.
    pub fn toAugmentedGrammar(self: *GrammarBuilder) error{OutOfMemory}!Grammar {
        self.was_moved = true;

        const s_prime = Symbol.from("S'");
        try self.non_terminals.insert(self.allocator, 0, s_prime);

        const eof = Symbol.from("$");
        try self.terminals.append(self.allocator, eof);

        const rhs = try self.allocator.dupe(Symbol, &.{
            self.start_symbol,
                // TODO: eof here does not change the output. Research why
                // require the input to be fully consumed (ending with '$'), and clarify if omitting 'eof'
                // is correct for this grammar or if there is a bug in the parser or grammar construction.
                // eof,
        });
        const augmented_rule = Rule.from(s_prime, rhs);

        try self.rules.insert(self.allocator, 0, augmented_rule);
        self.start_symbol = s_prime;

        return Grammar{
            .start_symbol = self.start_symbol,
            .terminals = try self.terminals.toOwnedSlice(self.allocator),
            .non_terminals = try self.non_terminals.toOwnedSlice(self.allocator),
            .rules = try self.rules.toOwnedSlice(self.allocator),
            .is_augmented = true,
        };
    }
};

test "expression grammar" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const grammar = try examples.ExpressionGrammar(allocator);
    std.log.info("expression grammar:\n{f}\n", .{grammar});

    var builder = try GrammarBuilder.fromOwnedGrammar(allocator, grammar);
    const augmented_grammar = try builder.toAugmentedGrammar();

    std.log.info("augmented grammar:\n{f}\n", .{augmented_grammar});
}

test "grammar validation" {
    const allocator = std.testing.allocator;
    const grammar = try examples.ExpressionGrammar(allocator);
    defer grammar.deinit(allocator);

    validator.GrammarValidator.validate(&grammar.asStaticView()) catch |err| {
        std.log.err("grammar validation failed: {any}\n", .{err});
        unreachable; // No error for a valid grammar.
    };
}

test "is_terminal" {
    const allocator = std.testing.allocator;
    const grammar = try examples.ExpressionGrammar(allocator);
    defer grammar.deinit(allocator);

    try std.testing.expect(grammar.is_terminal(&Symbol.from("(")));
    try std.testing.expect(grammar.is_terminal(&Symbol.from(")")));
    try std.testing.expect(grammar.is_terminal(&Symbol.from("number")));

    try std.testing.expect(!grammar.is_terminal(&Symbol.from("exp")));
    try std.testing.expect(!grammar.is_terminal(&Symbol.from("term")));
    try std.testing.expect(!grammar.is_terminal(&Symbol.from("factor")));
}

test "fromRules builds a grammar correctly" {
    const allocator = std.testing.allocator;

    const S = Symbol.from("S");
    const A = Symbol.from("A");
    const a = Symbol.from("a");
    const b = Symbol.from("b");

    const rules = &.{
        Rule.from(S, &.{ A, A }),
        Rule.from(A, &.{a}),
        Rule.from(A, &.{b}),
    };

    var builder = try GrammarBuilder.fromRules(allocator, rules);
    defer builder.deinit();

    const grammar = try builder.toOwnedGrammar();
    defer grammar.deinit(allocator);

    try std.testing.expectEqual(S, grammar.start_symbol);
    try std.testing.expectEqual(2, grammar.non_terminals.len); // S, A
    try std.testing.expectEqual(2, grammar.terminals.len); // a, b
}

test "fromRules with empty rules returns an error" {
    _ = GrammarBuilder.fromRules(
        std.testing.allocator,
        &.{},
    ) catch |err| {
        try std.testing.expectEqual(error.EmptyRules, err);
        return;
    };

    unreachable; // Should have returned an error.
}
