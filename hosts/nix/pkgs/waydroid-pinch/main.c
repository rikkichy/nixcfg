// Two-finger pinch for Waydroid: the daemon owns a virtual touchscreen; each
// `waydroid-pinch in|out X Y` (fractions of the touch output) steps one pinch.
#include <errno.h>
#include <fcntl.h>
#include <linux/uinput.h>
#include <math.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#define AXIS_MAX 32767
#define IDLE_MS 250
// Finger spans as fractions of the output width; each tick scales the span by SPAN_FACTOR.
#define SPAN_IN 0.10
#define SPAN_OUT 0.60
#define SPAN_MIN 0.04
#define SPAN_FACTOR 1.15

struct request {
	double x, y;
	int in;
};

static int ui;
static int tracking;
static double cx, cy, span; // span 0: fingers up

static void die(const char *what) {
	perror(what);
	exit(1);
}

static int valid(const struct request *r) {
	return r->x >= 0 && r->x <= 1 && r->y >= 0 && r->y <= 1 && (r->in == 0 || r->in == 1);
}

static void emit(int type, int code, int value) {
	struct input_event ev = { .type = type, .code = code, .value = value };
	if (write(ui, &ev, sizeof ev) != sizeof ev)
		die("uinput write");
}

static void control(unsigned long req, unsigned long arg) {
	if (ioctl(ui, req, arg) < 0)
		die("uinput ioctl");
}

static void axis(int code, int max) {
	struct uinput_abs_setup a = { .code = code, .absinfo = { .maximum = max } };
	control(UI_SET_ABSBIT, code);
	if (ioctl(ui, UI_ABS_SETUP, &a) < 0)
		die("UI_ABS_SETUP");
}

static void place(void) {
	int x0 = (cx - span / 2) * AXIS_MAX, x1 = (cx + span / 2) * AXIS_MAX, y = cy * AXIS_MAX;
	emit(EV_ABS, ABS_MT_SLOT, 0);
	emit(EV_ABS, ABS_MT_POSITION_X, x0);
	emit(EV_ABS, ABS_MT_POSITION_Y, y);
	emit(EV_ABS, ABS_MT_SLOT, 1);
	emit(EV_ABS, ABS_MT_POSITION_X, x1);
	emit(EV_ABS, ABS_MT_POSITION_Y, y);
	emit(EV_ABS, ABS_X, x0);
	emit(EV_ABS, ABS_Y, y);
	emit(EV_SYN, SYN_REPORT, 0);
}

static void down(const struct request *r) {
	span = r->in ? SPAN_IN : SPAN_OUT;
	double margin = span * SPAN_FACTOR / 2;
	cx = fmin(fmax(r->x, margin), 1 - margin);
	cy = r->y;
	for (int slot = 0; slot < 2; slot++) {
		emit(EV_ABS, ABS_MT_SLOT, slot);
		emit(EV_ABS, ABS_MT_TRACKING_ID, tracking);
		tracking = (tracking + 1) & 0xffff;
	}
	emit(EV_KEY, BTN_TOUCH, 1);
	place();
}

static void up(void) {
	for (int slot = 0; slot < 2; slot++) {
		emit(EV_ABS, ABS_MT_SLOT, slot);
		emit(EV_ABS, ABS_MT_TRACKING_ID, -1);
	}
	emit(EV_KEY, BTN_TOUCH, 0);
	emit(EV_SYN, SYN_REPORT, 0);
	span = 0;
}

static void pinch(const struct request *r) {
	if (!span)
		down(r);
	double next = r->in ? span * SPAN_FACTOR : span / SPAN_FACTOR;
	if (next < SPAN_MIN || cx - next / 2 < 0 || cx + next / 2 > 1) {
		up();
		down(r);
		next = r->in ? span * SPAN_FACTOR : span / SPAN_FACTOR;
	}
	span = next;
	place();
}

static _Noreturn void serve(int sock, const struct sockaddr_un *addr) {
	ui = open("/dev/uinput", O_WRONLY | O_CLOEXEC);
	if (ui < 0)
		die("/dev/uinput");
	control(UI_SET_EVBIT, EV_KEY);
	control(UI_SET_EVBIT, EV_ABS);
	control(UI_SET_KEYBIT, BTN_TOUCH);
	control(UI_SET_PROPBIT, INPUT_PROP_DIRECT);
	axis(ABS_X, AXIS_MAX);
	axis(ABS_Y, AXIS_MAX);
	axis(ABS_MT_SLOT, 1);
	axis(ABS_MT_TRACKING_ID, 0xffff);
	axis(ABS_MT_POSITION_X, AXIS_MAX);
	axis(ABS_MT_POSITION_Y, AXIS_MAX);
	struct uinput_setup setup = { .id = { .bustype = BUS_VIRTUAL }, .name = "waydroid-pinch" };
	if (ioctl(ui, UI_DEV_SETUP, &setup) < 0)
		die("UI_DEV_SETUP");
	control(UI_DEV_CREATE, 0);

	if (unlink(addr->sun_path) < 0 && errno != ENOENT)
		die(addr->sun_path);
	if (bind(sock, (const struct sockaddr *)addr, sizeof *addr) < 0)
		die(addr->sun_path);

	for (;;) {
		struct pollfd p = { .fd = sock, .events = POLLIN };
		int n = poll(&p, 1, span ? IDLE_MS : -1);
		if (n < 0) {
			if (errno == EINTR)
				continue;
			die("poll");
		}
		if (!n) {
			up();
			continue;
		}
		struct request r;
		ssize_t len = recv(sock, &r, sizeof r, 0);
		if (len < 0) {
			if (errno == EINTR)
				continue;
			die("recv");
		}
		if (len != sizeof r || !valid(&r)) {
			fputs("ignoring malformed request\n", stderr);
			continue;
		}
		pinch(&r);
	}
}

int main(int argc, char **argv) {
	const char *dir = getenv("XDG_RUNTIME_DIR");
	if (!dir) {
		fputs("XDG_RUNTIME_DIR is unset\n", stderr);
		return 1;
	}
	struct sockaddr_un addr = { .sun_family = AF_UNIX };
	if (snprintf(addr.sun_path, sizeof addr.sun_path, "%s/waydroid-pinch.sock", dir) >= (int)sizeof addr.sun_path) {
		fputs("socket path too long\n", stderr);
		return 1;
	}
	int sock = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
	if (sock < 0)
		die("socket");
	if (argc == 1)
		serve(sock, &addr);

	struct request r = { .in = argc == 4 && !strcmp(argv[1], "in") };
	char *end1 = NULL, *end2 = NULL;
	if (argc == 4) {
		r.x = strtod(argv[2], &end1);
		r.y = strtod(argv[3], &end2);
	}
	if (argc != 4 || (!r.in && strcmp(argv[1], "out")) || *end1 || *end2 || !valid(&r)) {
		fputs("usage: waydroid-pinch            run the virtual touchscreen\n"
		      "       waydroid-pinch in|out X Y  pinch at X,Y (0..1 of the output)\n",
		      stderr);
		return 2;
	}
	if (sendto(sock, &r, sizeof r, 0, (const struct sockaddr *)&addr, sizeof addr) != sizeof r)
		die(addr.sun_path);
	return 0;
}
