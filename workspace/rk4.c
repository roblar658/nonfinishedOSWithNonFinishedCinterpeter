#include <stdio.h>

// Definerer differensialligningen: dy/dt = f(t, y)
// Eksempel: dy/dt = t + y
double f(double t, double y) {
    return t + y;
}

// 4. ordens Runge-Kutta (RK4)
void rk4(double (*func)(double, double), double t0, double y0, double t_end, double h) {
    double t = t0;
    double y = y0;

    printf("%-10s %-18s\n", "t", "y (RK4 tilnaermet)");
    printf("-------------------------------\n");
    printf("%-10.4f %-18.8f\n", t, y);

    while (t < t_end) {
        // Juster steglengden for siste iterasjon ved behov
        if (t + h > t_end) {
            h = t_end - t;
        }

        double k1 = func(t, y);
        double k2 = func(t + 0.5 * h, y + 0.5 * h * k1);
        double k3 = func(t + 0.5 * h, y + 0.5 * h * k2);
        double k4 = func(t + h, y + h * k3);

        y += (h / 6.0) * (k1 + 2.0 * k2 + 2.0 * k3 + k4);
        t += h;

        printf("%-10.4f %-18.8f\n", t, y);
    }
}

int main(void) {
    double t0 = 0.0;     // Starttid
    double y0 = 1.0;     // Startverdi y(t0)
    double t_end = 2.0;  // Slutt-tid
    double h = 0.1;      // Steglengde

    rk4(f, t0, y0, t_end, h);

    return 0;
}
