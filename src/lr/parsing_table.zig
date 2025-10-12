const std = @import("std");

const grammars = @import("../grammars/grammar.zig");
const Symbol = grammars.Symbol;

const lr0 = @import("../lr0/automaton.zig");

const FixedTable = @import("../utils/utils.zig").FixedTable;

const Action = @import("action.zig").Action;

/// See Dragonbook 4.5.3 Shift-Reduce Parsing
/// Action enriched with state numbers
const TableAction = union(Action) {
    /// Shift and go to state `shift`
    shift: usize,
    /// Reduce by grammar rule which number is `reduce`
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

const Conflict = struct {
    state: usize,
    symbol: Symbol,
    actions: [2]TableAction, // TODO: perhaps more than 2?

    // e.g. {f}/{f} -> s1/r2
    pub fn format(self: Conflict, writer: *std.io.Writer) !void {
        // _ = self;
        // try writer.print("conflict", .{});
        for (self.actions, 0..2) |action, idx| {
            try action.format(writer);
            if (idx != self.actions.len - 1) { // not last
                try writer.print("/", .{});
            }
        }
    }
};

// Each cell can contain either a single action or a conflict (a list of conflicting actions)
const ActionOrConflict = union(enum) {
    action: TableAction,
    conflict: Conflict,

    pub fn format(self: ActionOrConflict, writer: *std.io.Writer) !void {
        switch (self) {
            .action => |a| try a.format(writer),
            .conflict => |c| try c.format(writer),
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
/// Each cell is nullable, null basically means unreachable
pub const ParsingTable = struct {
    n_states: usize,
    grammar: *const grammars.Grammar,
    action: FixedTable(?ActionOrConflict),
    goto: FixedTable(?usize),

    pub fn from_lr0(allocator: std.mem.Allocator, automaton: *const lr0.Automaton) !ParsingTable {
        const n_states = automaton.states.items.len;
        const n_terminals = automaton.grammar.terminals.len;
        const n_non_terminals = automaton.grammar.non_terminals.len;
        const action_table = try FixedTable(?ActionOrConflict).init(allocator, n_states, n_terminals, null);
        const goto_table = try FixedTable(?usize).init(allocator, n_states, n_non_terminals - 1, null);

        for (automaton.states.items) |state| {
            // TODO: figure out where did I get these rules... (perhaps from the Dragon Book? Check)

            // Rule 1 & 2: GOTO and ACTION-Shift
            for (state.transitions) |transition| {
                if (automaton.grammar.is_terminal(&transition.symbol)) {
                    const terminal_id = automaton.grammar.get_terminal_id(transition.symbol).?;
                    action_table.data[state.id][terminal_id] = ActionOrConflict{
                        .action = TableAction{ .shift = transition.to },
                    };
                } else {
                    const non_terminal_id = automaton.grammar.get_non_terminal_id(transition.symbol).? - 1; // -1 because we don't want the augmented start symbol in the GOTO table
                    goto_table.data[state.id][non_terminal_id] = transition.to;
                }
            }

            // // Rule 3 & 4: ACTION-Reduce and ACTION-Accept
            for (state.items) |item| {
                if (!item.is_complete()) continue;

                // Accept
                if (item.is_accept_item()) {
                    const eof_id = automaton.grammar.get_terminal_id(Symbol.from("$")).?;
                    action_table.data[state.id][eof_id] = ActionOrConflict{
                        .action = TableAction{ .accept = {} },
                    };
                    continue;
                }

                // Reduce
                const rule_idx = automaton.grammar.find_rule_idx(item.rule).?;
                for (automaton.grammar.terminals) |terminal| {
                    const terminal_id = automaton.grammar.get_terminal_id(terminal).?;
                    const reduce_action = TableAction{ .reduce = rule_idx };
                    // TODO: this code implies that existing_action is always an action, but what if it's a conflict?
                    // Then we override it and lose information about the previous conflict.
                    // In that case it would be better to extend the array of actions in the existing conflict.
                    if (action_table.data[state.id][terminal_id]) |existing_action| {
                        const conflict = Conflict{
                            .state = state.id,
                            .symbol = terminal,
                            .actions = [2]TableAction{ existing_action.action, reduce_action },
                        };
                        action_table.data[state.id][terminal_id] = ActionOrConflict{ .conflict = conflict };
                        continue;
                    }

                    action_table.data[state.id][terminal_id] = ActionOrConflict{ .action = reduce_action };
                }
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
    }

    // TODO: improve formatting, by pre-computing max length of each column
    pub fn format(self: *const ParsingTable, writer: *std.io.Writer) !void {
        // print header
        try writer.print("State\t| ACTION", .{});
        for (0..self.grammar.terminals.len - 1) |_| {
            try writer.print("\t|", .{});
        }
        try writer.print(" GOTO\n", .{});

        // row that prints terminals and non-terminals columns
        try writer.print("\t|", .{});
        for (self.grammar.terminals) |t| {
            try writer.print(" {f}\t|", .{t});
        }
        for (self.grammar.non_terminals) |nt| {
            if (nt.is_augmented()) continue; // skip augmented start symbol
            try writer.print(" {f}\t|", .{nt});
        }
        try writer.print("\n", .{});

        // actual state rows
        for (0..self.n_states) |state| {
            try writer.print("{d}\t|", .{state});

            for (self.action.data[state]) |cell| {
                if (cell) |c| {
                    try writer.print(" {f}\t|", .{c});
                } else {
                    try writer.print(" -\t|", .{});
                }
            }

            for (self.goto.data[state]) |cell| {
                if (cell) |c| {
                    try writer.print(" {d}\t|", .{c});
                } else {
                    try writer.print(" -\t|", .{});
                }
            }

            try writer.print("\n", .{});
        }
        try writer.print("\n", .{});
    }
};

test "This test prints a parsing table for a simple grammar" {
    const allocator = std.testing.allocator;
    const grammar = try grammars.examples.SimpleGrammar(allocator);

    std.debug.print("Grammar:\n{f}\n", .{grammar});

    var automaton = lr0.Automaton.init(allocator, grammar);
    defer automaton.deinit();
    try automaton.build();
    for (automaton.states.items) |state| {
        std.debug.print("{f}", .{state});
    }

    var table = try ParsingTable.from_lr0(allocator, &automaton);
    defer table.deinit(allocator);
    std.debug.print("\nParsing Table:\n{f}", .{table});
}
