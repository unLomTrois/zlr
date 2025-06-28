const std = @import("std");

const grammars = @import("../grammars/grammar.zig");
const Symbol = grammars.Symbol;
const Rule = grammars.Rule;

const Item = @import("item.zig").Item;

pub const State = struct {
    id: usize,
    items: []Item,

    /// Implies that items were allocated, or from toOwnedSlice.
    /// State owns items. Caller must deinit state.
    pub fn fromOwnedSlice(id: usize, items: []Item) State {
        return State{
            .id = id,
            .items = items,
        };
    }

    pub fn initDupe(allocator: std.mem.Allocator, id: usize, items: []const Item) !State {
        return State{
            .id = id,
            .items = try allocator.dupe(Item, items),
        };
    }

    pub fn deinit(self: *const State, allocator: std.mem.Allocator) void {
        allocator.free(self.items);
    }

    pub const ArrayListIter = struct {
        list: *std.ArrayList(State),
        idx: usize = 0,

        pub inline fn from(list: *std.ArrayList(State)) ArrayListIter {
            return ArrayListIter{ .list = list, .idx = 0 };
        }

        pub fn next(self: *ArrayListIter) ?State {
            while (self.idx < self.list.items.len) {
                const state = self.list.items[self.idx];
                self.idx += 1;
                return state;
            }
            return null;
        }
    };

    pub fn format(self: *const State, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("State {d}\n", .{self.id});
        for (self.items) |item| {
            try writer.print("  {any}\n", .{item});
        }
    }

    const HashContext = struct {
        pub fn hash(_: HashContext, key: State) u64 {
            var result: u64 = 0;
            for (key.items) |item| {
                const item_hash = (Item.HashContext{}).hash(item);
                if (item_hash == 0) {
                    result = item_hash;
                } else result ^= item_hash;
            }
            return result;
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

    const state = try State.initDupe(allocator, 0, &.{
        Item.from(
            Rule.from(
                Symbol.from("S"),
                &.{Symbol.from("A")},
            ),
        ),
    });

    defer state.deinit(allocator);

    var hash_map = State.HashMap(void).init(allocator);
    defer hash_map.deinit();
    try hash_map.put(state, {});
    try std.testing.expectEqual(true, hash_map.contains(state));
}
