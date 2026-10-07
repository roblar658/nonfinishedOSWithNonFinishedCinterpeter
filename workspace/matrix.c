extern int printf(char *fmt, ...);

int main() {
    int m[3][3];
    int i;
    int j;
    int count = 1;

    for (i = 0; i < 3; i++) {
        for (j = 0; j < 3; j++) {
            m[i][j] = count;
            count++;
        }
    }

    printf("3x3 Matrix:\n");
    for (i = 0; i < 3; i++) {
        printf("[%d, %d, %d]\n", m[i][0], m[i][1], m[i][2]);
    }

    int diag_sum = 0;
    for (i = 0; i < 3; i++) {
        diag_sum += m[i][i];
    }
    printf("Trace: %d\n", diag_sum);

    return 0;
}
