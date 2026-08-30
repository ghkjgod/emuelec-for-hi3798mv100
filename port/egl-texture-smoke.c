#include <EGL/egl.h>
#include <EGL/fbdev_window.h>
#include <GLES2/gl2.h>

#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static const char *vertex_shader_source =
    "attribute vec2 TexCoord;\n"
    "attribute vec2 VertexCoord;\n"
    "uniform mat4 MVPMatrix;\n"
    "varying vec2 tex_coord;\n"
    "void main() {\n"
    "  gl_Position = MVPMatrix * vec4(VertexCoord, 0.0, 1.0);\n"
    "  tex_coord = TexCoord;\n"
    "}\n";

static const char *fragment_shader_source =
    "precision mediump float;\n"
    "uniform sampler2D Texture;\n"
    "varying vec2 tex_coord;\n"
    "void main() {\n"
    "  gl_FragColor = texture2D(Texture, tex_coord);\n"
    "}\n";

static void print_egl_error(const char *operation)
{
    fprintf(stderr, "%s failed (EGL error 0x%04x)\n", operation,
            (unsigned int)eglGetError());
}

static int check_gl(const char *operation)
{
    GLenum error = glGetError();
    if (error != GL_NO_ERROR) {
        fprintf(stderr, "%s failed (GL error 0x%04x)\n", operation,
                (unsigned int)error);
        return 0;
    }
    return 1;
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

static GLuint compile_shader(GLenum type, const char *source)
{
    GLuint shader = glCreateShader(type);
    GLint status = GL_FALSE;
    GLint log_length = 0;

    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);
    glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &log_length);
    if (log_length > 1) {
        char *log = malloc((size_t)log_length);
        if (log != NULL) {
            glGetShaderInfoLog(shader, log_length, NULL, log);
            fprintf(stderr, "shader log: %s\n", log);
            free(log);
        }
    }
    if (status != GL_TRUE) {
        fprintf(stderr, "shader compilation failed\n");
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

static GLuint create_program(void)
{
    GLuint vertex_shader = compile_shader(GL_VERTEX_SHADER, vertex_shader_source);
    GLuint fragment_shader = compile_shader(GL_FRAGMENT_SHADER, fragment_shader_source);
    GLuint program;
    GLint status = GL_FALSE;
    GLint log_length = 0;

    if (vertex_shader == 0 || fragment_shader == 0) {
        return 0;
    }
    program = glCreateProgram();
    glAttachShader(program, vertex_shader);
    glAttachShader(program, fragment_shader);
    glLinkProgram(program);
    glGetProgramiv(program, GL_LINK_STATUS, &status);
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, &log_length);
    if (log_length > 1) {
        char *log = malloc((size_t)log_length);
        if (log != NULL) {
            glGetProgramInfoLog(program, log_length, NULL, log);
            fprintf(stderr, "program log: %s\n", log);
            free(log);
        }
    }
    glDeleteShader(vertex_shader);
    glDeleteShader(fragment_shader);
    if (status != GL_TRUE) {
        fprintf(stderr, "program link failed\n");
        glDeleteProgram(program);
        return 0;
    }
    return program;
}

static uint16_t rgb565(unsigned red, unsigned green, unsigned blue)
{
    return (uint16_t)(((red & 0xf8U) << 8) |
                      ((green & 0xfcU) << 3) |
                      ((blue & 0xf8U) >> 3));
}

static void fill_test_pattern(uint16_t *pixels, unsigned width, unsigned height)
{
    unsigned x;
    unsigned y;

    for (y = 0; y < height; ++y) {
        for (x = 0; x < width; ++x) {
            unsigned tile_x = x / 16U;
            unsigned tile_y = y / 16U;
            unsigned selector = (tile_x + tile_y) & 3U;
            uint16_t color;

            if (selector == 0U) {
                color = rgb565(255, 32, 32);
            } else if (selector == 1U) {
                color = rgb565(32, 255, 32);
            } else if (selector == 2U) {
                color = rgb565(32, 64, 255);
            } else {
                color = rgb565(255, 255, 255);
            }
            pixels[y * width + x] = color;
        }
    }
}

