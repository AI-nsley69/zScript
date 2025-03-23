const std = @import("std");
const interpreter = @import("interpreter.zig");
const bytecode = @import("bytecode.zig");

fn fmtInstruction(allocator: *std.mem.Allocator, input: *[]const u8, pointer: u32) []const u8 {
    return std.fmt.allocPrint(allocator.*, "[{x:0>6}] {s}", .{ pointer, input.* }) catch "Unable to format instruction.";
}

fn tripleRegInstruction(alloc: *std.mem.Allocator, name: *[]const u8, operands: *[]const u8, pointer: u32) []const u8 {
    var str: []const u8 = std.fmt.allocPrint(alloc.*, "{s} r{d} r{d} r{d}", .{ name, operands.*[0], operands.*[1], operands.*[2] }) catch return "Unable to format instruction.";
    return fmtInstruction(alloc, &str, pointer);
}

fn doubleRegInstruction(alloc: *std.mem.Allocator, name: *[]const u8, operands: *[]const u8, pointer: u32) []const u8 {
    var str: []const u8 = std.fmt.allocPrint(alloc.*, "{s} r{d} r{d}", .{ name, operands.*[0], operands.*[1] }) catch return "Unable to format instruction.";
    return fmtInstruction(alloc, &str, pointer);
}

fn singleRegInstruction(alloc: *std.mem.Allocator, name: *[]const u8, operands: *[]const u8, pointer: u32) []const u8 {
    var str: []const u8 = std.fmt.allocPrint(alloc.*, "{s} r{d}", .{ name, operands.*[0] }) catch return "Unable to format instruction.";
    return fmtInstruction(alloc, &str, pointer);
}

pub fn dissambleInstruction(alloc: *std.mem.Allocator, instruction: *[]const u8, pointer: u32) []const u8 {
    const opcode: bytecode.OpCodes = @enumFromInt(instruction.*[0]);
    var operands: []const u8 = &[_]u8{ instruction.*[1], instruction.*[2], instruction.*[3] };
    return switch (opcode) {
        .HALT => {
            var str: []const u8 = "halt";
            return fmtInstruction(alloc, &str, pointer);
        },
        .NOP => {
            var str: []const u8 = "nop";
            return fmtInstruction(alloc, &str, pointer);
        },
        .LOAD_IMMEDIATE => {
            const imm: u16 = @as(u16, operands[1]) << 8 | operands[2];
            var str: []const u8 = std.fmt.allocPrint(alloc.*, "li r{d} #{x:0>4}", .{ operands[0], imm }) catch return "Unable to format instruction.";
            return fmtInstruction(alloc, &str, pointer);
        },
        .LOAD_WORD => {
            var str: []const u8 = "lw";
            return doubleRegInstruction(alloc, &str, &operands, pointer);
        },
        .STORE_WORD => {
            var str: []const u8 = "sw";
            return doubleRegInstruction(alloc, &str, &operands, pointer);
        },
        .ADD => {
            var str: []const u8 = "add";
            return tripleRegInstruction(alloc, &str, &operands, pointer);
        },
        .SUBTRACT => {
            var str: []const u8 = "sub";
            return tripleRegInstruction(alloc, &str, &operands, pointer);
        },
        .MULTIPLY => {
            var str: []const u8 = "mul";
            return tripleRegInstruction(alloc, &str, &operands, pointer);
        },
        .DIVIDE => {
            var str: []const u8 = "div";
            return tripleRegInstruction(alloc, &str, &operands, pointer);
        },
        .JUMP => {
            var str: []const u8 = "jmp";
            return singleRegInstruction(alloc, &str, &operands, pointer);
        },
        .BRANCH_IF_EQUAL => {
            var str: []const u8 = "beq";
            return tripleRegInstruction(alloc, &str, &operands, pointer);
        },
        .BRANCH_IF_NOT_EQUAL => {
            var str: []const u8 = "bne";
            return tripleRegInstruction(alloc, &str, &operands, pointer);
        },
        .XOR => {
            var str: []const u8 = "xor";
            return tripleRegInstruction(alloc, &str, &operands, pointer);
        },
        .AND => {
            var str: []const u8 = "and";
            return tripleRegInstruction(alloc, &str, &operands, pointer);
        },
        .OR => {
            var str: []const u8 = "or";
            return tripleRegInstruction(alloc, &str, &operands, pointer);
        },
        // else => {
        //     var str: []const u8 = std.fmt.allocPrint(alloc.*, "{any} {x:0>2} {x:0>2} {x:0>2}", .{ opcode, instruction.*[1], instruction.*[2], instruction.*[3] }) catch return "Unable to format instruction.";
        //     return fmtInstruction(alloc, &str, pointer);
        // },
    };
}
