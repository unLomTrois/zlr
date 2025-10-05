/// The initial purpose of this struct is to model tables for LR Parsing Table, e.g.
///
/// State   | ACTION                     |
///         | id | +     | (  | )  |  $  |
/// 0       | s2 |       | s4 |    |     |
/// 1       |    |       |    |    | acc |
/// 2       | r4 | s5/r4 | r4 | r4 | r4  |
const std = @import("std");

/// Fixed size n x m table for runtime sizes
/// Supports nullable entries
///
/// Usage:
/// ```zig
/// const table = try nxmTable(usize).init(allocator, 2, 3, 1);
/// > [ [1, 1, 1],
///     [1, 1, 1] ]
///
/// const nullable_table = try nxmTable(?usize).init(allocator, 2, 2, null);
/// > [ [null, null],
///     [null, null] ]
/// ```
///
/// defaultValue can be null only if T is nullable
pub fn FixedTable(comptime T: type) type {
    return struct {
        const Self = @This();

        rows: usize,
        cols: usize,
        data: [][]T,

        pub fn init(allocator: std.mem.Allocator, rows: usize, cols: usize, comptime defaultValue: T) !Self {
            var table: [][]T = try allocator.alloc([]T, rows);
            for (0..rows) |i| {
                table[i] = try allocator.alloc(T, cols);
                for (0..cols) |j| {
                    table[i][j] = defaultValue;
                }
            }
            return Self{
                .rows = rows,
                .cols = cols,
                .data = table,
            };
        }

        pub fn initF(allocator: std.mem.Allocator, rows: usize, cols: usize, comptime defaultF: fn () error{OutOfMemory}!T) !Self {
            var table: [][]T = try allocator.alloc([]T, rows);
            for (0..rows) |i| {
                table[i] = try allocator.alloc(T, cols);
                for (0..cols) |j| {
                    table[i][j] = try defaultF();
                }
            }
            return Self{
                .rows = rows,
                .cols = cols,
                .data = table,
            };
        }

        pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
            for (self.data) |row| {
                allocator.free(row);
            }
            allocator.free(self.data);
        }
    };
}

test "2d slice of usize" {
    const allocator = std.testing.allocator;
    const table = try FixedTable(usize).init(allocator, 2, 3, 0);
    defer table.deinit(allocator);
    try std.testing.expect(table.data[0][0] == 0);
    try std.testing.expect(table.rows == 2);
    try std.testing.expect(table.cols == 3);
}

test "2d slice of bool" {
    const allocator = std.testing.allocator;
    const table = try FixedTable(bool).init(allocator, 2, 2, true);
    defer table.deinit(allocator);
    try std.testing.expect(table.data[0][0] == true);
}

test "nullable table" {
    const allocator = std.testing.allocator;
    const table = try FixedTable(?usize).init(allocator, 2, 2, null);
    defer table.deinit(allocator);
    try std.testing.expect(table.data[0][0] == null);
}

test "nullable union table" {
    const tagged = union(enum) {
        ok: u8,
        err: void,
    };

    const allocator = std.testing.allocator;
    var table = try FixedTable(?tagged).init(allocator, 2, 2, null);
    defer table.deinit(allocator);

    table.data[0][0] = .{ .ok = 42 };
    table.data[1][1] = .{ .err = {} };
    try std.testing.expect(table.data[0][0] != null);
    try std.testing.expect(table.data[0][0].?.ok == 42);

    try std.testing.expect(table.data[0][1] == null);

    try std.testing.expect(table.data[1][1] != null);
    try std.testing.expect(table.data[1][1].?.err == {});
}

test "table with slice cells" {
    // Consider a table with
    const allocator = std.testing.allocator;
    const table = try FixedTable([]usize).init(allocator, 2, 2, undefined);
    defer table.deinit(allocator);
    try std.testing.expect(table.cols == 2);
}

test "initF" {
    const allocator = std.testing.allocator;
    const table = try FixedTable(usize).initF(allocator, 2, 2, struct {
        pub fn init() !usize {
            return 0;
        }
    }.init);
    defer table.deinit(allocator);
}

test "initF slice cells" {
    const allocator = std.testing.allocator;
    const table = try FixedTable([]usize).initF(allocator, 2, 2, struct {
        pub fn init() ![]usize {
            var cell = try allocator.alloc(usize, 2);
            cell[0] = 0;
            cell[1] = 1;
            return cell;
        }
    }.init);
    defer table.deinit(allocator);
    defer for (table.data) |row| {
        for (row) |cell| {
            allocator.free(cell);
        }
    };
}
