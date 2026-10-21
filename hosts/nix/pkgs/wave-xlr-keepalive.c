/*
 * Single-device Wave XLR MK1 capture keepalive. No hardware/profile changes.
 * Watchdog policy adapted from OpenWave 1.2.0 audio.rs (MIT).
 * Copyright (c) 2025 rikkichy
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
#define _POSIX_C_SOURCE 200809L
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <json-c/json.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define PREFIX "alsa_input.usb-Elgato_Systems_Elgato_Wave_XLR_"
#define CORE "PipeWire:Interface:Core"
#define NODE "PipeWire:Interface:Node"
#define DEVICE "PipeWire:Interface:Device"
#define DUMP_LIMIT (16U * 1024U * 1024U)

enum graph_state { UNKNOWN = -1, ABSENT = 0, FOUND = 1 };
struct node { char name[512]; uint64_t cookie, serial; int muted; };
struct watch { double started, last_data, silence_since; bool received, silence_spent; };
struct child {
    pid_t pid;
    int fd, status;
    double started, stopping;
    bool active;
};
static volatile sig_atomic_t stopping;

static double monotonic(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) < 0) abort();
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1000000000.0;
}

static void interrupted(int signum) { (void)signum; stopping = 1; }

static struct json_object *field(struct json_object *object, const char *key)
{
    struct json_object *value = NULL;
    if (json_object_is_type(object, json_type_object))
        json_object_object_get_ex(object, key, &value);
    return value;
}

static const char *text(struct json_object *value)
{
    if (!json_object_is_type(value, json_type_string)) return NULL;
    const char *s = json_object_get_string(value);
    return strlen(s) == (size_t)json_object_get_string_len(value) ? s : NULL;
}

static bool equals(struct json_object *value, const char *expected)
{
    const char *s = text(value);
    return s && strcmp(s, expected) == 0;
}

static bool number(struct json_object *value, uint64_t maximum, uint64_t *out)
{
    if (!json_object_is_type(value, json_type_int) && !text(value)) return false;
    const char *s = json_object_get_string(value);
    if (!s || !*s) return false;
    uint64_t result = 0;
    for (; *s; ++s) {
        if (*s < '0' || *s > '9') return false;
        unsigned digit = (unsigned)(*s - '0');
        if (digit > maximum || result > (maximum - digit) / 10) return false;
        result = result * 10 + digit;
    }
    *out = result;
    return true;
}

/* -1 is malformed metadata, distinct from a known non-MK1 device. */
static int usb_matches(struct json_object *props, const char *key, uint64_t expected)
{
    struct json_object *value;
    if (!json_object_object_get_ex(props, key, &value)) return true;
    uint64_t id;
    if (json_object_is_type(value, json_type_int))
        return number(value, UINT16_MAX, &id) ? (id == expected) : -1;
    const char *s = text(value);
    if (!s || !*s) return -1;
    int base = (s[0] == '0' || strpbrk(s, "abcdefABCDEF")) ? 16 : 10;
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) s += 2;
    if (!*s) return -1;
    for (const char *p = s; *p; ++p)
        if (!(base == 16 ? isxdigit((unsigned char)*p) : isdigit((unsigned char)*p)))
            return -1;
    char *end;
    errno = 0;
    unsigned long long parsed = strtoull(s, &end, base);
    return !errno && !*end && parsed <= UINT16_MAX ? (parsed == expected) : -1;
}

static int input_mute(struct json_object *props, struct json_object *device_info)
{
    struct json_object *routes = field(field(device_info, "params"), "Route");
    if (!json_object_is_type(routes, json_type_array)) return -1;
    struct json_object *profile_value;
    bool exact = json_object_object_get_ex(props, "device.profile.device", &profile_value);
    uint64_t profile = 0;
    if (exact && !number(profile_value, UINT32_MAX, &profile)) return -1;
    int result = -1;
    size_t count = json_object_array_length(routes);
    for (size_t i = 0; i < count; ++i) {
        struct json_object *route = json_object_array_get_idx(routes, i);
        struct json_object *direction = field(route, "direction");
        if (equals(direction, "Output")) continue;
        if (!equals(direction, "Input")) return -1;
        uint64_t device;
        if (exact) {
            if (!number(field(route, "device"), UINT32_MAX, &device)) return -1;
            if (device != profile) continue;
        }
        struct json_object *mute = field(field(route, "props"), "mute");
        if (!json_object_is_type(mute, json_type_boolean)) return -1;
        int current = json_object_get_boolean(mute) ? 1 : 0;
        if (result != -1 && result != current) return -1;
        result = current;
    }
    return result;
}

