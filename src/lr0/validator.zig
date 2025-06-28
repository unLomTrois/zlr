const std = @import("std");

const Automaton = @import("automaton.zig").Automaton;

const State = @import("../lr/state.zig").State;
const Action = @import("../lr/action.zig").Action;
const Symbol = @import("../grammars/symbol.zig").Symbol;

const grammars = @import("../grammars/grammar.zig");

const LR0Error = error{ ShiftReduceConflict, ReduceReduceConflict } || std.mem.Allocator.Error;

pub const LR0Validator = struct {
    states: *std.ArrayList(State),
    idx: usize,
    allocator: std.mem.Allocator,
    toLog: bool = true,

    pub fn from(states: *std.ArrayList(State), allocator: std.mem.Allocator) LR0Validator {
        return LR0Validator{ .states = states, .idx = 0, .allocator = allocator };
    }

    pub fn next(self: *LR0Validator) ?StateAndError {
        if (self.idx >= self.states.items.len) return null;

        const state = self.states.items[self.idx];
        self.idx += 1;

        validate_state(state, self.allocator, self.toLog) catch |err| {
            if (self.toLog) {
                std.debug.print("{any}\n", .{err});
            }
            return StateAndError{ .state = state, .err = err };
        };

        return StateAndError{ .state = state, .err = null };
    }

    const StateAndError = struct {
        state: State,
        err: ?LR0Error,
    };

    fn validate_state(state: State, allocator: std.mem.Allocator, toLog: bool) LR0Error!void {
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
};

test "shift-reduce conflict" {
    const allocator = std.testing.allocator;
    const grammar = try grammars.examples.ShiftReduceGrammar(allocator);
    var automaton = Automaton.init(allocator, grammar);
    defer automaton.deinit();
    try automaton.build();

    var iter = LR0Validator.from(&automaton.states, allocator);
    while (iter.next()) |state_and_error| {
        if (state_and_error.err) |err| {
            try std.testing.expectEqual(LR0Error.ShiftReduceConflict, err);
        }
    }
}

test "reduce-reduce conflict" {
    const allocator = std.testing.allocator;
    const grammar = try grammars.examples.ReduceReduceGrammar(allocator);
    var automaton = Automaton.init(allocator, grammar);
    defer automaton.deinit();
    try automaton.build();

    var iter = LR0Validator.from(&automaton.states, allocator);
    while (iter.next()) |state_and_error| {
        if (state_and_error.err) |err| {
            try std.testing.expectEqual(LR0Error.ReduceReduceConflict, err);
        }
    }
}
