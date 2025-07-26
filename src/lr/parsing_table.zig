const std = @import("std");

const grammars = @import("../grammars/grammar.zig");
const Symbol = grammars.Symbol;

const lr0 = @import("../lr0/automaton.zig");

const TableAction = union(enum) {
    shift: usize,
    reduce: usize,
    accept,

    pub fn format(self: TableAction, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .shift => |s| try writer.print("s{d}", .{s}),
            .reduce => |r| try writer.print("r{d}", .{r}),
            .accept => try writer.print("acc", .{}),
        }
    }
};

pub const ParsingTable = struct {
    allocator: std.mem.Allocator,
    actions: []std.ArrayList(TableAction),
    gotos: []?usize,
    grammar: *const grammars.Grammar,
    n_terminals: usize,
    n_non_terminals: usize,

    pub fn deinit(self: *ParsingTable) void {
        for (self.actions) |action_list| {
            action_list.deinit();
        }
        self.allocator.free(self.actions);
        self.allocator.free(self.gotos);
    }

    pub fn from_lr0(allocator: std.mem.Allocator, automaton: *const lr0.Automaton) !ParsingTable {
        const n_states = automaton.states.items.len;
        const n_terminals = automaton.grammar.terminals.len;
        const n_non_terminals = automaton.grammar.non_terminals.len;

        const actions = try allocator.alloc(std.ArrayList(TableAction), n_states * (n_terminals + 1)); // +1 for EOF
        @memset(actions, undefined);
        for (0..actions.len) |i| {
            actions[i] = std.ArrayList(TableAction).init(allocator);
        }

        const gotos = try allocator.alloc(?usize, n_states * n_non_terminals);
        @memset(gotos, null);

        for (automaton.states.items) |state| {
            // Rule 1 & 2: GOTO and ACTION-Shift
            for (state.transitions) |transition| {
                if (automaton.grammar.is_terminal(&transition.symbol)) {
                    const terminal_id = automaton.grammar.get_terminal_id(transition.symbol).?;
                    const action_idx = state.id * (n_terminals + 1) + terminal_id;
                    try actions[action_idx].append(.{ .shift = transition.to });
                } else {
                    const non_terminal_id = automaton.grammar.get_non_terminal_id(transition.symbol).?;
                    const goto_idx = state.id * n_non_terminals + non_terminal_id;
                    gotos[goto_idx] = transition.to;
                }
            }

            // Rule 3 & 4: ACTION-Reduce and ACTION-Accept
            for (state.items) |item| {
                if (!item.is_complete()) continue;

                // Accept
                if (item.is_accept_item()) {
                    const eof_idx = state.id * (n_terminals + 1) + n_terminals;
                    try actions[eof_idx].append(.accept);
                    continue;
                }

                // Reduce
                const rule_idx = automaton.grammar.find_rule_idx(item.rule).?;
                for (0..n_terminals) |i| {
                    const action_idx = state.id * (n_terminals + 1) + i;
                    try actions[action_idx].append(.{ .reduce = rule_idx });
                }
                const eof_action_idx = state.id * (n_terminals + 1) + n_terminals;
                try actions[eof_action_idx].append(.{ .reduce = rule_idx });
            }
        }

        return ParsingTable{
            .allocator = allocator,
            .actions = actions,
            .gotos = gotos,
            .grammar = &automaton.grammar,
            .n_terminals = n_terminals,
            .n_non_terminals = n_non_terminals,
        };
    }

    fn writePadding(writer: anytype, n: usize) !void {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            try writer.print(" ", .{});
        }
    }

    pub fn format(self: *const ParsingTable, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        const col_width = 8;

        // Header
        try writer.print("State", .{});
        try writePadding(writer, col_width - 5);
        try writer.print(" | ", .{});
        for (self.grammar.terminals) |terminal| {
            try writer.print("{s}", .{terminal.name});
            try writePadding(writer, col_width - terminal.name.len);
            try writer.print(" | ", .{});
        }
        try writer.print("$", .{});
        try writePadding(writer, col_width - 1);
        try writer.print(" |", .{});

        for (self.grammar.non_terminals) |non_terminal| {
            if (non_terminal.is_augmented()) continue;
            try writer.print(" {s}", .{non_terminal.name});
            try writePadding(writer, col_width - non_terminal.name.len);
            try writer.print(" |", .{});
        }
        try writer.print("\n", .{});

        // Body
        const n_states = self.actions.len / (self.n_terminals + 1);
        for (0..n_states) |i| {
            const state_str_len = std.fmt.count("{d}", .{i});
            try writer.print("{d}", .{i});
            try writePadding(writer, col_width - state_str_len);
            try writer.print(" | ", .{});
            // Actions
            for (0..self.n_terminals) |j| {
                const action_idx = i * (self.n_terminals + 1) + j;
                const action_list = self.actions[action_idx];
                if (action_list.items.len > 0) {
                    var written: usize = 0;
                    for (action_list.items) |action| {
                        try writer.print("{any}", .{action});
                        written += switch (action) {
                            .shift => |s| std.fmt.count("s{d}", .{s}),
                            .reduce => |r| std.fmt.count("r{d}", .{r}),
                            .accept => 3, // "acc"
                        };
                    }
                    try writePadding(writer, col_width - written);
                    try writer.print(" | ", .{});
                } else {
                    try writePadding(writer, col_width);
                    try writer.print(" | ", .{});
                }
            }
            // EOF Action
            const eof_action_idx = i * (self.n_terminals + 1) + self.n_terminals;
            const eof_action_list = self.actions[eof_action_idx];
            if (eof_action_list.items.len > 0) {
                var written: usize = 0;
                for (eof_action_list.items) |action| {
                    try writer.print("{any}", .{action});
                    written += switch (action) {
                        .shift => |s| std.fmt.count("s{d}", .{s}),
                        .reduce => |r| std.fmt.count("r{d}", .{r}),
                        .accept => 3, // "acc"
                    };
                }
                try writePadding(writer, col_width - written);
                try writer.print(" |", .{});
            } else {
                try writePadding(writer, col_width);
                try writer.print(" |", .{});
            }

            // Gotos
            for (0..self.n_non_terminals) |j| {
                const non_terminal = self.grammar.non_terminals[j];
                if (non_terminal.is_augmented()) continue;

                const goto_idx = i * self.n_non_terminals + j;
                if (self.gotos[goto_idx]) |goto_state| {
                    const written = std.fmt.count("{d}", .{goto_state});
                    try writer.print(" {d}", .{goto_state});
                    try writePadding(writer, col_width - written);
                    try writer.print(" |", .{});
                } else {
                    try writer.print(" ", .{});
                    try writePadding(writer, col_width);
                    try writer.print(" |", .{});
                }
            }
            try writer.print("\n", .{});
        }
    }
};

test "parsing table from lr0 automaton" {
    const allocator = std.testing.allocator;
    const grammar = try grammars.examples.ShiftReduceGrammar(allocator);
    var automaton = lr0.Automaton.init(allocator, grammar);
    defer automaton.deinit();
    try automaton.build();

    var table = try ParsingTable.from_lr0(allocator, &automaton);
    defer table.deinit();

    std.debug.print("\n{any}\n", .{table});
}

test "root tests" {
    std.testing.refAllDecls(@This());
}
