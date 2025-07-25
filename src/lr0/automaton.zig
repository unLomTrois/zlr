const std = @import("std");
const assert = std.debug.assert;

const utils = @import("../utils/iter.zig");

const grammars = @import("../grammars/grammar.zig");
const Symbol = grammars.Symbol;
const Grammar = grammars.Grammar;
const GrammarBuilder = grammars.GrammarBuilder;
const Rule = grammars.Rule;

const Item = @import("../lr/item.zig").Item;
const State = @import("../lr/state.zig").State;
const Action = @import("../lr/action.zig").Action;
const Transition = @import("../lr/transition.zig").Transition;

pub const LR0Validator = @import("validator.zig").LR0Validator;

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
        for (self.states.items) |state| {
            state.deinit(self.allocator);
        }
        self.states.deinit();
        self.grammar.deinit(self.allocator);
    }

    pub fn build(self: *Automaton) !void {
        try self.augment_grammar();
        try self.init_states();
        try self.build_states();
    }

    fn augment_grammar(self: *Automaton) !void {
        var builder = try GrammarBuilder.fromOwnedGrammar(self.allocator, self.grammar);
        const augmented_grammar = try builder.toAugmentedGrammar();
        self.grammar = augmented_grammar;
    }

    fn init_states(self: *Automaton) !void {
        const start_rule = try self.grammar.get_start_rule();
        const start_item = Item.from(start_rule);
        const initial_items = try self.CLOSURE(&.{start_item});
        const initial_state = State.fromOwnedSlice(0, initial_items);
        try self.states.append(initial_state);
    }

    fn build_states(self: *Automaton) !void {
        var seen_states = State.HashMap(void).init(self.allocator);
        defer seen_states.deinit();

        var work_list = utils.WorkListIter(State).from(&self.states);
        while (work_list.next()) |state| {
            try self.build_state(&state, &seen_states);
        }
    }

    fn build_state(self: *Automaton, state: *const State, seen_states: *State.HashMap(void)) !void {
        var seen_symbols = Symbol.ArrayHashMap(void).init(self.allocator);
        defer seen_symbols.deinit();

        for (state.items) |item| {
            if (item.is_complete()) continue;
            const dot_symbol = item.dot_symbol().?;
            if (seen_symbols.contains(dot_symbol)) continue;
            try seen_symbols.put(dot_symbol, {});

            const goto_items = try self.GOTO(state.items, &dot_symbol);
            const new_id: usize = self.states.getLast().id + 1;
            const new_state = State.fromOwnedSlice(new_id, goto_items);

            var transition = Transition{
                .from = state.id,
                .to = new_state.id,
                .symbol = dot_symbol,
            };

            var mutable_state = &self.states.items[state.id];
            try mutable_state.addTransition(self.allocator, transition);

            if (seen_states.getKey(new_state)) |existing_state| {
                try mutable_state.popTransition(self.allocator);
                transition.to = existing_state.id;
                try mutable_state.addTransition(self.allocator, transition);

                new_state.deinit(self.allocator);
                continue;
            }

            try seen_states.put(new_state, {});
            try self.states.append(new_state);
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
    fn CLOSURE(self: *Automaton, items: []const Item) std.mem.Allocator.Error![]Item {
        var closure_items = std.ArrayList(Item).init(self.allocator);
        try closure_items.appendSlice(items);

        var seen_symbols = Symbol.HashMap(void).init(self.allocator);
        defer seen_symbols.deinit();

        var work_list = utils.WorkListIter(Item).from(&closure_items);
        while (work_list.next()) |item| {
            if (item.is_complete()) continue;

            const dot_symbol = item.dot_symbol().?;

            if (self.grammar.is_terminal(&dot_symbol)) continue;

            if (seen_symbols.contains(dot_symbol)) continue;

            try seen_symbols.put(dot_symbol, {});

            for (self.grammar.rules) |rule| {
                if (!rule.lhs.eql(&dot_symbol)) continue;
                const new_item = Item.from(rule);
                try closure_items.append(new_item);
            }
        }

        return try closure_items.toOwnedSlice();
    }

    fn GOTO(self: *Automaton, items: []const Item, symbol: *const Symbol) std.mem.Allocator.Error![]Item {
        var goto_items = std.ArrayList(Item).init(self.allocator);
        defer goto_items.deinit();

        for (items) |item| {
            if (item.is_complete()) continue;

            assert(item.dot_symbol() != null);
            if (!item.dot_symbol().?.eql(symbol)) continue;

            const new_item = item.advance_dot_clone();
            try goto_items.append(new_item);
        }

        return try self.CLOSURE(goto_items.items);
    }
};

test "automaton does not leak with non-arena allocator" {
    const allocator = std.testing.allocator;
    const grammar = try grammars.examples.ShiftReduceGrammar(allocator);
    var automaton = Automaton.init(allocator, grammar);
    defer automaton.deinit();
    try automaton.build();

    for (automaton.states.items) |state| {
        std.debug.print("{s}", .{state});
    }

    // for (automaton.transitions.values()) |transition| {
    //     std.debug.print("{any}\n", .{transition});
    // }
}

test "root tests" {
    std.testing.refAllDecls(@This());
}