static enum graph_state parse_graph(struct json_object *objects, struct node *out)
{
    if (!json_object_is_type(objects, json_type_array)) return UNKNOWN;
    size_t count = json_object_array_length(objects);
    unsigned cores = 0, candidates = 0;
    uint64_t cookie = 0;
    struct json_object *chosen = NULL, *chosen_device = NULL;
    for (size_t i = 0; i < count; ++i) {
        struct json_object *object = json_object_array_get_idx(objects, i);
        struct json_object *kind = field(object, "type");
        uint64_t id;
        if (!text(kind) || !number(field(object, "id"), UINT32_MAX, &id)) return UNKNOWN;
        struct json_object *info = field(object, "info");
        if (equals(kind, CORE)) {
            if (!number(field(info, "cookie"), UINT32_MAX, &cookie)) return UNKNOWN;
            ++cores;
        }
        if (!equals(kind, NODE) && !equals(kind, DEVICE)) continue;
        struct json_object *props = field(info, "props");
        if (!json_object_is_type(props, json_type_object)) return UNKNOWN;
        if (!equals(kind, NODE)) continue;
        const char *name = text(field(props, "node.name"));
        if (!name || !*name) return UNKNOWN;
        struct json_object *serial;
        if (json_object_object_get_ex(props, "object.serial", &serial) &&
            !number(serial, UINT64_MAX, &id)) return UNKNOWN;
        if (strncmp(name, PREFIX, sizeof(PREFIX) - 1) != 0) continue;
        struct json_object *media_class = field(props, "media.class");
        if (!text(media_class)) return UNKNOWN;
        if (!equals(media_class, "Audio/Source")) continue;

        struct json_object *device_info = NULL, *device_value;
        if (json_object_object_get_ex(props, "device.id", &device_value)) {
            uint64_t device_id;
            if (!number(device_value, UINT32_MAX, &device_id)) return UNKNOWN;
            unsigned matches = 0;
            for (size_t j = 0; j < count; ++j) {
                struct json_object *device = json_object_array_get_idx(objects, j);
                if (number(field(device, "id"), UINT32_MAX, &id) && id == device_id) {
                    if (!equals(field(device, "type"), DEVICE)) return UNKNOWN;
                    device_info = field(device, "info");
                    ++matches;
                }
            }
            if (matches != 1) return UNKNOWN;
        }
        struct json_object *device_props = field(device_info, "props");
        if (device_info && !json_object_is_type(device_props, json_type_object)) return UNKNOWN;
        int vendor = usb_matches(props, "device.vendor.id", 0x0fd9);
        int product = usb_matches(props, "device.product.id", 0x007d);
        int device_vendor = device_props ? usb_matches(device_props, "device.vendor.id", 0x0fd9) : 1;
        int device_product = device_props ? usb_matches(device_props, "device.product.id", 0x007d) : 1;
        if (vendor < 0 || product < 0 || device_vendor < 0 || device_product < 0) return UNKNOWN;
        if (!vendor || !product || !device_vendor || !device_product) continue;
        ++candidates;
        chosen = props;
        chosen_device = device_info;
    }
    if (cores != 1) return UNKNOWN;
    /* No arbitrary selection when more than one MK1 source is present. */
    if (candidates != 1) return ABSENT;
    const char *name = text(field(chosen, "node.name"));
    if (strlen(name) >= sizeof(out->name) ||
        !number(field(chosen, "object.serial"), UINT64_MAX, &out->serial)) return UNKNOWN;
    /* A numeric target must denote only this node, never a reused graph ID. */
    unsigned serial_matches = 0;
    for (size_t i = 0; i < count; ++i) {
        struct json_object *object = json_object_array_get_idx(objects, i);
        uint64_t serial;
        if (equals(field(object, "type"), NODE) &&
            number(field(field(field(object, "info"), "props"), "object.serial"),
                   UINT64_MAX, &serial) && serial == out->serial) ++serial_matches;
    }
    if (serial_matches != 1) return UNKNOWN;
    strcpy(out->name, name);
    out->cookie = cookie;
    out->muted = input_mute(chosen, chosen_device);
    return FOUND;
}

