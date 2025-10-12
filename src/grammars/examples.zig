const std = @import("std");
const Grammar = @import("grammar.zig").Grammar;
const Symbol = @import("symbol.zig").Symbol;
const Rule = @import("rules.zig").Rule;
const GrammarBuilder = @import("grammar.zig").GrammarBuilder;
const StaticGrammar = @import("grammar.zig").StaticGrammar;

/// Returns an owned expression grammar. Designed for expressions like `(1 + 2) * 3`.
/// Caller must deinit the grammar.
///
/// Grammar:
/// exp -> exp + term
/// exp -> term
/// term -> term * factor
/// term -> factor
/// factor -> ( exp )
/// factor -> number
pub fn ExpressionGrammar(allocator: std.mem.Allocator) !Grammar {
    const number = Symbol.from("number");
    const plus = Symbol.from("+");
    const times = Symbol.from("*");
    const lparen = Symbol.from("(");
    const rparen = Symbol.from(")");
    const exp = Symbol.from("exp");
    const term = Symbol.from("term");
    const factor = Symbol.from("factor");

    var builder = try GrammarBuilder.fromRules(allocator, &.{
        Rule.from(exp, &.{ exp, plus, term }), // exp -> exp + term
        Rule.from(exp, &.{term}), // exp -> term
        Rule.from(term, &.{ term, times, factor }), // term -> term * factor
        Rule.from(term, &.{factor}), // term -> factor
        Rule.from(factor, &.{ lparen, exp, rparen }), // factor -> ( exp )
        Rule.from(factor, &.{number}), // factor -> number
    });

    return try builder.toOwnedGrammar();
}

// S -> A OP B.
// A -> id.
// B -> id.
// OP -> + | - | * | /
pub fn SimpleGrammar(allocator: std.mem.Allocator) !Grammar {
    const id = Symbol.from("id");
    const plus = Symbol.from("+");
    const minus = Symbol.from("-");
    const times = Symbol.from("*");
    const divide = Symbol.from("/");
    const S = Symbol.from("S");
    const A = Symbol.from("A");
    const B = Symbol.from("B");
    const OP = Symbol.from("OP");

    var builder = try GrammarBuilder.fromRules(allocator, &.{
        Rule.from(S, &.{ A, OP, B }), // S -> A OP B
        Rule.from(A, &.{id}), // A -> id
        Rule.from(B, &.{id}), // B -> id
        Rule.from(OP, &.{plus}), // OP -> +
        Rule.from(OP, &.{minus}), // OP -> -
        Rule.from(OP, &.{times}), // OP -> *
        Rule.from(OP, &.{divide}), // OP -> /
    });

    return try builder.toOwnedGrammar();
}

// cycle -> id "+" id | factor.
// factor -> "(" cycle ")" | id.
pub fn ShiftReduceGrammar(allocator: std.mem.Allocator) !Grammar {
    const id = Symbol.from("id");
    const plus = Symbol.from("+");
    const lparen = Symbol.from("(");
    const rparen = Symbol.from(")");
    const cycle = Symbol.from("cycle");
    const factor = Symbol.from("factor");

    var builder = try GrammarBuilder.fromRules(allocator, &.{
        Rule.from(cycle, &.{ id, plus, id }), // cycle -> id + id
        Rule.from(cycle, &.{factor}), // cycle -> factor
        Rule.from(factor, &.{ lparen, cycle, rparen }), // factor -> ( cycle )
        Rule.from(factor, &.{id}), // factor -> id
    });

    return try builder.toOwnedGrammar();
}

// S -> A | B .
// A -> c .
// B-> c .
pub fn ReduceReduceGrammar(allocator: std.mem.Allocator) !Grammar {
    const c = Symbol.from("c");
    const S = Symbol.from("S");
    const A = Symbol.from("A");
    const B = Symbol.from("B");

    var builder = try GrammarBuilder.fromRules(allocator, &.{
        Rule.from(S, &.{A}), // S -> A
        Rule.from(S, &.{B}), // S -> B
        Rule.from(A, &.{c}), // A -> c
        Rule.from(B, &.{c}), // B -> c
    });

    return try builder.toOwnedGrammar();
}

test "expression grammar" {
    const allocator = std.testing.allocator;
    const grammar = try ExpressionGrammar(allocator);
    defer grammar.deinit(allocator);
    try std.testing.expectEqual(grammar.terminals.len, 5);
}

// TODO: it is a bad test, rewrite please
test "augmented expression grammar" {
    const allocator = std.testing.allocator;
    const grammar = try ExpressionGrammar(allocator);

    var builder = try GrammarBuilder.fromOwnedGrammar(allocator, grammar);
    const augmented_grammar = try builder.toAugmentedGrammar();
    defer augmented_grammar.deinit(allocator);

    try std.testing.expect(augmented_grammar.start_symbol.eql(&Symbol.from("S'")));
}

/// Caller must deinit the grammar.
fn createAugmentedGrammar(allocator: std.mem.Allocator) !Grammar {
    const grammar = try ExpressionGrammar(allocator);
    var builder = try GrammarBuilder.fromOwnedGrammar(allocator, grammar);
    return try builder.toAugmentedGrammar();
}

test "dangling pointer bug demonstration" {
    const allocator = std.testing.allocator;

    // Create the augmented grammar in a separate function
    const augmented_grammar = try createAugmentedGrammar(allocator);
    defer augmented_grammar.deinit(allocator);
    // This should crash or produce garbage because the rhs slice
    // in the first rule (S' -> exp) is now pointing to overwritten memory
    std.log.info("Augmented grammar rules:\n", .{});
    for (augmented_grammar.rules) |rule| {
        std.log.info("Rule: {f} -> ", .{rule.lhs});
        for (rule.rhs) |symbol| {
            std.log.info("{f} ", .{symbol});
        }
        std.log.info("\n", .{});
    }

    // This assertion will likely fail due to corrupted memory
    try std.testing.expect(augmented_grammar.start_symbol.eql(&Symbol.from("S'")));
}
