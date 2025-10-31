const std = @import("std");

const sac = @import("./public.zig");
const Token = sac.Token;

pub const NodeType = enum {
    atom,
    sexpr,

    pub fn getTypeString(self: NodeType) []const u8 {
        switch (self) {
            .atom => return "atom",
            .sexpr => return "expression",
        }
        unreachable;
    }
};

pub const Node = union(NodeType) {
    const Self = @This();

    atom: Token,
    sexpr: std.ArrayList(Self),

    pub fn deinit(self: Self) void {
        switch (self) {
            NodeType.atom => |atm| {
                atm.deinit();
            },
            NodeType.sexpr => |xpr| {
                for (xpr.items) |item| {
                    item.deinit();
                }
                xpr.deinit();
            },
        }
    }

    pub fn copy(self: Self) !Self {
        switch (self) {
            NodeType.atom => {
                return Node{
                    .atom = try self.atom.copy(),
                };
            },
            NodeType.sexpr => {
                var arr = std.ArrayList(Self).init(self.sexpr.allocator);
                for (self.sexpr.items) |child| {
                    try arr.append(try child.copy());
                }
                return Node{
                    .sexpr = arr,
                };
            },
        }
        unreachable;
    }

    pub fn new_sexpr() Node {
        return Node{ .sexpr = std.ArrayList(Node).empty };
    }

    pub fn equal(self: Self, other: Self) bool {
        switch (self) {
            NodeType.atom => {
                if (other != NodeType.atom) {
                    return false;
                }
                if (self.atom.id != other.atom.id) {
                    return false;
                }
                return std.mem.eql(u8, self.atom.raw.items, other.atom.raw.items);
            },
            NodeType.sexpr => {
                if (self.sexpr.items.len != other.sexpr.items.len) {
                    return false;
                }
                for (self.sexpr.items[0..], other.sexpr.items[0..]) |si, oi| {
                    if (!si.equal(oi)) {
                        return false;
                    }
                }
                return true;
            },
        }
    }

    pub fn findFirstToken(self: Self) Token {
        switch (self) {
            NodeType.atom => {
                return self.atom;
            },
            NodeType.sexpr => {
                for (self.sexpr.items) |child| {
                    return child.findFirstToken();
                }
            },
        }
        unreachable;
    }

    pub fn print(self: Self) !void {
        const stdout = std.io.getStdOut().writer();
        switch (self) {
            NodeType.atom => |val| {
                try stdout.print("{s} ", .{val.raw.items});
            },
            NodeType.sexpr => |nodes| {
                try stdout.print("(", .{});
                for (nodes.items) |node| {
                    try node.print();
                    try stdout.print(" ", .{});
                }
                try stdout.print(")", .{});
            },
        }
    }
};
