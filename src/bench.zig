const std = @import("std");

const sac = @import("./internals/public.zig");
const Context = sac.Context;
const Node = sac.Node;

fn parseRawSource(raw: []const u8, allocator: std.mem.Allocator) !Node {
    var tokenizer = sac.Tokenizer.init();
    defer tokenizer.deinit(allocator);
    try tokenizer.tokenize(allocator, raw);

    var ntokparsed: usize = 0;
    const node = try sac.parse(tokenizer.tokens.items, 0, &ntokparsed, allocator);
    return node;
}

fn benchParseEval(writer: anytype, name: []const u8, src: []const u8, iterations: usize) !void {
    var timer = try std.time.Timer.start();
    var i: usize = 0;
    const alloc = std.heap.page_allocator;
    while (i < iterations) : (i += 1) {
        var node = try parseRawSource(src, alloc);
        defer node.deinit(alloc);
        var ctx = try Context.init(alloc);
        defer ctx.deinit(alloc);
        if (sac.eval(&ctx, alloc, node)) |*result| {
            result.deinit(alloc);
        } else |_| {}
    }
    const ns = timer.read();
    const ns_per = @divTrunc(ns, iterations);
    const ms_int: u64 = @intCast(ns_per / 1_000_000);
    const ms_frac3_val: u64 = @intCast((ns_per % 1_000_000) / 1_000);
    var frac_buf: [3]u8 = undefined;
    frac_buf[0] = '0' + @as(u8, @intCast((ms_frac3_val / 100) % 10));
    frac_buf[1] = '0' + @as(u8, @intCast((ms_frac3_val / 10) % 10));
    frac_buf[2] = '0' + @as(u8, @intCast(ms_frac3_val % 10));
    try writer.print("{s}: {d} iters, {d} ns/op ({d}.{s} ms/op)\n", .{ name, iterations, ns_per, ms_int, frac_buf });
    try writer.flush();
}

fn benchEvalOnly(writer: anytype, name: []const u8, src: []const u8, iterations: usize, parse_alloc: std.mem.Allocator) !void {
    var node = try parseRawSource(src, parse_alloc);
    defer node.deinit(parse_alloc);
    var timer = try std.time.Timer.start();
    var i: usize = 0;
    const alloc = std.heap.page_allocator;
    var ctx = try Context.init(alloc);
    defer ctx.deinit(alloc);
    while (i < iterations) : (i += 1) {
        if (sac.eval(&ctx, alloc, node)) |*result| {
            result.deinit(alloc);
        } else |_| {}
    }
    const ns = timer.read();
    const ns_per = @divTrunc(ns, iterations);
    const ms_int: u64 = @intCast(ns_per / 1_000_000);
    const ms_frac3_val: u64 = @intCast((ns_per % 1_000_000) / 1_000);
    var frac_buf: [3]u8 = undefined;
    frac_buf[0] = '0' + @as(u8, @intCast((ms_frac3_val / 100) % 10));
    frac_buf[1] = '0' + @as(u8, @intCast((ms_frac3_val / 10) % 10));
    frac_buf[2] = '0' + @as(u8, @intCast(ms_frac3_val % 10));
    try writer.print("{s}: {d} iters, {d} ns/op ({d}.{s} ms/op)\n", .{ name, iterations, ns_per, ms_int, frac_buf });
    try writer.flush();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    // Micro programs
    const src_arith = "(sum 1 2 3 4 5 6 7 8 9 10)";

    var list_buf = std.ArrayList(u8).empty;
    defer list_buf.deinit(allocator);
    try list_buf.appendSlice(allocator, "(list");
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const frag = try std.fmt.allocPrint(allocator, " {d}", .{i});
        defer allocator.free(frag);
        try list_buf.appendSlice(allocator, frag);
    }
    try list_buf.appendSlice(allocator, ")");
    const src_list_100 = list_buf.items;

    const src_lambda_comp =
        "(set inc (lambda (x) (sum x 1)))" ++
        "(set double (lambda (x) (mult 2 x)))" ++
        "(set inc_then_double (lambda (x) (double (inc x))))" ++
        "(inc_then_double 123)";

    const src_tco_fact =
        "(defun fact (n acc) (if (eq n 0) acc (fact (sub n 1) (mult acc n))))" ++
        "(fact 10 1)";

    // Example files (embedded)
    const ex_lambdas = @embedFile("./examples/lambdas-tests.sac");
    const ex_lists = @embedFile("./examples/lists-tests.sac");

    const it_small: usize = 20_000;
    const it_medium: usize = 2_000;
    const it_file: usize = 50;

    try stdout.print("Sacrilege benchmarks (ns/op)\n", .{});
    try stdout.flush();

    // Parse+Eval
    try benchParseEval(stdout, "parse+eval arith", src_arith, it_medium);
    try benchParseEval(stdout, "parse+eval list100", src_list_100, it_small / 5);
    try benchParseEval(stdout, "parse+eval lambda-comp", src_lambda_comp, it_medium);
    try benchParseEval(stdout, "parse+eval tco-fact", src_tco_fact, it_medium);

    // Eval only (parse once)
    try benchEvalOnly(stdout, "eval-only arith", src_arith, it_small, allocator);
    try benchEvalOnly(stdout, "eval-only list100", src_list_100, it_small, allocator);
    try benchEvalOnly(stdout, "eval-only lambda-comp", src_lambda_comp, it_small, allocator);
    try benchEvalOnly(stdout, "eval-only tco-fact", src_tco_fact, it_small, allocator);

    // Embedded example files
    try benchParseEval(stdout, "parse+eval file lambdas-tests.sac", ex_lambdas, it_file);
    try benchParseEval(stdout, "parse+eval file lists-tests.sac", ex_lists, it_file);
    try benchEvalOnly(stdout, "eval-only file lambdas-tests.sac", ex_lambdas, it_file, allocator);
    try benchEvalOnly(stdout, "eval-only file lists-tests.sac", ex_lists, it_file, allocator);
}