int main(int argc, char **argv)
{
    enum { MODE_RA_VBO, MODE_KEEP_BOUND, MODE_CLIENT } mode = MODE_RA_VBO;
    const unsigned texture_width = 512;
    const unsigned texture_height = 256;
    const unsigned image_width = 256;
    const unsigned image_height = 224;
    const GLfloat vertices[] = { 0, 0, 1, 0, 0, 1, 1, 1 };
    const GLfloat texcoords[] = { 0, 0, 0.5f, 0, 0, 0.875f, 0.5f, 0.875f };
    const GLfloat matrix[] = {
        2, 0, 0, 0,
        0, 2, 0, 0,
        0, 0, -1, 0,
       -1,-1, 0, 1
    };
    GLfloat arrays[16];
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
    GLuint program = 0;
    GLuint texture = 0;
    GLuint vbo = 0;
    GLint texcoord_location;
    GLint vertex_location;
    GLint matrix_location;
    GLint texture_location;
    uint16_t *pixels = NULL;
    const EGLint config_attributes[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_NONE
    };
    const EGLint context_attributes[] = {
        EGL_CONTEXT_CLIENT_VERSION, 2,
        EGL_NONE
    };

    for (i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--frames") == 0 && i + 1 < argc) {
            frames = parse_positive(argv[++i], "frame count");
            if (frames < 0) {
                return 2;
            }
        } else if (strcmp(argv[i], "--mode") == 0 && i + 1 < argc) {
            const char *value = argv[++i];
            if (strcmp(value, "ra-vbo") == 0) {
                mode = MODE_RA_VBO;
            } else if (strcmp(value, "keep-bound") == 0) {
                mode = MODE_KEEP_BOUND;
            } else if (strcmp(value, "client") == 0) {
                mode = MODE_CLIENT;
            } else {
                fprintf(stderr, "invalid mode: %s\n", value);
                return 2;
            }
        } else {
            fprintf(stderr, "usage: %s [--frames N] [--mode ra-vbo|keep-bound|client]\n", argv[0]);
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

    native_window.width = (unsigned short)vinfo.xres;
    native_window.height = (unsigned short)vinfo.yres;
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

    printf("mode=%s framebuffer=%ux%u EGL=%d.%d GL=%s renderer=%s\n",
           mode == MODE_RA_VBO ? "ra-vbo" : mode == MODE_KEEP_BOUND ? "keep-bound" : "client",
           vinfo.xres, vinfo.yres, major, minor, glGetString(GL_VERSION), glGetString(GL_RENDERER));
    program = create_program();
    if (program == 0) {
        goto fail;
    }
    glUseProgram(program);
    texcoord_location = glGetAttribLocation(program, "TexCoord");
    vertex_location = glGetAttribLocation(program, "VertexCoord");
    matrix_location = glGetUniformLocation(program, "MVPMatrix");
    texture_location = glGetUniformLocation(program, "Texture");
    printf("locations TexCoord=%d VertexCoord=%d MVPMatrix=%d Texture=%d\n",
           texcoord_location, vertex_location, matrix_location, texture_location);
    if (texcoord_location < 0 || vertex_location < 0 || matrix_location < 0 || texture_location < 0) {
        fprintf(stderr, "required shader location missing\n");
        goto fail;
    }

    pixels = calloc(texture_width * texture_height, sizeof(*pixels));
    if (pixels == NULL) {
        fprintf(stderr, "texture allocation failed\n");
        goto fail;
    }
    fill_test_pattern(pixels, image_width, image_height);
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, texture_width, texture_height, 0,
                 GL_RGB, GL_UNSIGNED_SHORT_5_6_5, pixels);
    if (!check_gl("texture upload")) {
        goto fail;
    }
    glUniform1i(texture_location, 0);
    glUniformMatrix4fv(matrix_location, 1, GL_FALSE, matrix);
    memcpy(arrays, texcoords, sizeof(texcoords));
    memcpy(arrays + 8, vertices, sizeof(vertices));

    if (mode == MODE_CLIENT) {
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        glEnableVertexAttribArray((GLuint)texcoord_location);
        glVertexAttribPointer((GLuint)texcoord_location, 2, GL_FLOAT, GL_FALSE, 0, arrays);
        glEnableVertexAttribArray((GLuint)vertex_location);
        glVertexAttribPointer((GLuint)vertex_location, 2, GL_FLOAT, GL_FALSE, 0, arrays + 8);
    } else {
        glGenBuffers(1, &vbo);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, sizeof(arrays), arrays, GL_STATIC_DRAW);
        glEnableVertexAttribArray((GLuint)texcoord_location);
        glVertexAttribPointer((GLuint)texcoord_location, 2, GL_FLOAT, GL_FALSE, 0, (const GLvoid *)0);
        glEnableVertexAttribArray((GLuint)vertex_location);
        glVertexAttribPointer((GLuint)vertex_location, 2, GL_FLOAT, GL_FALSE, 0,
                              (const GLvoid *)(uintptr_t)sizeof(texcoords));
        if (mode == MODE_RA_VBO) {
            glBindBuffer(GL_ARRAY_BUFFER, 0);
        }
    }
    if (!check_gl("attribute setup")) {
        goto fail;
    }

    eglSwapInterval(display, 1);
    glViewport(0, 0, native_window.width, native_window.height);
    glClearColor(0.02f, 0.02f, 0.02f, 1.0f);
    for (i = 0; i < frames; ++i) {
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        if (!check_gl("draw")) {
            goto fail;
        }
        if (eglSwapBuffers(display, surface) != EGL_TRUE) {
            print_egl_error("eglSwapBuffers");
            goto fail;
        }
    }
    puts("EGL RGB565 texture smoke test completed successfully");

    glDisableVertexAttribArray((GLuint)texcoord_location);
    glDisableVertexAttribArray((GLuint)vertex_location);
    if (vbo != 0) {
        glDeleteBuffers(1, &vbo);
    }
    glDeleteTextures(1, &texture);
    glDeleteProgram(program);
    free(pixels);
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(display, context);
    eglDestroySurface(display, surface);
    eglTerminate(display);
    return 0;

fail:
    free(pixels);
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
