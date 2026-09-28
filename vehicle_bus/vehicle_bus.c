/*
 * vehicle_bus — the car side of a taxi dashboard, as a program.
 *
 * Stands in for what a dashboard unit is actually wired to: a CAN bus carrying
 * the vehicle's own frames, a door switch, and a taximeter's start/stop line.
 * It really compiles and really runs; what it does not have is a car.
 *
 * Why this one is different from a request/response device
 * -------------------------------------------------------
 * A CAN bus is not a thing you ask. Frames arrive whether anyone wanted them or
 * not, at the rate the vehicle feels like sending them, and nobody replies to
 * them. So this program PUSHES lines:
 *
 *     {"frame":"speed","kph":42.7,"t":12.480}
 *     {"frame":"door","open":true,"t":13.010}
 *
 * and separately answers requests that carry an id, the way a dashboard's own
 * peripherals do:
 *
 *     {"id":4,"tool":"meter.state"}  ->  {"id":4,"ok":true,"result":{...}}
 *
 * Anything upstream has to cope with both on one wire. That is the shape of the
 * problem, and pretending otherwise would make the sample easier and useless.
 *
 * A trip is driven by a scripted profile so a run is reproducible: idle, then a
 * passenger boards, then a drive with a stop at a light, then arrival.
 *
 * Build: cc -O2 -o vehicle_bus vehicle_bus.c -lm
 */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <time.h>
#include <unistd.h>

#define LINE_MAX_LEN 2048
#define FRAME_INTERVAL_MS 100

/* A trip runs on the vehicle's clock, and that clock is deliberately fast here.
 * One wall-clock second is TIME_SCALE seconds of driving, so a run of the
 * sample covers a few kilometres instead of a few metres and the fare on screen
 * looks like a fare.
 *
 * Nothing downstream is told about this. The frames carry their own timestamps
 * and the meter integrates whatever intervals it is handed — which is exactly
 * the behaviour that has to be right on a real bus, where frames also arrive at
 * intervals nobody promised. Compressing time here is therefore not a trick
 * that hides a shortcut; it exercises the same code path harder. */
#define TIME_SCALE 30.0

/* `--scale N` overrides TIME_SCALE. A screen check runs the trip slower so every
 * phase can be photographed; the meter does not know, which is the point. */
static double g_scale = TIME_SCALE;

static double g_t0 = 0;
static int g_door_open = 0;
static int g_ignition = 1;

static double now_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

/* The scripted trip, in driving seconds (see TIME_SCALE).
 *
 *    0 -  45   stopped at the rank, no passenger
 *   45         door opens and closes: passenger boards
 *   45 - 120   driving, accelerating to about 52 km/h
 *  120 - 150   stopped at a light (this is what waiting-time billing is for)
 *  150 - 216   driving again
 *  216         arrival: speed to zero, door opens
 */
static double scripted_speed(double t) {
    if (t < 54.0) return 0.0;
    if (t < 120.0) {
        double x = (t - 54.0) / 66.0;
        return 52.0 * (1.0 - exp(-3.0 * x));
    }
    if (t < 150.0) return 0.0;             /* red light */
    if (t < 216.0) {
        double x = (t - 150.0) / 66.0;
        return 46.0 * (1.0 - exp(-3.0 * x));
    }
    return 0.0;                            /* arrived */
}

static int scripted_door(double t) {
    if (t >= 45.0 && t < 52.5) return 1;  /* boarding */
    if (t >= 225.0) return 1;             /* alighting */
    return 0;
}

static int json_str(const char *src, const char *key, char *out, size_t cap) {
    char pat[64];
    snprintf(pat, sizeof(pat), "\"%s\"", key);
    const char *p = strstr(src, pat);
    if (!p) return 0;
    p = strchr(p + strlen(pat), ':');
    if (!p) return 0;
    while (*p && *p != '"') p++;
    if (*p != '"') return 0;
    p++;
    size_t n = 0;
    while (*p && *p != '"' && n + 1 < cap) out[n++] = *p++;
    out[n] = '\0';
    return 1;
}

