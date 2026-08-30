#include <EGL/egl.h>
#include <EGL/fbdev_window.h>
#include <GLES/gl.h>

#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static void print_egl_error(const char *operation)
{
    fprintf(stderr, "%s failed (EGL error 0x%04x)\n", operation,
            (unsigned int)eglGetError());
}

static int parse_positive(const char *value, const char *name)
{
    char *end = NULL;
    long parsed = strtol(value, &end, 10);

    if (value[0] == '\0' || end == NULL || *end != '\0' || parsed < 1 || parsed > 65535) {
        fprintf(stderr, "invalid %s: %s\n", name, value);
        return -1;
    }
    return (int)parsed;
}

int main(int argc, char **argv)
{
    int width = 1280;
    int height = 720;
    int frames = 180;
    int fb_fd = -1;
    int i;
    struct fb_var_screeninfo vinfo;
    fbdev_window native_window;
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLSurface surface = EGL_NO_SURFACE;
    EGLContext context = EGL_NO_CONTEXT;
    EGLConfig config;
    EGLint config_count = 0;
    EGLint major = 0;
    EGLint minor = 0;
    const EGLint config_attributes[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_NONE
    };
    const EGLint context_attributes[] = {
        EGL_CONTEXT_CLIENT_VERSION, 1,
        EGL_NONE
    };

    for (i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--frames") == 0 && i + 1 < argc) {
            frames = parse_positive(argv[++i], "frame count");
            if (frames < 0) {
                return 2;
            }
        } else if (strcmp(argv[i], "--use-fb-size") == 0) {
            width = 0;
            height = 0;
        } else {
            fprintf(stderr, "usage: %s [--frames N] [--use-fb-size]\n", argv[0]);
            return 2;
        }
    }

    fb_fd = open("/dev/fb0", O_RDWR);
    if (fb_fd < 0) {
        fprintf(stderr, "cannot open /dev/fb0: %s\n", strerror(errno));
        return 1;
    }
    if (ioctl(fb_fd, FBIOGET_VSCREENINFO, &vinfo) != 0) {
        fprintf(stderr, "FBIOGET_VSCREENINFO failed: %s\n", strerror(errno));
        close(fb_fd);
        return 1;
    }
    close(fb_fd);

    printf("framebuffer: %ux%u, %u bpp; GLES1 window: %dx%d\n",
           vinfo.xres, vinfo.yres, vinfo.bits_per_pixel,
           width != 0 ? width : (int)vinfo.xres,
           height != 0 ? height : (int)vinfo.yres);

    native_window.width = (unsigned short)(width != 0 ? width : (int)vinfo.xres);
    native_window.height = (unsigned short)(height != 0 ? height : (int)vinfo.yres);

    display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (display == EGL_NO_DISPLAY) {
        print_egl_error("eglGetDisplay");
        goto fail;
    }
    if (eglInitialize(display, &major, &minor) != EGL_TRUE) {
        print_egl_error("eglInitialize");
        goto fail;
    }
    if (eglBindAPI(EGL_OPENGL_ES_API) != EGL_TRUE) {
        print_egl_error("eglBindAPI");
        goto fail;
    }
    if (eglChooseConfig(display, config_attributes, &config, 1, &config_count) != EGL_TRUE ||
        config_count < 1) {
        print_egl_error("eglChooseConfig");
        goto fail;
    }
    surface = eglCreateWindowSurface(display, config, &native_window, NULL);
    if (surface == EGL_NO_SURFACE) {
        print_egl_error("eglCreateWindowSurface");
        goto fail;
    }
    context = eglCreateContext(display, config, EGL_NO_CONTEXT, context_attributes);
    if (context == EGL_NO_CONTEXT) {
        print_egl_error("eglCreateContext");
        goto fail;
    }
    if (eglMakeCurrent(display, surface, surface, context) != EGL_TRUE) {
        print_egl_error("eglMakeCurrent");
        goto fail;
    }

    printf("EGL %d.%d vendor=%s version=%s\n", major, minor,
           eglQueryString(display, EGL_VENDOR), eglQueryString(display, EGL_VERSION));
    printf("GL vendor=%s renderer=%s version=%s\n",
           glGetString(GL_VENDOR), glGetString(GL_RENDERER), glGetString(GL_VERSION));

    eglSwapInterval(display, 1);
    glViewport(0, 0, native_window.width, native_window.height);
    for (i = 0; i < frames; ++i) {
        float phase = (float)(i % 120) / 119.0f;
        glClearColor(0.45f - 0.25f * phase, 0.10f + 0.55f * phase, 0.08f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        if (eglSwapBuffers(display, surface) != EGL_TRUE) {
            print_egl_error("eglSwapBuffers");
            goto fail;
        }
    }

    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(display, context);
    eglDestroySurface(display, surface);
    eglTerminate(display);
    puts("EGL GLES1 smoke test completed successfully");
    return 0;

fail:
    if (display != EGL_NO_DISPLAY) {
        eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (context != EGL_NO_CONTEXT) {
            eglDestroyContext(display, context);
        }
        if (surface != EGL_NO_SURFACE) {
            eglDestroySurface(display, surface);
        }
        eglTerminate(display);
    }
    return 1;
}
