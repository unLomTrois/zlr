// TODO: remove this file

const std = @import("std");

const grammars = @import("../grammars/grammar.zig");
const Symbol = grammars.Symbol;

const lr0 = @import("../lr0/automaton.zig");

/// See Dragonbook 4.5.3 Shift-Reduce Parsing
const TableAction = union(enum) {
    /// Shift the next input symbol onto the top of the stack.
    shift: usize,
    /// The right end of the string to be reduced must be at the top of
    /// the stack. Locate the left end of the string within the stack and decide
    /// with what nonterminal to replace the string.
    reduce: usize,
    /// Announce successful completion of parsing.
    accept,

    pub fn format(self: TableAction, writer: *std.io.Writer) !void {
        switch (self) {
            .shift => |s| try writer.print("s{d}", .{s}),
            .reduce => |r| try writer.print("r{d}", .{r}),
            .accept => try writer.print("acc", .{}),
        }
    }
};

const TableEntry = struct {
    actions: []TableAction,

    pub fn init() !TableEntry {
        return TableEntry{
            .actions = &.{},
        };
    }

    pub fn deinit(self: *TableEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.actions);
    }

    pub fn append(self: *TableEntry, allocator: std.mem.Allocator, action: TableAction) !void {
        if (self.actions.len == 0) {
            self.actions = try allocator.alloc(TableAction, 1);
            self.actions[0] = action;
        } else {
            self.actions = try allocator.realloc(self.actions, self.actions.len + 1);
            self.actions[self.actions.len - 1] = action;
        }
    }

    pub fn format(self: *const TableEntry, writer: *std.io.Writer) !void {
        if (self.actions.len == 0) {
            try writer.print("empty", .{});
        } else if (self.actions.len == 1) {
            try writer.print("{f}", .{self.actions[0]});
        } else {
            for (self.actions, 0..self.actions.len) |action, i| {
                try writer.print("{f}", .{action});
                if (i < self.actions.len - 1) {
                    try writer.print(" / ", .{});
                }
            }
        }
    }
};

// test "table entry" {
//     const allocator = std.testing.allocator;
//     var entry = try TableEntry.init();
//     defer entry.deinit(allocator);
//     try entry.append(allocator, .{ .shift = 1 });

//     std.debug.print("{[value]s:_^[width]}\n", .{
//         .value = "hi",
//         .width = 10,
//     });
//     var buf: [32]u8 = undefined;

//     const r1 = try std.fmt.bufPrint(&buf, "|{[value]s: ^8}|", .{ .value = "hi" });
//     std.debug.print("{s}", .{r1});

//     const result = try std.fmt.bufPrint(&buf, "|{[value]f:_^8}|", .{ .value = entry });
//     try std.testing.expectEqualStrings("|   s1   |", result);

//     try entry.append(allocator, .{ .reduce = 2 });
//     const result2 = try std.fmt.bufPrint(&buf, "| {any:>8} |", .{entry});
//     try std.testing.expectEqualStrings("| s1, r2 |", result2);

//     var entry2 = try TableEntry.init();
//     try entry2.append(allocator, .{ .accept = {} });
//     defer entry2.deinit(allocator);
//     const result3 = try std.fmt.bufPrint(&buf, "{f}", .{entry2});
//     try std.testing.expectEqualStrings("acc", result3);
// }

pub const ActionTable = struct {
    allocator: std.mem.Allocator,
    data: []std.ArrayList(TableAction),
    n_terminals: usize, // number of terminals in the grammar (not counting EOF)

    pub fn init(allocator: std.mem.Allocator, n_states: usize, n_terminals: usize) !ActionTable {
        const entries = try allocator.alloc(std.ArrayList(TableAction), n_states * (n_terminals + 1)); // +1 for EOF
        @memset(entries, undefined);
        for (0..entries.len) |i| {
            entries[i] = std.ArrayList(TableAction).empty;
        }
        return ActionTable{
            .allocator = allocator,
            .data = entries,
            .n_terminals = n_terminals,
        };
    }

    pub fn deinit(self: *ActionTable) void {
        for (self.data) |*list| {
            list.deinit(self.allocator);
        }
        self.allocator.free(self.data);
    }
};