static int json_num(const char *src, const char *key, double *out) {
    char pat[64];
    snprintf(pat, sizeof(pat), "\"%s\"", key);
    const char *p = strstr(src, pat);
    if (!p) return 0;
    p = strchr(p + strlen(pat), ':');
    if (!p) return 0;
    p++;
    while (*p == ' ') p++;
    char *end = NULL;
    double v = strtod(p, &end);
    if (end == p) return 0;
    *out = v;
    return 1;
}

/* Read one request line if the host sent one, without blocking the frame loop.
 * A dashboard cannot stop watching the bus because someone asked it a question. */
static int poll_request(char *buf, size_t cap) {
    struct timespec zero = {0, 0};
    fd_set set;
    FD_ZERO(&set);
    FD_SET(0, &set);
    if (pselect(1, &set, NULL, NULL, &zero, NULL) <= 0) return 0;
    if (!fgets(buf, (int)cap, stdin)) return 0;
    return 1;
}

int main(int argc, char **argv) {
    for (int i = 1; i + 1 < argc; i++) {
        if (strcmp(argv[i], "--scale") == 0) g_scale = atof(argv[i + 1]);
    }
    setvbuf(stdout, NULL, _IOLBF, 0);
    g_t0 = now_seconds();

    char line[LINE_MAX_LEN];
    double last_emit = 0;

    for (;;) {
        double t = (now_seconds() - g_t0) * g_scale;

        /* --- unsolicited frames, at the bus's own rate --- */
        if (t - last_emit >= FRAME_INTERVAL_MS / 1000.0 * g_scale) {
            last_emit = t;
            double kph = scripted_speed(t);
            printf("{\"frame\":\"speed\",\"kph\":%.1f,\"t\":%.3f}\n", kph, t);

            int door = scripted_door(t);
            if (door != g_door_open) {
                g_door_open = door;
                printf("{\"frame\":\"door\",\"open\":%s,\"t\":%.3f}\n",
                       door ? "true" : "false", t);
            }
        }

        /* --- requests, answered the ordinary way --- */
        if (poll_request(line, sizeof(line))) {
            double id_d = 0;
            json_num(line, "id", &id_d);
            long rid = (long)id_d;
            char tool[64] = {0};
            if (!json_str(line, "tool", tool, sizeof(tool))) {
                printf("{\"id\":%ld,\"ok\":false,\"error\":\"missing tool\"}\n", rid);
            } else if (strcmp(tool, "vehicle.state") == 0) {
                printf("{\"id\":%ld,\"ok\":true,\"result\":{\"ignition\":%s,"
                       "\"doorOpen\":%s,\"kph\":%.1f,\"uptime\":%.3f}}\n",
                       rid, g_ignition ? "true" : "false",
                       g_door_open ? "true" : "false", scripted_speed(t), t);
            } else if (strcmp(tool, "terminal.authorize") == 0) {
                /* The fare terminal in the dashboard. Same shape as any other
                 * card device: ask, and hear a verdict. No card data leaves it. */
                double amount = 0;
                if (!json_num(line, "amount", &amount) || amount <= 0) {
                    printf("{\"id\":%ld,\"ok\":false,"
                           "\"error\":\"amount must be positive\"}\n", rid);
                } else {
                    struct timespec nap = {0, 90 * 1000000L};
                    nanosleep(&nap, NULL);
                    printf("{\"id\":%ld,\"ok\":true,\"result\":{\"approved\":true,"
                           "\"approvalCode\":\"T%ld\",\"last4\":\"7788\","
                           "\"amount\":%ld}}\n", rid, 8800 + rid, (long)amount);
                }
            } else {
                printf("{\"id\":%ld,\"ok\":false,\"error\":\"unknown tool\"}\n", rid);
            }
        }

        struct timespec nap = {0, 5 * 1000000L}; /* 5 ms */
        nanosleep(&nap, NULL);
    }
    return 0;
}
