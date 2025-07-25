const std = @import("std");

const grammars = @import("../grammars/grammar.zig");
const Symbol = grammars.Symbol;
const Rule = grammars.Rule;

const Item = @import("item.zig").Item;
const Transition = @import("transition.zig").Transition;

pub const State = struct {
    id: usize,
    items: []Item,
    transitions: []Transition,

    /// Implies that items were allocated, or from toOwnedSlice.
    /// State owns items. Caller must deinit state.
    pub fn fromOwnedSlice(id: usize, items: []Item) State {
        return State{
            .id = id,
            .items = items,
            .transitions = &.{},
        };
    }

    pub fn deinit(self: *const State, allocator: std.mem.Allocator) void {
        allocator.free(self.items);
        allocator.free(self.transitions);
    }

    pub fn format(self: *const State, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("State {d}\n", .{self.id});
        for (self.items) |item| {
            try writer.print("  {any}\n", .{item});
        }
        for (self.transitions) |transition| {
            try writer.print("  {any}\n", .{transition});
        }
    }

    pub fn hash(self: *const State) u64 { // id does not matter
        var result: u64 = 0;
        for (self.items) |item| {
            result ^= item.hash();
        }
        return result;
    }

    pub fn addTransition(self: *State, allocator: std.mem.Allocator, transition: Transition) !void {
        if (self.transitions.len == 0) {
            self.transitions = try allocator.alloc(Transition, 1);
        } else {
            self.transitions = try allocator.realloc(self.transitions, self.transitions.len + 1);
        }
        self.transitions[self.transitions.len - 1] = transition;
    }

    pub fn popTransition(self: *State, allocator: std.mem.Allocator) !void {
        self.transitions = try allocator.realloc(self.transitions, self.transitions.len - 1);
    }

    pub const HashContext = struct {
        pub fn hash(_: HashContext, key: State) u64 {
            return key.hash();
        }

        pub fn eql(hash_context: HashContext, a: State, b: State) bool {
            return hash_context.hash(a) == hash_context.hash(b);
        }
    };

    pub fn HashMap(comptime V: type) type {
        return std.HashMap(State, V, HashContext, std.hash_map.default_max_load_percentage);
    }
};

test "state_hash_map" {
    const allocator = std.testing.allocator;

    var items = std.ArrayList(Item).init(allocator);
    defer items.deinit();
    try items.append(Item.from(Rule.from(
        Symbol.from("S"),
        &.{Symbol.from("A")},
    )));

    const state = State.fromOwnedSlice(0, try items.toOwnedSlice());
    defer state.deinit(allocator);

    var hash_map = State.HashMap(void).init(allocator);
    defer hash_map.deinit();
    try hash_map.put(state, {});
    try std.testing.expectEqual(true, hash_map.contains(state));
}
