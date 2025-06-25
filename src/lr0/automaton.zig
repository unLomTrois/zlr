const std = @import("std");

const grammars = @import("../grammars/grammar.zig");
const Symbol = grammars.Symbol;
const Grammar = grammars.Grammar;
const GrammarBuilder = grammars.GrammarBuilder;
const Rule = grammars.Rule;

const Item = @import("../lr/item.zig").Item;

const State = @import("../lr/state.zig").State;

pub const Automaton = struct {
    allocator: std.mem.Allocator,
    grammar: Grammar,
    states: std.ArrayList(State),

    pub fn init(allocator: std.mem.Allocator, grammar: Grammar) Automaton {
        return Automaton{
            .allocator = allocator,
            .grammar = grammar,
            .states = std.ArrayList(State).init(allocator),
        };
    }

    pub fn deinit(self: *Automaton) void {
        self.states.deinit();
        self.grammar.deinit(self.allocator);
    }

    fn build(self: *Automaton) !void {
        // Augment the grammar
        var builder = try GrammarBuilder.fromOwnedGrammar(self.allocator, self.grammar);
        const augmented_grammar = try builder.toAugmentedGrammar();
        self.grammar = augmented_grammar;

        // Get the start rule
        const start_rule = try self.grammar.get_start_rule();
        const start_item = Item.from(start_rule);

        // Compute the initial closure
        const initial_items = try self.CLOSURE(&.{start_item}, self.allocator);
        const initial_state = try State.init(self.allocator, 0, initial_items);
        defer initial_state.deinit(self.allocator);

        try self.states.append(initial_state);

        try self.build_states();

        for (self.states.items) |state| {
            std.debug.print("{any}\n", .{state});
        }
    }

    fn build_states(self: *Automaton) !void {
        var state_iter = State.ArrayListIter.from(&self.states);

        var state_hash_map = State.HashMap(void).init(self.allocator);
        defer state_hash_map.deinit();

        var i: usize = 1;
        while (state_iter.next()) |state| {
            var unique_iter = Item.UniqueIter.init(self.allocator, state.items);
            defer unique_iter.deinit();
            while (try unique_iter.next()) |item| : (i += 1) {
                const dot_symbol = item.dot_symbol() orelse continue;

                const goto_items = try self.GOTO(state.items, dot_symbol, self.allocator);

                const new_state = try State.init(self.allocator, i, goto_items);

                if (state_hash_map.contains(new_state)) continue;

                try state_hash_map.put(new_state, {});

                try self.states.append(new_state);
            }
        }
    }

    /// CLOSURE computes the CLOSURE of a set of items.
    /// CLOSURE(I): For any item A -> α • B β in a state I (where B is a non-terminal),
    /// we add all of B's productions (B -> • γ) to the state.
    /// This is repeated until no new items can be added.
    ///
    /// Example: for the following grammar:
    /// S -> A a
    /// A -> B b
    /// B -> c
    ///
    /// CLOSURE(S -> • A a) would be:
    /// S -> • A a
    /// A -> • B b
    /// B -> • c
    fn CLOSURE(self: *Automaton, items: []const Item, allocator: std.mem.Allocator) std.mem.Allocator.Error![]Item {
        var closure_items = std.ArrayList(Item).init(allocator);
        var seen_symbols = Symbol.HashMap(void).init(allocator);
        defer seen_symbols.deinit();

        try closure_items.appendSlice(items);

        var item_iter = Item.IncompleteIter.from(&closure_items);
        while (item_iter.next()) |item| { // iter works as a work-list here
            const dot_symbol = item.dot_symbol().?; // item is not complete, so dot symbol is always present

            if (self.grammar.is_terminal(dot_symbol)) continue; // skip terminals, they don't have any productions

            if (seen_symbols.contains(dot_symbol)) continue;

            try seen_symbols.put(dot_symbol, {});

            var rule_iter = self.grammar.rulesForSymbol(dot_symbol);
            while (rule_iter.next()) |rule| {
                const new_item = Item.from(rule);
                try closure_items.append(new_item);
            }
        }

        return try closure_items.toOwnedSlice();
    }

    fn GOTO(self: *Automaton, items: []const Item, symbol: Symbol, allocator: std.mem.Allocator) std.mem.Allocator.Error![]Item {
        var goto_items = std.ArrayList(Item).init(allocator);
        defer goto_items.deinit();

        var item_iter = Item.FilterDotSymbolIter.from(items, symbol);
        while (item_iter.next()) |item| {
            // std.debug.print("{any}\n", .{item});
            const new_item = item.advance_dot_clone();
            try goto_items.append(new_item);
        }

        return try self.CLOSURE(goto_items.items, allocator);
    }
};

test "automaton" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const grammar = try grammars.examples.SimpleGrammar(arena_allocator);

    var automaton = Automaton.init(arena_allocator, grammar);
    defer automaton.deinit();

    try automaton.build();

    // try std.testing.expect(automaton.states.items.len == 1);

    // std.debug.print("automaton:\n{any}\n", .{automaton});
}
