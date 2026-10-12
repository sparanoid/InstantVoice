// Shifts the wall clock of a screenshot run so it reads SCREENSHOT_EPOCH (Unix seconds) at launch.
// scripts/screenshots.sh loads it with DYLD_INSERT_LIBRARIES. Time keeps running from that moment, so timers and
// animations behave normally, while dates, greetings, and "minutes ago" labels come out the same on every run.

#include <stdint.h>
#include <stdlib.h>
#include <sys/time.h>
#include <time.h>

#define INTERPOSE(replacement, replacee) \
    __attribute__((used)) static struct { const void *replacement_; const void *replacee_; } interpose_##replacee \
    __attribute__((section("__DATA,__interpose"))) = { (const void *)&replacement, (const void *)&replacee }

static int64_t offsetNanoseconds;

__attribute__((constructor)) static void setUpFixedClock(void) {
    const char *epoch = getenv("SCREENSHOT_EPOCH");
    if (epoch == NULL) return;

    // Calls from this library reach the real functions, so this reads the actual time.
    struct timespec now;
    clock_gettime(CLOCK_REALTIME, &now);
    offsetNanoseconds = (int64_t)(strtod(epoch, NULL) * 1e9) - ((int64_t)now.tv_sec * 1000000000LL + now.tv_nsec);
}

static void shift(struct timespec *time) {
    int64_t nanoseconds = (int64_t)time->tv_sec * 1000000000LL + time->tv_nsec + offsetNanoseconds;
    time->tv_sec = nanoseconds / 1000000000LL;
    time->tv_nsec = nanoseconds % 1000000000LL;
}

static int fixed_clock_gettime(clockid_t clock, struct timespec *time) {
    int result = clock_gettime(clock, time);
    if (result == 0 && clock == CLOCK_REALTIME) shift(time);
    return result;
}
INTERPOSE(fixed_clock_gettime, clock_gettime);

static uint64_t fixed_clock_gettime_nsec_np(clockid_t clock) {
    uint64_t nanoseconds = clock_gettime_nsec_np(clock);
    return clock == CLOCK_REALTIME ? (uint64_t)((int64_t)nanoseconds + offsetNanoseconds) : nanoseconds;
}
INTERPOSE(fixed_clock_gettime_nsec_np, clock_gettime_nsec_np);

static int fixed_gettimeofday(struct timeval *time, void *zone) {
    int result = gettimeofday(time, zone);
    if (result == 0 && time != NULL) {
        int64_t microseconds = (int64_t)time->tv_sec * 1000000LL + time->tv_usec + offsetNanoseconds / 1000;
        time->tv_sec = microseconds / 1000000LL;
        time->tv_usec = (suseconds_t)(microseconds % 1000000LL);
    }
    return result;
}
INTERPOSE(fixed_gettimeofday, gettimeofday);

static time_t fixed_time(time_t *output) {
    struct timespec now;
    fixed_clock_gettime(CLOCK_REALTIME, &now);
    if (output != NULL) *output = now.tv_sec;
    return now.tv_sec;
}
INTERPOSE(fixed_time, time);
