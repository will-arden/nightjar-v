# x1 = loop counter (start at 5)
addi x1, x0, 5

# x2 = accumulator (start at 0)
addi x2, x0, 0

loop:
    addi x2, x2, 1     # accumulator++
    addi x1, x1, -1    # counter--

    bne  x1, x0, loop  # loop while x1 != 0

halt:
    jal  x0, halt      # infinite loop (halt)
