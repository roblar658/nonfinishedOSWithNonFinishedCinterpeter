#include <stdio.h>

// Definerer differensialligningen: dy/dt = f(t, y)
// Eksempel: dy/dt = t + y
double f(double t, double y) {
    return t + y;
}

// Implementasjon av Eulers metode
void euler(double (*func)(double, double), double t0, double y0, double t_end, double h) {
    double t = t0;
    double y = y0;

    printf("%-10s %-15s\\n", "t", "y (tilnaermet)");
    printf("---------------------------\\n");
    printf("%-10.4f %-15.6f\\n", t, y);

    while (t < t_end) {
        // Juster siste steg dersom t + h overskrider t_end
        if (t + h > t_end) {
            h = t_end - t;
        }

        y = y + h * func(t, y);
        t = t + h;

        printf("%-10.4f %-15.6f\\n", t, y);
    }
}

int main(void) {
    double t0 = 0.0;     // Starttidspunkt
    double y0 = 1.0;     // Startverdi y(t0)
    double t_end = 2.0;  // Slutt-tidspunkt
    double h = 0.1;      // Steglengde (mindre verdi gir hoyere presisjon)

    euler(f, t0, y0, t_end, h);

    return 0;
}
