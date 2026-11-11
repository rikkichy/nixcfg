// Two-finger pinch for Waydroid. `waydroid-pinch start` (bound to pressing
// Alt) shows a transparent overlay that takes the pointer and keyboard, so
// mouse motion stops reaching Waydroid; Android cancels touch gestures when the
// mouse moves. The overlay closes itself when Alt is released, Escape is
// pressed or it loses keyboard focus. Finger 1 is where the cursor was when
// Alt went down (marked with a ring); pressing the left button puts finger 2 at
// the cursor. Dragging moves finger 2 with the cursor and finger 1 the opposite
// way around their midpoint. The overlay must cover the fullscreen Waydroid
// window (see rules.lua).
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/input-event-codes.h>
#include <linux/uinput.h>
#include <math.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <wayland-client.h>

#include "wlr-layer-shell-unstable-v1-client-protocol.h"

#define AXIS_MAX 32767
#define MIN_GAP_PX 40.0
#define HOLE_PX 16
#define RING_RADIUS 18.0

static int ui;
static int tracking;

static struct wl_display *display;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct wl_seat *seat;
static struct wl_pointer *pointer;
static struct wl_keyboard *keyboard;
static struct zwlr_layer_shell_v1 *layer_shell;

// Overlay state, all in overlay surface coordinates.
static struct wl_surface *shield;
static struct zwlr_layer_surface_v1 *shield_layer;
static struct wl_buffer *ring_buffer, *clear_buffer;
static uint32_t *pixels;
static size_t pixels_size;
static int width, height;
// Touch-down moves keyboard focus to Waydroid, so a pinch in progress outlives
// the overlay's keyboard focus and closes it on button release instead.
static int have_anchor, focused, pressed, touching;
static double anchor_x, anchor_y, pointer_x, pointer_y, mid_x, mid_y;

