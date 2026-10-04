extern int printf(char *fmt, ...);

int fib(int n) {
    if (n <= 0) return 0;
    if (n == 1) return 1;
    return fib(n - 1) + fib(n - 2);
}

int main() {
    int i;
    printf("Fibonacci sequence (first 10 numbers):\n");
    for (i = 0; i < 10; i = i + 1) {
        printf("fib(%d) = %d\n", i, fib(i));
    }
    return 0;
}
