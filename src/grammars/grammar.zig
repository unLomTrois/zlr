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

    pub fn is_terminal(self: *const Grammar, symbol: Symbol) bool {
        for (self.terminals) |terminal| {
            if (terminal.eqlTo(symbol)) {
                return true;
            }
        }
        return false;
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
    pub fn fromStaticGrammar(
        allocator: std.mem.Allocator,
        grammar: StaticGrammar,
    ) error{OutOfMemory}!GrammarBuilder {
        // Copy slices to owned memory.
        const terminals = try Symbol.fromSlice(allocator, grammar.terminals);
        const non_terminals = try Symbol.fromSlice(allocator, grammar.non_terminals);
        const rules = try Rule.fromSlice(allocator, grammar.rules);

        return GrammarBuilder{
            .allocator = allocator,
            .terminals = std.ArrayList(Symbol).fromOwnedSlice(allocator, terminals),
            .non_terminals = std.ArrayList(Symbol).fromOwnedSlice(allocator, non_terminals),
            .rules = std.ArrayList(Rule).fromOwnedSlice(allocator, rules),
            .start_symbol = grammar.start_symbol,
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
            .terminals = std.ArrayList(Symbol).fromOwnedSlice(allocator, grammar.terminals),
            .non_terminals = std.ArrayList(Symbol).fromOwnedSlice(allocator, grammar.non_terminals),
            .rules = std.ArrayList(Rule).fromOwnedSlice(allocator, grammar.rules),
            .start_symbol = grammar.start_symbol,
        };
    }

    pub fn deinit(self: *const GrammarBuilder) void {
        if (self.was_moved) {
            std.log.warn("GrammarBuilder data was moved, no need to deinit\n", .{});
        }

        self.terminals.deinit();
        self.non_terminals.deinit();
        self.rules.deinit();
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
            .terminals = try self.terminals.toOwnedSlice(),
            .non_terminals = try self.non_terminals.toOwnedSlice(),
            .rules = try self.rules.toOwnedSlice(),
        };
    }

    /// Adds a new start symbol S' and a new rule S' -> S.
    /// Returns a new StaticGrammar that takes ownership of the underlying memory of the GrammarBuilder.
    /// Caller must free the memory.
    pub fn toAugmentedGrammar(self: *GrammarBuilder) error{OutOfMemory}!Grammar {
        self.was_moved = true;

        const s_prime = Symbol.from("S'");
        try self.non_terminals.insert(0, s_prime);

        const augmented_rule = Rule.from(s_prime, try Symbol.fromSlice(
            self.allocator,
            &.{self.start_symbol},
        ));
        try self.rules.insert(0, augmented_rule);
        self.start_symbol = s_prime;

        return Grammar{
            .start_symbol = self.start_symbol,
            .terminals = try self.terminals.toOwnedSlice(),
            .non_terminals = try self.non_terminals.toOwnedSlice(),
            .rules = try self.rules.toOwnedSlice(),
            .is_augmented = true,
        };
    }
};

test "full conversion cycle: static → builder → owned → builder → static" {
    const allocator = std.testing.allocator;

    // Start with a static grammar
    const S = Symbol.from("S");
    const A = Symbol.from("A");
    const a = Symbol.from("a");
    const b = Symbol.from("b");

    const original_static = StaticGrammar.from(
        S,
        &.{ a, b },
        &.{ S, A },
        &.{
            Rule.from(S, &.{ A, A }),
            Rule.from(A, &.{a}),
            Rule.from(A, &.{b}),
        },
    );

    // Convert static → builder
    var builder = try GrammarBuilder.fromStaticGrammar(allocator, original_static);

    // Convert builder → owned
    const g = try builder.toOwnedGrammar();

    // Convert owned → builder (by treating owned)
    builder = try GrammarBuilder.fromOwnedGrammar(allocator, g);

    // add a new symbol
    const c = Symbol.from("c");
    try builder.non_terminals.append(c);
    defer builder.deinit();

    // Convert builder → static
    const final_static = builder.asStaticView();

    // check that the new symbol is not in the grammar
    try std.testing.expect(final_static.non_terminals[final_static.non_terminals.len - 1].eql(c));
}

test "expression grammar" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const grammar = try examples.ExpressionGrammar(allocator);

    std.log.info("expression grammar:\n{any}\n", .{grammar});

    var builder = try GrammarBuilder.fromOwnedGrammar(allocator, grammar);
    const augmented_grammar = try builder.toAugmentedGrammar();

    std.log.info("augmented grammar:\n{any}\n", .{augmented_grammar});
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

    try std.testing.expect(grammar.is_terminal(Symbol.from("(")));
    try std.testing.expect(grammar.is_terminal(Symbol.from(")")));
    try std.testing.expect(grammar.is_terminal(Symbol.from("number")));

    try std.testing.expect(!grammar.is_terminal(Symbol.from("exp")));
    try std.testing.expect(!grammar.is_terminal(Symbol.from("term")));
    try std.testing.expect(!grammar.is_terminal(Symbol.from("factor")));
}
