#include <SDL.h>
#include <SDL_opengles2.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int parse_frames(const char *value)
{
    char *end = NULL;
    long parsed = strtol(value, &end, 10);

    if (value[0] == '\0' || end == NULL || *end != '\0' || parsed < 1 || parsed > 36000) {
        return -1;
    }
    return (int)parsed;
}

int main(int argc, char **argv)
{
    int frames = 180;
    int i;
    SDL_Window *window = NULL;
    SDL_GLContext context = NULL;
    SDL_DisplayMode mode;

    if (argc == 3 && strcmp(argv[1], "--frames") == 0) {
        frames = parse_frames(argv[2]);
        if (frames < 0) {
            fprintf(stderr, "invalid frame count: %s\n", argv[2]);
            return 2;
        }
    } else if (argc != 1) {
        fprintf(stderr, "usage: %s [--frames N]\n", argv[0]);
        return 2;
    }

    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) != 0) {
        fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }
    printf("SDL video driver: %s\n", SDL_GetCurrentVideoDriver());

    if (SDL_GetCurrentDisplayMode(0, &mode) != 0) {
        fprintf(stderr, "SDL_GetCurrentDisplayMode failed: %s\n", SDL_GetError());
        goto fail;
    }
    printf("display mode: %dx%d @ %d Hz\n", mode.w, mode.h, mode.refresh_rate);

    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
    SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, 8);

    window = SDL_CreateWindow("HiSTB SDL2 Mali smoke test",
                              SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                              1280, 720,
                              SDL_WINDOW_OPENGL | SDL_WINDOW_FULLSCREEN | SDL_WINDOW_SHOWN);
    if (window == NULL) {
        fprintf(stderr, "SDL_CreateWindow failed: %s\n", SDL_GetError());
        goto fail;
    }
    context = SDL_GL_CreateContext(window);
    if (context == NULL) {
        fprintf(stderr, "SDL_GL_CreateContext failed: %s\n", SDL_GetError());
        goto fail;
    }

    printf("GL vendor=%s renderer=%s version=%s\n",
           glGetString(GL_VENDOR), glGetString(GL_RENDERER), glGetString(GL_VERSION));
    SDL_GL_SetSwapInterval(1);
    glViewport(0, 0, mode.w, mode.h);

    for (i = 0; i < frames; ++i) {
        SDL_Event event;
        float phase = (float)(i % 120) / 119.0f;

        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT || event.type == SDL_KEYDOWN) {
                i = frames;
                break;
            }
        }
        glClearColor(0.55f - 0.35f * phase, 0.08f, 0.18f + 0.55f * phase, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        SDL_GL_SwapWindow(window);
    }

    SDL_GL_DeleteContext(context);
    SDL_DestroyWindow(window);
    SDL_Quit();
    puts("SDL2 Mali-fbdev smoke test completed successfully");
    return 0;

fail:
    if (context != NULL) {
        SDL_GL_DeleteContext(context);
    }
    if (window != NULL) {
        SDL_DestroyWindow(window);
    }
    SDL_Quit();
    return 1;
}
