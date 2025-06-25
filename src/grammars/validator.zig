const std = @import("std");

const Symbol = @import("grammar.zig").Symbol;
const StaticGrammar = @import("grammar.zig").StaticGrammar;
const Rule = @import("grammar.zig").Rule;

pub const GrammarError = error{
    /// The start symbol was not found in the rules.
    /// E.g. the start symbol is S, but there is no rule that starts with S.
    StartSymbolNotFoundInRules,

    /// The start symbol is not a non-terminal.
    StartSymbolIsNotNonTerminal,

    EmptyTerminals,
    EmptyNonTerminals,
    EmptyRules,

    DuplicateTerminal,
    DuplicateNonTerminal,
    OverlapBetweenSets,

    LhsIsTerminal,
    LhsIsNotNonTerminal,
    UnknownSymbolInRhs,

    UnreachableNonTerminal,
    NonProductiveNonTerminal,
} || std.mem.Allocator.Error; // OutOfMemory

pub const GrammarValidator = struct {
    const Self = @This();

    pub fn validate(grammar: *const StaticGrammar) GrammarError!void {
        try Self.validate_sets(grammar);
        try Self.validate_start_symbol(grammar);
    }

    fn validate_sets(grammar: *const StaticGrammar) error{
        EmptyTerminals,
        EmptyNonTerminals,
        EmptyRules,
    }!void {
        if (grammar.terminals.len == 0) {
            return GrammarError.EmptyTerminals;
        }
        if (grammar.non_terminals.len == 0) {
            return GrammarError.EmptyNonTerminals;
        }
        if (grammar.rules.len == 0) {
            return GrammarError.EmptyRules;
        }
    }

    fn validate_start_symbol(grammar: *const StaticGrammar) error{
        StartSymbolNotFoundInRules,
        StartSymbolIsNotNonTerminal,
    }!void {
        // First make sure at least one rule has the start symbol on the LHS.
        const found_in_rules = blk: {
            for (grammar.rules) |rule| {
                if (rule.lhs.eql(grammar.start_symbol)) {
                    break :blk true;
                }
            }
            break :blk false;
        };

        if (!found_in_rules) {
            return GrammarError.StartSymbolNotFoundInRules;
        }

        const found_in_non_terminals = blk: {
            for (grammar.non_terminals) |non_terminal| {
                if (non_terminal.eql(grammar.start_symbol)) {
                    break :blk true;
                }
            }
            break :blk false;
        };

        if (!found_in_non_terminals) {
            return GrammarError.StartSymbolIsNotNonTerminal;
        }
    }
};

test "GrammarError.StartSymbolNotFoundInRules" {
    const S = Symbol.from("S");
    const A = Symbol.from("A");
    const a = Symbol.from("a");

    const failing_grammar = StaticGrammar.from(
        S,
        &.{a},
        &.{ S, A },
        &.{
            // Rule.from(S, &.{A}), // This is missing
            Rule.from(A, &.{a}),
        },
    );

    GrammarValidator.validate(&failing_grammar) catch |err| {
        try std.testing.expectEqual(GrammarError.StartSymbolNotFoundInRules, err);
        return;
    };
}

test "GrammarError.StartSymbolIsNotNonTerminal" {
    const S = Symbol.from("S");
    const A = Symbol.from("A");
    const a = Symbol.from("a");

    const failing_grammar = StaticGrammar.from(
        S,
        &.{a},
        &.{
            // S, // This is missing
            A,
        },
        &.{
            Rule.from(S, &.{ A, A }),
            Rule.from(A, &.{a}),
        },
    );

    GrammarValidator.validate(&failing_grammar) catch |err| {
        try std.testing.expectEqual(GrammarError.StartSymbolIsNotNonTerminal, err);
        return;
    };
}
