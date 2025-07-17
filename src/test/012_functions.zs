fn fib(n) {
    if (n < 2) {
        return n;
    }
    mut res = fib(n - 1) + fib(n - 2);
    return res;
}

fib(5);