static void die(const char *what) {
	perror(what);
	exit(1);
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

static int scale(double v, int size) {
	return fmin(fmax(v / size, 0), 1) * AXIS_MAX;
}

static void place(void) {
	double x1 = 2 * mid_x - pointer_x, y1 = 2 * mid_y - pointer_y;
	if (hypot(pointer_x - x1, pointer_y - y1) < MIN_GAP_PX)
		return;
	emit(EV_ABS, ABS_MT_SLOT, 0);
	emit(EV_ABS, ABS_MT_POSITION_X, scale(x1, width));
	emit(EV_ABS, ABS_MT_POSITION_Y, scale(y1, height));
	emit(EV_ABS, ABS_MT_SLOT, 1);
	emit(EV_ABS, ABS_MT_POSITION_X, scale(pointer_x, width));
	emit(EV_ABS, ABS_MT_POSITION_Y, scale(pointer_y, height));
	emit(EV_ABS, ABS_X, scale(x1, width));
	emit(EV_ABS, ABS_Y, scale(y1, height));
	emit(EV_SYN, SYN_REPORT, 0);
}

static void lift(void) {
	if (!touching)
		return;
	for (int slot = 0; slot < 2; slot++) {
		emit(EV_ABS, ABS_MT_SLOT, slot);
		emit(EV_ABS, ABS_MT_TRACKING_ID, -1);
	}
	emit(EV_KEY, BTN_TOUCH, 0);
	emit(EV_SYN, SYN_REPORT, 0);
	touching = 0;
}

static void show(struct wl_buffer *buffer) {
	wl_surface_attach(shield, buffer, 0, 0);
	wl_surface_damage(shield, 0, 0, width, height);
	wl_surface_commit(shield);
}

static void draw_ring(void) {
	memset(pixels, 0, (size_t)width * height * 4);
	int r = RING_RADIUS + 3;
	for (int y = anchor_y - r; y <= anchor_y + r; y++)
		for (int x = anchor_x - r; x <= anchor_x + r; x++) {
			if (x < 0 || y < 0 || x >= width || y >= height)
				continue;
			double d = fabs(hypot(x + 0.5 - anchor_x, y + 0.5 - anchor_y) - RING_RADIUS);
			if (d <= 1.5)
				pixels[(size_t)y * width + x] = 0xe6e6e6e6; // premultiplied white
			else if (d <= 3)
				pixels[(size_t)y * width + x] = 0x80000000;
		}
}

static void hide(void) {
	if (!shield)
		return;
	lift();
	pressed = 0;
	if (ring_buffer) {
		wl_buffer_destroy(ring_buffer);
		wl_buffer_destroy(clear_buffer);
		munmap(pixels, pixels_size);
	}
	zwlr_layer_surface_v1_destroy(shield_layer);
	wl_surface_destroy(shield);
	ring_buffer = clear_buffer = NULL;
	shield_layer = NULL;
	shield = NULL;
}

static void layer_configure(void *data, struct zwlr_layer_surface_v1 *layer, uint32_t serial, uint32_t w,
                            uint32_t h) {
	(void)data;
	zwlr_layer_surface_v1_ack_configure(layer, serial);
	if (ring_buffer || !w || !h)
		return;
	width = w;
	height = h;
	// Two frames: the ring for finger 1 and a fully transparent one.
	size_t frame = (size_t)w * h * 4;
	pixels_size = 2 * frame;
	int fd = memfd_create("waydroid-pinch", MFD_CLOEXEC);
	if (fd < 0 || ftruncate(fd, pixels_size) < 0)
		die("overlay buffer");
	pixels = mmap(NULL, pixels_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (pixels == MAP_FAILED)
		die("overlay mmap");
	struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, pixels_size);
	ring_buffer = wl_shm_pool_create_buffer(pool, 0, w, h, w * 4, WL_SHM_FORMAT_ARGB8888);
	clear_buffer = wl_shm_pool_create_buffer(pool, frame, w, h, w * 4, WL_SHM_FORMAT_ARGB8888);
	wl_shm_pool_destroy(pool);
	close(fd);
	show(clear_buffer);
}

static void layer_closed(void *data, struct zwlr_layer_surface_v1 *layer) {
	(void)data;
	(void)layer;
	hide();
}

static const struct zwlr_layer_surface_v1_listener layer_listener = {
	.configure = layer_configure,
	.closed = layer_closed,
};

static void start(void) {
	hide();
	have_anchor = focused = 0;
	shield = wl_compositor_create_surface(compositor);
	shield_layer = zwlr_layer_shell_v1_get_layer_surface(layer_shell, shield, NULL, ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY,
	                                                     "waydroid-pinch");
	zwlr_layer_surface_v1_add_listener(shield_layer, &layer_listener, NULL);
	zwlr_layer_surface_v1_set_anchor(shield_layer, ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
	                                                       ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
	                                                       ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
	zwlr_layer_surface_v1_set_exclusive_zone(shield_layer, -1);
	zwlr_layer_surface_v1_set_keyboard_interactivity(shield_layer, 1);
	wl_surface_commit(shield);
}

// Touch focus is chosen at touch-down, so the fingers land through holes in the
// overlay's input region and stay with Waydroid afterwards.
static void touch_down(void *data, struct wl_callback *cb, uint32_t time) {
	(void)data;
	(void)time;
	wl_callback_destroy(cb);
	if (!pressed || touching)
		return;
	for (int slot = 0; slot < 2; slot++) {
		emit(EV_ABS, ABS_MT_SLOT, slot);
		emit(EV_ABS, ABS_MT_TRACKING_ID, tracking);
		tracking = (tracking + 1) & 0xffff;
	}
	emit(EV_KEY, BTN_TOUCH, 1);
	touching = 1;
	place();
}

static const struct wl_callback_listener touch_down_listener = { .done = touch_down };

static void press(void) {
	if (!ring_buffer || !have_anchor || hypot(pointer_x - anchor_x, pointer_y - anchor_y) < MIN_GAP_PX)
		return;
	mid_x = (anchor_x + pointer_x) / 2;
	mid_y = (anchor_y + pointer_y) / 2;
	pressed = 1;
	struct wl_region *region = wl_compositor_create_region(compositor);
	wl_region_add(region, 0, 0, width, height);
	wl_region_subtract(region, anchor_x - HOLE_PX / 2, anchor_y - HOLE_PX / 2, HOLE_PX, HOLE_PX);
	wl_region_subtract(region, pointer_x - HOLE_PX / 2, pointer_y - HOLE_PX / 2, HOLE_PX, HOLE_PX);
	wl_surface_set_input_region(shield, region);
	wl_region_destroy(region);
	show(clear_buffer);
	wl_callback_add_listener(wl_display_sync(display), &touch_down_listener, NULL);
}

static void release(void) {
	if (!focused) {
		hide();
		return;
	}
	lift();
	pressed = 0;
	wl_surface_set_input_region(shield, NULL);
	show(ring_buffer);
}

static void pointer_enter(void *data, struct wl_pointer *p, uint32_t serial, struct wl_surface *s, wl_fixed_t x,
                          wl_fixed_t y) {
	(void)data;
	(void)p;
	(void)serial;
	if (!shield || s != shield)
		return;
	pointer_x = wl_fixed_to_double(x);
	pointer_y = wl_fixed_to_double(y);
	if (!have_anchor && ring_buffer) {
		anchor_x = pointer_x;
		anchor_y = pointer_y;
		have_anchor = 1;
		draw_ring();
		show(ring_buffer);
	}
}

static void pointer_leave(void *data, struct wl_pointer *p, uint32_t serial, struct wl_surface *s) {
	(void)data;
	(void)p;
	(void)serial;
	(void)s;
}

static void pointer_motion(void *data, struct wl_pointer *p, uint32_t time, wl_fixed_t x, wl_fixed_t y) {
	(void)data;
	(void)p;
	(void)time;
	if (!shield)
		return;
	pointer_x = wl_fixed_to_double(x);
	pointer_y = wl_fixed_to_double(y);
	if (touching)
		place();
}

static void pointer_button(void *data, struct wl_pointer *p, uint32_t serial, uint32_t time, uint32_t button,
                           uint32_t state) {
	(void)data;
	(void)p;
	(void)serial;
	(void)time;
	if (!shield || button != BTN_LEFT)
		return;
	if (state == WL_POINTER_BUTTON_STATE_PRESSED && !focused && !pressed)
		hide(); // Stale overlay without keyboard focus: any click dismisses it.
	else if (state == WL_POINTER_BUTTON_STATE_PRESSED)
		press();
	else if (pressed)
		release();
}

static void pointer_axis(void *data, struct wl_pointer *p, uint32_t time, uint32_t a, wl_fixed_t v) {
	(void)data;
	(void)p;
	(void)time;
	(void)a;
	(void)v;
}

// Seat version 1: only these pointer events are ever sent.
static const struct wl_pointer_listener pointer_listener = {
	.enter = pointer_enter,
	.leave = pointer_leave,
	.motion = pointer_motion,
	.button = pointer_button,
	.axis = pointer_axis,
};

static void keyboard_keymap(void *data, struct wl_keyboard *k, uint32_t format, int32_t fd, uint32_t size) {
	(void)data;
	(void)k;
	(void)format;
	(void)size;
	close(fd);
}

static void keyboard_enter(void *data, struct wl_keyboard *k, uint32_t serial, struct wl_surface *s,
                           struct wl_array *keys) {
	(void)data;
	(void)k;
	(void)serial;
	if (!shield || s != shield)
		return;
	uint32_t *key;
	wl_array_for_each(key, keys) {
		if (*key == KEY_LEFTALT) {
			focused = 1;
			return;
		}
	}
	hide(); // Alt was already released.
}

static void keyboard_leave(void *data, struct wl_keyboard *k, uint32_t serial, struct wl_surface *s) {
	(void)data;
	(void)k;
	(void)serial;
	if (!shield || s != shield)
		return;
	focused = 0;
	if (!pressed)
		hide();
}

static void keyboard_key(void *data, struct wl_keyboard *k, uint32_t serial, uint32_t time, uint32_t key,
                         uint32_t state) {
	(void)data;
	(void)k;
	(void)serial;
	(void)time;
	if (shield && ((key == KEY_LEFTALT && state == WL_KEYBOARD_KEY_STATE_RELEASED) || key == KEY_ESC))
		hide();
}

static void keyboard_modifiers(void *data, struct wl_keyboard *k, uint32_t serial, uint32_t depressed,
                               uint32_t latched, uint32_t locked, uint32_t group) {
	(void)data;
	(void)k;
	(void)serial;
	(void)depressed;
	(void)latched;
	(void)locked;
	(void)group;
}

static const struct wl_keyboard_listener keyboard_listener = {
	.keymap = keyboard_keymap,
	.enter = keyboard_enter,
	.leave = keyboard_leave,
	.key = keyboard_key,
	.modifiers = keyboard_modifiers,
};

static void seat_capabilities(void *data, struct wl_seat *s, uint32_t caps) {
	(void)data;
	if ((caps & WL_SEAT_CAPABILITY_POINTER) && !pointer) {
		pointer = wl_seat_get_pointer(s);
		wl_pointer_add_listener(pointer, &pointer_listener, NULL);
	}
	if ((caps & WL_SEAT_CAPABILITY_KEYBOARD) && !keyboard) {
		keyboard = wl_seat_get_keyboard(s);
		wl_keyboard_add_listener(keyboard, &keyboard_listener, NULL);
	}
}

static const struct wl_seat_listener seat_listener = { .capabilities = seat_capabilities };

static void registry_global(void *data, struct wl_registry *registry, uint32_t name, const char *interface,
                            uint32_t version) {
	(void)data;
	(void)version;
	if (!strcmp(interface, wl_compositor_interface.name))
		compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 1);
	else if (!strcmp(interface, wl_shm_interface.name))
		shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
	else if (!strcmp(interface, wl_seat_interface.name) && !seat) {
		seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
		wl_seat_add_listener(seat, &seat_listener, NULL);
	} else if (!strcmp(interface, zwlr_layer_shell_v1_interface.name))
		layer_shell = wl_registry_bind(registry, name, &zwlr_layer_shell_v1_interface, 1);
}

static void registry_remove(void *data, struct wl_registry *registry, uint32_t name) {
	(void)data;
	(void)registry;
	(void)name;
}

static const struct wl_registry_listener registry_listener = {
	.global = registry_global,
	.global_remove = registry_remove,
};

static _Noreturn void serve(int sock, const struct sockaddr_un *addr) {
	display = wl_display_connect(NULL);
	if (!display)
		die("wl_display_connect");
	wl_registry_add_listener(wl_display_get_registry(display), &registry_listener, NULL);
	if (wl_display_roundtrip(display) < 0 || wl_display_roundtrip(display) < 0)
		die("wayland roundtrip");
	if (!compositor || !shm || !seat || !layer_shell) {
		fputs("compositor lacks wl_compositor, wl_shm, wl_seat or wlr-layer-shell\n", stderr);
		exit(1);
	}

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
		while (wl_display_prepare_read(display) != 0)
			if (wl_display_dispatch_pending(display) < 0)
				die("wayland dispatch");
		if (wl_display_flush(display) < 0 && errno != EAGAIN)
			die("wayland flush");
		struct pollfd p[2] = {
			{ .fd = sock, .events = POLLIN },
			{ .fd = wl_display_get_fd(display), .events = POLLIN },
		};
		if (poll(p, 2, -1) < 0) {
			wl_display_cancel_read(display);
			if (errno == EINTR)
				continue;
			die("poll");
		}
		if (p[1].revents & POLLIN) {
			if (wl_display_read_events(display) < 0)
				die("wayland read");
		} else {
			wl_display_cancel_read(display);
		}
		if (p[1].revents & (POLLERR | POLLHUP)) {
			fputs("compositor connection closed\n", stderr);
			exit(1);
		}
		if (wl_display_dispatch_pending(display) < 0)
			die("wayland dispatch");
		if (!(p[0].revents & POLLIN))
			continue;
		char msg;
		ssize_t len = recv(sock, &msg, 1, 0);
		if (len < 0) {
			if (errno == EINTR)
				continue;
			die("recv");
		}
		if (len == 1 && msg == 's')
			start();
		else
			fputs("ignoring malformed request\n", stderr);
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

	if (argc != 2 || strcmp(argv[1], "start")) {
		fputs("usage: waydroid-pinch        run the virtual touchscreen\n"
		      "       waydroid-pinch start  show the pinch overlay while Alt is held\n",
		      stderr);
		return 2;
	}
	char msg = 's';
	if (sendto(sock, &msg, 1, 0, (const struct sockaddr *)&addr, sizeof addr) != 1)
		die(addr.sun_path);
	return 0;
}
