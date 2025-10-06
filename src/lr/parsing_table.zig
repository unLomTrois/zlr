const std = @import("std");

const grammars = @import("../grammars/grammar.zig");
const Symbol = grammars.Symbol;

const lr0 = @import("../lr0/automaton.zig");

const FixedTable = @import("../utils/utils.zig").FixedTable;

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
    // No err because jumping to a cell with null means there is no way to continue parsing, implicit error
    // err

    pub fn format(self: TableAction, writer: *std.io.Writer) !void {
        switch (self) {
            .shift => |s| try writer.print("s{d}", .{s}),
            .reduce => |r| try writer.print("r{d}", .{r}),
            .accept => try writer.print("acc", .{}),
        }
    }
};

/// State   | ACTION                     | GOTO           |
///         | id | +     | (  | )  |  $  | cycle | factor |
/// 0       | s2 |       | s4 |    |     | 1     | 3      |
/// 1       |    |       |    |    | acc |       |        |
/// 2       | r4 | s5/r4 | r4 | r4 | r4  |       |        |
/// ...
///
/// Action table is n_states x n_terminals
/// Goto table is n_states x n_nonterminals
pub const ParsingTable = struct {
    n_states: usize,
    grammar: *const grammars.Grammar,
    action: FixedTable(?TableAction),
    goto: FixedTable(?usize),

    pub fn from_lr0(allocator: std.mem.Allocator, automaton: *const lr0.Automaton) !ParsingTable {
        const n_states = automaton.states.items.len;
        const n_terminals = automaton.grammar.terminals.len;
        const n_non_terminals = automaton.grammar.non_terminals.len;
        const action_table = try FixedTable(?TableAction).init(allocator, n_states, n_terminals, null);
        const goto_table = try FixedTable(?usize).init(allocator, n_states, n_non_terminals, null);

        std.debug.print("Number of states: {d}\n", .{n_states});

        for (automaton.states.items) |state| {
            // Rule 1 & 2: GOTO and ACTION-Shift
            for (state.transitions) |transition| {
                if (automaton.grammar.is_terminal(&transition.symbol)) {
                    const terminal_id = automaton.grammar.get_terminal_id(transition.symbol).?;
                    action_table.data[state.id][terminal_id] = TableAction{ .shift = transition.to };
                } else {
                    // TODO FORMAT THEM
                    const non_terminal_id = automaton.grammar.get_non_terminal_id(transition.symbol).?;
                    goto_table.data[state.id][non_terminal_id] = transition.to;
                }
            }

            // TODO: figure out where did I get these rules... (perhaps from the Dragon Book? Check)

            // // Rule 3 & 4: ACTION-Reduce and ACTION-Accept
            for (state.items) |item| {
                if (!item.is_complete()) continue;

                // Accept
                if (item.is_accept_item()) {
                    const eof_id = automaton.grammar.get_terminal_id(Symbol.from("$")).?;
                    action_table.data[state.id][eof_id] = TableAction{ .accept = {} };
                    continue;
                }

                // // Reduce
                // const rule_idx = automaton.grammar.find_rule_idx(item.rule).?;
                // for (0..n_terminals) |i| {
                //     const action_idx = state.id * (n_terminals + 1) + i;
                //     try action_table.data[action_idx].append(allocator, .{ .reduce = rule_idx });
                // }
                // const eof_action_idx = state.id * (n_terminals + 1) + n_terminals;
                // try action_table.data[eof_action_idx].append(allocator, .{ .reduce = rule_idx });
            }
        }

        return ParsingTable{
            .n_states = n_states,
            .action = action_table,
            .goto = goto_table,
            .grammar = &automaton.grammar,
        };
    }

    pub fn deinit(self: *ParsingTable, allocator: std.mem.Allocator) void {
        self.action.deinit(allocator);
        self.goto.deinit(allocator);
        // allocator.free(self.goto);
    }

    pub fn format(self: *const ParsingTable, writer: *std.io.Writer) !void {
        // print header
        try writer.print("State\t| ACTION \n", .{});
        try writer.print("\t|", .{});
        for (self.grammar.terminals) |t| {
            try writer.print(" {f}\t |", .{t});
        }
        try writer.print("\n", .{});

        for (0..self.n_states) |state| {
            try writer.print("{d}\t|", .{state});

            for (self.action.data[state]) |cell| {
                if (cell) |c| {
                    try writer.print(" {f}\t |", .{c});
                } else {
                    try writer.print(" -\t |", .{});
                }
            }
            try writer.print("\n", .{});
        }
        try writer.print("\n", .{});
    }
};

test "This test prints a parsing table for a simple grammar" {
    const allocator = std.testing.allocator;
    const grammar = try grammars.examples.ShiftReduceGrammar(allocator);

    var automaton = lr0.Automaton.init(allocator, grammar);
    defer automaton.deinit();
    try automaton.build();

    std.debug.print("\nTerminals:\n", .{});
    for (grammar.terminals) |t| {
        std.debug.print("{f} ", .{t});
    }

    var table = try ParsingTable.from_lr0(allocator, &automaton);
    defer table.deinit(allocator);
    std.debug.print("\nParsing Table:\n{f}", .{table});
    std.debug.print("\nAction table\n{any}", .{table.action.data});
}
