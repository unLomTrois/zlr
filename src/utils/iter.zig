const std = @import("std");

/// Generic iterator over a slice of items.
///
/// Usage:
/// ```zig
/// const items = [_]YourType{ item1, item2, item3 };
/// var iter = Iter(YourType).from(&items);
/// while (iter.next()) |item| {
///     // ...
/// }
/// ```
pub fn Iter(comptime T: type) type {
    return struct {
        const Self = @This();
        items: []const T,
        idx: usize = 0,

        pub inline fn from(items: []const T) Self {
            return Self{ .items = items };
        }

        /// Iterate over the items.
        ///
        /// Usage:
        /// ```zig
        /// var iter = Iter(i32).from(&numbers);
        /// while (iter.next()) |item| {
        ///     // ...
        /// }
        /// ```
        pub fn next(self: *Self) ?T {
            while (self.idx < self.items.len) {
                const item = self.items[self.idx];
                self.idx += 1;
                return item;
            }
            return null;
        }

        /// Iterate over the items which satisfy the predicate.
        ///
        /// Usage:
        /// ```zig
        /// var iter = Iter(i32).from(&numbers);
        /// while (iter.next_if(is_even)) |item| {
        ///     // ...
        /// }
        /// ```
        pub fn next_if(self: *Self, predicate: fn (T) bool) ?T {
            while (self.next()) |item| {
                if (predicate(item)) return item;
            }
            return null;
        }
    };
}

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

        /// Iterate over the items which satisfy the predicate.
        ///
        /// Usage:
        /// ```zig
        /// const list = std.ArrayList(i32).init(allocator);
        /// defer list.deinit();
        /// var iter = WorkListIter(i32).from(&list);
        /// while (iter.next_if(is_even)) |item| {
        ///     // ...
        /// }
        /// ```
        pub fn next_if(self: *Self, predicate: fn (T) bool) ?T {
            while (self.next()) |item| {
                if (predicate(item)) return item;
            }
            return null;
        }
    };
}
