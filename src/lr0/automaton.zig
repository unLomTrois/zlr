const std = @import("std");

const grammars = @import("../grammars/grammar.zig");
const Symbol = grammars.Symbol;
const Grammar = grammars.Grammar;
const GrammarBuilder = grammars.GrammarBuilder;
const Rule = grammars.Rule;

const Item = @import("../lr/item.zig").Item;
const State = @import("../lr/state.zig").State;
const Action = @import("../lr/action.zig").Action;
const utils = @import("../utils/iter.zig");

pub const LR0Validator = @import("validator.zig").LR0Validator;

// TODO: move to State?
const Transition = struct {
    from: usize,
    to: usize,
    symbol: Symbol,

    pub fn format(self: *const Transition, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("goto({}, {})\t-> {}", .{ self.from, self.symbol, self.to });
    }

    pub fn hash(self: *const Transition) u64 {
        return @as(u64, self.from) + self.symbol.hash() ^ @as(u64, self.to);
    }

    pub const HashContext = struct {
        pub fn hash(_: HashContext, key: u64) u32 {
            return @truncate(key);
        }

        pub fn eql(_: HashContext, a: u64, b: u64, _: usize) bool {
            return a == b;
        }
    };
    // TODO: refactor
    pub fn ArrayHashMap(comptime K: type) type {
        return std.ArrayHashMap(K, Transition, HashContext, true);
    }
};

pub const Automaton = struct {
    allocator: std.mem.Allocator,
    grammar: Grammar,
    states: std.ArrayList(State),
    transitions: Transition.ArrayHashMap(u64),

    pub fn init(allocator: std.mem.Allocator, grammar: Grammar) Automaton {
        return Automaton{
            .allocator = allocator,
            .grammar = grammar,
            .states = std.ArrayList(State).init(allocator),
            .transitions = Transition.ArrayHashMap(u64).init(allocator),
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

    pub fn build(self: *Automaton) !void {
        // Augment the grammar
        var builder = try GrammarBuilder.fromOwnedGrammar(self.allocator, self.grammar);
        const augmented_grammar = try builder.toAugmentedGrammar();
        self.grammar = augmented_grammar;

        const start_rule = try self.grammar.get_start_rule();
        const start_item = Item.from(start_rule);
        const initial_items = try self.CLOSURE(&.{start_item}, self.allocator);
        const initial_state = State.fromOwnedSlice(0, initial_items);

        try self.build_states(initial_state);
    }

    fn build_states(self: *Automaton, initial_state: State) !void {
        try self.states.append(initial_state);

        var seen_states = State.HashMap(void).init(self.allocator);
        defer seen_states.deinit();

        var id_counter: usize = 1;
        var work_list = utils.WorkListIter(State).from(&self.states);
        while (work_list.next()) |state| {
            var seen_symbols = Symbol.ArrayHashMap(void).init(self.allocator);
            defer seen_symbols.deinit();

            for (state.items) |item| {
                if (!item.is_incomplete()) continue;
                const dot_symbol = item.dot_symbol().?;
                if (seen_symbols.contains(dot_symbol)) continue;
                try seen_symbols.put(dot_symbol, {});

                const goto_items = try self.GOTO(state.items, dot_symbol, self.allocator);
                const new_state = State.fromOwnedSlice(id_counter, goto_items);

                var transition = Transition{
                    .from = state.id,
                    .to = new_state.id,
                    .symbol = dot_symbol,
                };

                if (seen_states.getKey(new_state)) |existing_state| {
                    transition.to = existing_state.id;
                    const transition_hash = transition.hash();
                    try self.transitions.put(transition_hash, transition);

                    new_state.deinit(self.allocator);
                    continue;
                }

                const transition_hash = transition.hash();
                try self.transitions.put(transition_hash, transition);

                try seen_states.put(new_state, {});
                try self.states.append(new_state);

                id_counter += 1;
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
        try closure_items.appendSlice(items);

        var seen_symbols = Symbol.HashMap(void).init(allocator);
        defer seen_symbols.deinit();

        var work_list = utils.WorkListIter(Item).from(&closure_items);
        while (work_list.next()) |item| {
            if (!item.is_incomplete()) continue;

            const dot_symbol = item.dot_symbol().?;

            if (self.grammar.is_terminal(dot_symbol)) continue;

            if (seen_symbols.contains(dot_symbol)) continue;

            try seen_symbols.put(dot_symbol, {});

            for (self.grammar.rules) |rule| {
                if (!rule.lhs.eqlTo(dot_symbol)) continue;
                const new_item = Item.from(rule);
                try closure_items.append(new_item);
            }
        }

        return try closure_items.toOwnedSlice();
    }

    fn GOTO(self: *Automaton, items: []const Item, symbol: Symbol, allocator: std.mem.Allocator) std.mem.Allocator.Error![]Item {
        var goto_items = std.ArrayList(Item).init(allocator);
        defer goto_items.deinit();

        for (items) |item| {
            if (!item.is_incomplete()) continue;
            if (!item.dot_symbol().?.eqlTo(symbol)) continue;
            const new_item = item.advance_dot_clone();
            try goto_items.append(new_item);
        }

        return try self.CLOSURE(goto_items.items, allocator);
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

    for (automaton.transitions.values()) |transition| {
        std.debug.print("{any}\n", .{transition});
    }
}

test "root tests" {
    std.testing.refAllDecls(@This());
}
