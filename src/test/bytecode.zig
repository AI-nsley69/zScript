const std = @import("std");
const Vm = @import("../vm.zig");

const OpCodes = Vm.OpCodes;

pub fn fib(assembler: *Vm.Assembler, n: u8) !void {
    // Setup
    try assembler.createSingleRegImm(.LOAD_IMMEDIATE, 0x01, 0x0000); // a
    try assembler.createSingleRegImm(.LOAD_IMMEDIATE, 0x02, 0x0001); // b
    try assembler.createSingleRegImm(.LOAD_IMMEDIATE, 0x03, 0x0000); // tmp value
    try assembler.createSingleRegImm(.LOAD_IMMEDIATE, 0x04, 0x0000); // Accumulator
    try assembler.createSingleRegImm(.LOAD_IMMEDIATE, 0x06, @as(u16, n)); // n -> number in sequence - 1
    try assembler.createSingleRegImm(.LOAD_IMMEDIATE, 0x07, 0x0014); // Jump address
    // Loop
    try assembler.createRaw(.ADD, 0x03, 0x01, 0x02); // 0x001c
    try assembler.createSingleRegImm(.ADD_IMMEDIATE, 0x04, 0x0001); // Increment accumulator
    try assembler.createDoubleReg(.MOV, 0x02, 0x01); // Copy a to b
    try assembler.createDoubleReg(.MOV, 0x01, 0x03); // Copy tmp to a
    try assembler.createRaw(.BRANCH_IF_NOT_EQUAL, 0x07, 0x04, 0x06); // Branch if value not equal
    // Halt program
    try assembler.createNoArg(.RET); // Halt execution
}
