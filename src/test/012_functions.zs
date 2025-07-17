fn fib(n) {
    if (fib < 2) {
        return n;
    }
    return fib(n - 1) + fib(n - 2);
}

fib(3) + 5;