#include <stdio.h>

double beregn_kvadratrot(double n) {
    if (n <= 0.0) return 0.0;
    double x = n;
    for (int i = 0; i < 10; i++) {
        x = 0.5 * (x + n / x);
    }
    return x;
}

int main(void) {
    long lops_sum = 0;
    printf("+-----+------------+------------+---------------+------------+\n");
    printf("| %-3s | %-10s | %-10s | %-13s | %-10s |\n", "n", "Kvadrat", "Kubikk", "Kvadratrot", "Sum (1..n)");
    printf("+-----+------------+------------+---------------+------------+\n");

    for (int n = 1; n <= 10; n++) {
        long kvadrat = (long)n * n;
        long kubikk = (long)n * n * n;
        double rot = beregn_kvadratrot((double)n);
        lops_sum += n;
        printf("| %-3d | %-10ld | %-10ld | %-13.6f | %-10ld |\n", n, kvadrat, kubikk, rot, lops_sum);
    }
    printf("+-----+------------+------------+---------------+------------+\n");
    return 0;
}
