extern int printf(char *fmt, ...);
extern void *malloc(int size);
extern void free(void *ptr);

struct Node {
    int val;
    struct Node *next;
};

int main() {
    struct Node *head = (struct Node *)malloc(sizeof(struct Node));
    struct Node *second = (struct Node *)malloc(sizeof(struct Node));
    struct Node *third = (struct Node *)malloc(sizeof(struct Node));

    head->val = 10;
    head->next = second;

    second->val = 20;
    second->next = third;

    third->val = 30;
    third->next = 0;

    printf("Linked List traversal:\n");
    struct Node *curr = head;
    while (curr) {
        printf("Node val: %d\n", curr->val);
        curr = curr->next;
    }

    free(third);
    free(second);
    free(head);
    printf("Linked list freed successfully!\n");
    return 0;
}
