const std = @import("std");

/// Iterate over a growing `ArrayList` of items.
/// Take care to only append items to the list during the walk.
///
/// Usage:
/// ```zig
/// const list = std.ArrayList(Item).init(allocator);
/// defer list.deinit();
/// var iter = WorkListIter(Item).from(&list);
/// while (iter.next()) |item| {
///     // ...
///     // Only append items to the list during the walk.
///     list.append(new_item);
/// }
/// ```
pub fn WorkListIter(comptime T: type) type {
    return struct {
        const Self = @This();
        list: *std.ArrayList(T),
        idx: usize = 0,

        pub inline fn from(list: *std.ArrayList(T)) Self {
            return Self{ .list = list };
        }

        /// Iterate over a growing list of items.
        ///
        /// Usage:
        /// ```zig
        /// const list = std.ArrayList(Item).init(allocator);
        /// defer list.deinit();
        /// var iter = WorkListIter(Item).from(&list);
        /// while (iter.next()) |item| {
        ///     // ...
        ///     // Only append items to the list during the walk.
        ///     list.append(new_item);
        /// }
        /// ```
        pub fn next(self: *Self) ?T {
            while (self.idx < self.list.items.len) {
                const item = self.list.items[self.idx];
                self.idx += 1;
                return item;
            }
            return null;
        }
    };
}