static void watch_restarted(struct watch *watch, double now)
{
    watch->started = watch->last_data = watch->silence_since = now;
    watch->received = false;
}

static void watch_data(struct watch *watch, double now, bool nonzero)
{
    watch->last_data = now;
    watch->received = true;
    if (nonzero) {
        watch->silence_since = now;
        watch->silence_spent = false;
    }
}

static const char *watch_step(struct watch *watch, double now, bool alive, bool known, int muted)
{
    if (!known || muted < 0) { watch->silence_since = now; return NULL; }
    if (!alive) return "capture exited";
    if (now - watch->started < 1) return NULL;
    if (now - watch->last_data >= 3) return "no PCM for three seconds";
    if (!watch->received) return NULL;
    if (muted) watch->silence_since = now;
    else if (now - watch->silence_since >= 30 && !watch->silence_spent) {
        watch->silence_spent = true;
        return "digital silence for thirty seconds";
    }
    return NULL;
}

static bool spawn_child(struct child *child, char *const argv[], double now)
{
    int pipes[2];
    if (pipe(pipes) < 0) return false;
    int null = open("/dev/null", O_RDWR);
    if (null < 0 || fcntl(pipes[0], F_SETFD, FD_CLOEXEC) < 0 ||
        fcntl(pipes[1], F_SETFD, FD_CLOEXEC) < 0 ||
        fcntl(pipes[0], F_SETFL, O_NONBLOCK) < 0) {
        if (null >= 0) close(null);
        close(pipes[0]); close(pipes[1]); return false;
    }
    pid_t pid = fork();
    if (pid == 0) {
        signal(SIGTERM, SIG_DFL); signal(SIGINT, SIG_DFL);
        if (dup2(null, STDIN_FILENO) < 0 || dup2(null, STDERR_FILENO) < 0 ||
            dup2(pipes[1], STDOUT_FILENO) < 0) _exit(127);
        close(null); close(pipes[0]); close(pipes[1]);
        execvp(argv[0], argv);
        _exit(127);
    }
    close(null); close(pipes[1]);
    if (pid < 0) { close(pipes[0]); return false; }
    *child = (struct child){ .pid = pid, .fd = pipes[0], .started = now, .active = true };
    return true;
}

static void close_pipe(struct child *child)
{
    if (child->fd >= 0) { close(child->fd); child->fd = -1; }
}

static void retire_child(struct child *child, double now)
{
    close_pipe(child);
    if (child->pid > 0 && !child->stopping) {
        kill(child->pid, SIGTERM);
        child->stopping = now;
    }
    if (!child->pid) child->active = false;
}

static void reap_child(struct child *child, double now)
{
    if (child->pid <= 0) return;
    if (child->stopping && now - child->stopping >= 1) kill(child->pid, SIGKILL);
    if (waitpid(child->pid, &child->status, WNOHANG) == child->pid) {
        child->pid = 0;
        if (child->stopping) child->active = false;
    }
}

static enum graph_state decode_graph(const char *data, size_t length, struct node *node)
{
    struct json_tokener *tokener = json_tokener_new();
    if (!tokener) return UNKNOWN;
    json_tokener_set_flags(tokener, JSON_TOKENER_STRICT);
    struct json_object *objects = json_tokener_parse_ex(tokener, data, (int)length);
    size_t end = json_tokener_get_parse_end(tokener);
    while (end < length && isspace((unsigned char)data[end])) ++end;
    enum graph_state state = UNKNOWN;
    if (json_tokener_get_error(tokener) == json_tokener_success && end == length)
        state = parse_graph(objects, node);
    json_object_put(objects);
    json_tokener_free(tokener);
    return state;
}