pub const GotoTable = struct {
    allocator: std.mem.Allocator,
    data: []?usize,
    n_non_terminals: usize,

    pub fn init(allocator: std.mem.Allocator, n_states: usize, n_non_terminals: usize) !GotoTable {
        const entries = try allocator.alloc(?usize, n_states * n_non_terminals);
        @memset(entries, null);
        return GotoTable{
            .allocator = allocator,
            .data = entries,
            .n_non_terminals = n_non_terminals,
        };
    }

    pub fn deinit(self: *GotoTable) void {
        self.allocator.free(self.data);
    }
};

pub const ParsingTable = struct {
    allocator: std.mem.Allocator,
    action_table: ActionTable,
    goto_table: GotoTable,
    grammar: *const grammars.Grammar,
    n_terminals: usize,
    n_non_terminals: usize,

    pub fn deinit(self: *ParsingTable) void {
        self.action_table.deinit();
        self.goto_table.deinit();
    }

    pub fn from_lr0(allocator: std.mem.Allocator, automaton: *const lr0.Automaton) !ParsingTable {
        const n_states = automaton.states.items.len;
        const n_terminals = automaton.grammar.terminals.len;
        const n_non_terminals = automaton.grammar.non_terminals.len;

        var action_table = try ActionTable.init(allocator, n_states, n_terminals);
        var goto_table = try GotoTable.init(allocator, n_states, n_non_terminals);

        for (automaton.states.items) |state| {
            // Rule 1 & 2: GOTO and ACTION-Shift
            for (state.transitions) |transition| {
                if (automaton.grammar.is_terminal(&transition.symbol)) {
                    const terminal_id = automaton.grammar.get_terminal_id(transition.symbol).?;
                    const action_idx = state.id * (n_terminals + 1) + terminal_id;
                    try action_table.data[action_idx].append(allocator, .{ .shift = transition.to });
                } else {
                    const non_terminal_id = automaton.grammar.get_non_terminal_id(transition.symbol).?;
                    const goto_idx = state.id * n_non_terminals + non_terminal_id;
                    goto_table.data[goto_idx] = transition.to;
                }
            }

            // Rule 3 & 4: ACTION-Reduce and ACTION-Accept
            for (state.items) |item| {
                if (!item.is_complete()) continue;

                // Accept
                if (item.is_accept_item()) {
                    const eof_idx = state.id * (n_terminals + 1) + n_terminals;
                    try action_table.data[eof_idx].append(allocator, .accept);
                    continue;
                }

                // Reduce
                const rule_idx = automaton.grammar.find_rule_idx(item.rule).?;
                for (0..n_terminals) |i| {
                    const action_idx = state.id * (n_terminals + 1) + i;
                    try action_table.data[action_idx].append(allocator, .{ .reduce = rule_idx });
                }

                // fill EOF column because this version of table had no $ terminal in grammar
                const eof_action_idx = state.id * (n_terminals + 1) + n_terminals;
                try action_table.data[eof_action_idx].append(allocator, .{ .reduce = rule_idx });
            }
        }

        return ParsingTable{
            .allocator = allocator,
            .action_table = action_table,
            .goto_table = goto_table,
            .grammar = &automaton.grammar,
            .n_terminals = n_terminals,
            .n_non_terminals = n_non_terminals,
        };
    }

    fn writePadding(writer: *std.io.Writer, n: usize) !void {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            try writer.print(" ", .{});
        }
    }

    pub fn format(self: *const ParsingTable, writer: *std.io.Writer) !void {
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
        const n_states = self.action_table.data.len / (self.n_terminals + 1);
        for (0..n_states) |i| {
            const state_str_len = std.fmt.count("{d}", .{i});
            try writer.print("{d}", .{i});
            try writePadding(writer, col_width - state_str_len);
            try writer.print(" | ", .{});
            // Actions
            for (0..self.n_terminals) |j| {
                const action_idx = i * (self.n_terminals + 1) + j;
                const action_list = self.action_table.data[action_idx];
                if (action_list.items.len > 0) {
                    var written: usize = 0;
                    for (action_list.items) |action| {
                        try writer.print("{f}", .{action});
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
            const eof_action_list = self.action_table.data[eof_action_idx];
            if (eof_action_list.items.len > 0) {
                var written: usize = 0;
                for (eof_action_list.items) |action| {
                    try writer.print("{f}", .{action});
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
                if (self.goto_table.data[goto_idx]) |goto_state| {
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

    const src = @src();
    std.debug.print("\n{s}:{d}:{d} Parsing Table:\n", .{ src.file, src.line, src.column });
    std.debug.print("{f}\n", .{table});
}

test "root tests" {
    std.testing.refAllDecls(@This());
}
