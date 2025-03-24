# Bytecode

## Instructions
Opcode | Instruction | Description      | Example
------ | ----------- | -----------      | -------
`0x00` | `halt`       | Halt execution   | `halt`
`0x01` | `nop`        | No operation     | `nop`
`0x02` | `li`         | Load immediate   | `li r1, 0x1234`
`0x03` | `lw`         | Load word        | `lw r1, 0x1234`
`0x04` | `sw`         | Store word       | `sw r1, 0x1234`
`0x05` | `add`        | Add              | `add r1, r2, r3`
`0x06` | `sub`        | Subtract         | `sub r1, r2, r3`
`0x07` | `mul`        | Multiply         | `mul r1, r2, r3`
`0x08` | `div`        | Divide           | `div r1, r2, r3`
`0x09` | `jmp`        | Jump             | `jmp 0x1234`
`0x0a` | `beq`        | Equal            | `beq r1, r2, r3`
`0x0b` | `bne`        | Not equal        | `bne r1, r2, r3`
`0x0c` | `xor`        | Xor              | `xor r1, r2, r3`
`0x0d` | `and`        | And              | `and r1, r2, r3`
`0x0e` | `not`        | Not              | `not r1, r2`

## Bytecode Format

4-byte width:

```
Opcode    | Operand   | Operand   | Operand
0000 0000 | 0000 0000 | 0000 0000 | 0000 0000 
```