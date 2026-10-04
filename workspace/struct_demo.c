extern int printf(char *fmt, ...);

struct Vector {
    int x;
    int y;
    int z;
};

int dot_product(struct Vector *a, struct Vector *b) {
    return (a->x * b->x) + (a->y * b->y) + (a->z * b->z);
}

int main() {
    struct Vector v1;
    struct Vector v2;
    v1.x = 2; v1.y = 3; v1.z = 4;
    v2.x = 5; v2.y = 6; v2.z = 7;
    int dot = dot_product(&v1, &v2);
    printf("Vector 1: (%d, %d, %d)\n", v1.x, v1.y, v1.z);
    printf("Vector 2: (%d, %d, %d)\n", v2.x, v2.y, v2.z);
    printf("Dot product: %d\n", dot);
    return 0;
}
