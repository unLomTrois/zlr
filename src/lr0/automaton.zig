const std = @import("std");

const grammars = @import("../grammars/grammar.zig");
const Symbol = grammars.Symbol;
const Grammar = grammars.Grammar;
const GrammarBuilder = grammars.GrammarBuilder;
const Rule = grammars.Rule;

const Item = @import("../lr/item.zig").Item;
const State = @import("../lr/state.zig").State;
const Action = @import("../lr/action.zig").Action;

const Transition = struct {
    from: usize,
    to: usize,
    symbol: Symbol,

    pub fn format(self: *const Transition, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("goto({}, {})\t-> {}", .{ self.from, self.symbol, self.to });
    }

    const HashContext = struct {
        pub fn hash(_: HashContext, key: u64) u32 {
            return @truncate(key);
        }

        pub fn eql(_: HashContext, a: u64, b: u64, _: usize) bool {
            return a == b;
        }
    };

    pub fn HashMap(comptime V: type) type {
        return std.ArrayHashMap(V, Transition, HashContext, true);
    }
};

pub const Automaton = struct {
    allocator: std.mem.Allocator,
    grammar: Grammar,
    states: std.ArrayList(State),
    transitions: Transition.HashMap(u64),

    pub fn init(allocator: std.mem.Allocator, grammar: Grammar) Automaton {
        return Automaton{
            .allocator = allocator,
            .grammar = grammar,
            .states = std.ArrayList(State).init(allocator),
            .transitions = Transition.HashMap(u64).init(allocator),
        };
    }

    pub fn deinit(self: *Automaton) void {
        for (self.states.items) |state| {
            state.deinit(self.allocator);
        }
        self.states.deinit();
        self.grammar.deinit(self.allocator);
        self.transitions.deinit();
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
        const initial_state = State.fromOwnedSlice(0, initial_items);
        try self.states.append(initial_state);

        try self.build_states();
    }

    fn build_states(self: *Automaton) !void {
        var state_hash_map = State.HashMap(void).init(self.allocator);
        defer state_hash_map.deinit();

        var i: usize = 1;
        var state_iter = State.ArrayListIter.from(&self.states);
        while (state_iter.next()) |state| {
            var unique_iter = Item.UniqueIter.init(self.allocator, state.items);
            defer unique_iter.deinit();
            while (try unique_iter.next()) |item| {
                const dot_symbol = item.dot_symbol() orelse continue;

                const goto_items = try self.GOTO(state.items, dot_symbol, self.allocator);

                const new_state = State.fromOwnedSlice(i, goto_items);

                if (state_hash_map.contains(new_state)) {
                    new_state.deinit(self.allocator);
                    continue;
                }

                const transition_hash = self.calc_transition_hash(new_state, dot_symbol);
                try self.transitions.put(transition_hash, .{
                    .from = state.id,
                    .to = new_state.id,
                    .symbol = dot_symbol,
                });

                try state_hash_map.put(new_state, {});

                try self.states.append(new_state); // Automaton owns new_state and deinit it

                i += 1;
            }
        }
    }

    fn calc_transition_hash(_: *Automaton, state: State, symbol: Symbol) u64 {
        return (Symbol.HashContext{}).hash(symbol) ^ @as(u64, state.id);
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

test "automaton does not leak with non-arena allocator" {
    const allocator = std.testing.allocator;
    const grammar = try grammars.examples.SimpleCycleGrammar(allocator);
    var automaton = Automaton.init(allocator, grammar);
    defer automaton.deinit();
    try automaton.build();
}

const LRError = error{ ShiftReduceConflict, ReduceReduceConflict } || std.mem.Allocator.Error;

// Check whether items with the same pre-dot symbol have different actions
// e.g.   [shift] cycle -> id • + id
//        [reduce] factor -> id •
// This is a shift-reduce conflict
fn validate_state(state: State, allocator: std.mem.Allocator, toLog: bool) LRError!void {
    var action_map = Symbol.HashMap(Action).init(allocator);
    defer action_map.deinit();

    if (toLog) {
        std.debug.print("\n{s}", .{state});
    }

    for (state.items) |item| {
        const top_stack_symbol = item.pre_dot_symbol() orelse Symbol.Epsilon; // epsilon for A -> • B cases

        const current_action = action_map.get(top_stack_symbol) orelse {
            try action_map.put(top_stack_symbol, item.action);
            continue;
        };

        if (current_action != item.action) {
            return error.ShiftReduceConflict;
        }

        if (current_action == item.action and current_action == .reduce) {
            return error.ReduceReduceConflict;
        }
    }
}

fn validate_automaton(states: []const State, allocator: std.mem.Allocator) LRError!void {
    for (states) |state| {
        validate_state(state, allocator, true) catch |err| {
            std.debug.print("error: {any}\n", .{err});

            return err;
        };
    }
}

test "shift-reduce conflict" {
    const allocator = std.testing.allocator;
    const grammar = try grammars.examples.SimpleCycleGrammar(allocator);
    var automaton = Automaton.init(allocator, grammar);
    defer automaton.deinit();
    try automaton.build();

    validate_automaton(automaton.states.items, allocator) catch |err| {
        try std.testing.expectEqual(LRError.ShiftReduceConflict, err);
    };
}

test "reduce-reduce conflict" {
    const allocator = std.testing.allocator;
    const grammar = try grammars.examples.ReduceReduceConflictGrammar(allocator);
    var automaton = Automaton.init(allocator, grammar);
    defer automaton.deinit();
    try automaton.build();

    validate_automaton(automaton.states.items, allocator) catch |err| {
        try std.testing.expectEqual(LRError.ReduceReduceConflict, err);
    };
}
