#include <dlfcn.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    static const char *symbols[] = {
        "retro_init", "retro_deinit", "retro_load_game", "retro_run"
    };
    void *handle;
    unsigned int i;

    if (argc != 2) {
        fprintf(stderr, "usage: %s CORE.so\n", argv[0]);
        return 2;
    }
    handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        fprintf(stderr, "core dlopen failed: %s\n", dlerror());
        return 1;
    }
    for (i = 0; i < sizeof(symbols) / sizeof(symbols[0]); ++i) {
        if (dlsym(handle, symbols[i]) == NULL) {
            fprintf(stderr, "core symbol missing: %s\n", symbols[i]);
            dlclose(handle);
            return 1;
        }
    }
    dlclose(handle);
    return 0;
}