int main(void)
{
    struct sigaction action = { .sa_handler = interrupted };
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGTERM, &action, NULL) < 0 || sigaction(SIGINT, &action, NULL) < 0) return 1;
    struct child capture = { .fd = -1 }, dump = { .fd = -1 };
    struct watch watch = {0};
    struct node node = {0}, pinned = {0};
    enum graph_state graph = UNKNOWN;
    double next_dump = 0, next_start = 0;
    char *dump_data = NULL;
    size_t dump_length = 0, dump_capacity = 0;
    int result = 0;
    while (!stopping || capture.active || dump.active) {
        double now = monotonic();
        if (stopping) { retire_child(&capture, now); retire_child(&dump, now); }
        struct pollfd fds[2] = {
            { .fd = capture.fd, .events = POLLIN },
            { .fd = dump.fd, .events = POLLIN },
        };
        int ready = poll(fds, 2, 100);
        if (ready < 0 && errno != EINTR) { stopping = 1; result = 1; }
        now = monotonic();
        /* Drain PCM first, including while pw-dump is running or stalled. */
        for (unsigned i = 0; i < 2; ++i) {
            struct child *child = i ? &dump : &capture;
            if (child->fd < 0 || !fds[i].revents) continue;
            unsigned char bytes[8192];
            ssize_t size;
            while ((size = read(child->fd, bytes, sizeof(bytes))) > 0) {
                if (i == 0) {
                    bool nonzero = false;
                    for (ssize_t j = 0; j < size && !nonzero; ++j) nonzero = bytes[j] != 0;
                    watch_data(&watch, monotonic(), nonzero);
                } else {
                    size_t needed = dump_length + (size_t)size;
                    if (needed > DUMP_LIMIT) {
                        graph = UNKNOWN; retire_child(&dump, now); next_dump = now + 1; break;
                    }
                    if (needed > dump_capacity) {
                        size_t capacity = dump_capacity ? dump_capacity * 2 : 16384;
                        if (capacity < needed) capacity = needed;
                        char *grown = realloc(dump_data, capacity);
                        if (!grown) { stopping = 1; result = 1; break; }
                        dump_data = grown; dump_capacity = capacity;
                    }
                    memcpy(dump_data + dump_length, bytes, (size_t)size);
                    dump_length = needed;
                }
            }
            if (size == 0 || (size < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR))
                close_pipe(child);
        }
        now = monotonic();
        reap_child(&capture, now); reap_child(&dump, now);
        if (stopping) continue;
        if (dump.active && !dump.stopping && !dump.pid && dump.fd < 0) {
            graph = WIFEXITED(dump.status) && WEXITSTATUS(dump.status) == 0 && dump_length
                ? decode_graph(dump_data, dump_length, &node) : UNKNOWN;
            dump.active = false;
            next_dump = now + 1;
            if (graph != UNKNOWN && capture.active &&
                (graph == ABSENT || node.cookie != pinned.cookie || node.serial != pinned.serial ||
                 strcmp(node.name, pinned.name) != 0)) {
                retire_child(&capture, now);
                next_start = now + 1;
            }
        } else if (dump.active && !dump.stopping && now - dump.started >= 2) {
            graph = UNKNOWN;
            retire_child(&dump, now);
            next_dump = now + 1;
        }
        if (!dump.active && now >= next_dump) {
            char *argv[] = { "pw-dump", NULL };
            dump_length = 0;
            if (!spawn_child(&dump, argv, now)) { graph = UNKNOWN; next_dump = now + 3; }
        }
        if (capture.active && !capture.stopping) {
            const char *reason = watch_step(&watch, now, capture.pid > 0 && capture.fd >= 0,
                                           graph == FOUND, node.muted);
            if (reason) {
                fprintf(stderr, "Restarting owned capture: %s\n", reason);
                retire_child(&capture, now);
                if (next_start < now + 1) next_start = now + 1;
            }
        }
        if (!capture.active && graph == FOUND && now >= next_start) {
            char serial[21];
            snprintf(serial, sizeof(serial), "%" PRIu64, node.serial);
            char *argv[] = {
                "pw-cat", "--record", "--raw", "--target", serial,
                "--channels", "1", "--format", "s16", "--rate", "48000",
                "--latency", "200ms", "--properties",
                "{\"application.name\":\"wave-xlr-keepalive\",\"node.name\":\"wave-xlr-keepalive\","
                "\"node.dont-fallback\":true,\"node.dont-move\":true,\"node.dont-reconnect\":true}",
                "-", NULL,
            };
            next_start = now + 3;
            if (spawn_child(&capture, argv, now)) {
                pinned = node;
                /* Keep the silence allowance across child/server/hotplug lifetimes. */
                watch_restarted(&watch, now);
            } else perror("Cannot start capture");
        }
    }
    free(dump_data);
    return result;
}
