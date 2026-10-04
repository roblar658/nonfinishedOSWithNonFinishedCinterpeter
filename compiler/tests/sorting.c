extern int printf(char *fmt, ...);

int main() {
    int arr[8];
    arr[0] = 64; arr[1] = 34; arr[2] = 25; arr[3] = 12;
    arr[4] = 22; arr[5] = 11; arr[6] = 90; arr[7] = 42;
    int n = 8;
    int i;
    int j;
    int temp;

    printf("Original array:\n");
    for (i = 0; i < n; i = i + 1) {
        printf("%d ", arr[i]);
    }
    printf("\n");

    for (i = 0; i < n - 1; i = i + 1) {
        for (j = 0; j < n - i - 1; j = j + 1) {
            if (arr[j] > arr[j + 1]) {
                temp = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = temp;
            }
        }
    }

    printf("Sorted array:\n");
    for (i = 0; i < n; i = i + 1) {
        printf("%d ", arr[i]);
    }
    printf("\n");
    return 0;
}
