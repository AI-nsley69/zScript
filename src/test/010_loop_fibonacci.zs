mut n = 10;
mut i = 0;

mut fibone = 1;
mut fibtwo = 0;

while (i != n) {
    i = i + 1;
    mut tmp = fibone;
    fibone = fibone + fibtwo;
    fibtwo = tmp;
}