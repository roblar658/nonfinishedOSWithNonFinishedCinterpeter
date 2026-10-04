extern int printf(char *fmt, ...);

int fact(int n) {
    if (n <= 1) return 1;
    return n * fact(n - 1);
}

int main() {
    int i;
    printf("Factorial table in CustomC-OS:\n");
    for (i = 1; i <= 8; i = i + 1) {
        printf("  %d! = %d\n", i, fact(i));
    }
    return 0;
}
