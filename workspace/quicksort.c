void swap(int *a, int *b) {
    int tmp;
    tmp = *a;
    *a = *b;
    *b = tmp;
}

int partition(int arr[], int low, int high) {
    int mid;
    int pivot;
    int i;
    int j;

    mid = low + (high - low) / 2;
    pivot = arr[mid];

    i = low - 1;
    j = high + 1;

    while (1) {
        do {
            i = i + 1;
        } while (arr[i] < pivot);

        do {
            j = j - 1;
        } while (arr[j] > pivot);

        if (i >= j) {
            return j;
        }

        swap(&arr[i], &arr[j]);
    }
}

void quicksort(int arr[], int low, int high) {
    int p;

    while (low < high) {
        p = partition(arr, low, high);

        if (p - low < high - p) {
            quicksort(arr, low, p);
            low = p + 1;
        } else {
            quicksort(arr, p + 1, high);
            high = p;
        }
    }
}

int main() {
    int arr[] = {45, 12, 89, 34, 70, 23, 56, 9};
    int n = 8;
    int k;

    printf("Usortert: ");
    for (k = 0; k < n; k++) {
        printf("%d ", arr[k]);
    }
    printf("\\n");

    quicksort(arr, 0, n - 1);

    printf("Sortert : ");
    for (k = 0; k < n; k++) {
        printf("%d ", arr[k]);
    }
    printf("\\n");

    return 0;
}
