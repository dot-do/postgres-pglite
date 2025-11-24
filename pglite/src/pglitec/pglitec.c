#include <unistd.h>
#include <stdio.h>

#if defined(__EMSCRIPTEN__)
#include <emscripten/emscripten.h>
#else
#define EMSCRIPTEN_KEEPALIVE
// TODO: an include for libpglite
#endif

typedef ssize_t (*pglite_system_t)(const char *command);
pglite_system_t pglite_system = NULL;

void EMSCRIPTEN_KEEPALIVE
pgl_set_system_fn(pglite_system_t system_fn) {
    pglite_system = system_fn;
}

int EMSCRIPTEN_KEEPALIVE
pgl_system(const char *command) {
    if (pglite_system) {
        return pglite_system(command);
    }
    return 123; // should we call system???
}

typedef FILE* (*pglite_popen_t)(const char *command, const char *mode);
pglite_popen_t pglite_popen = NULL;

void EMSCRIPTEN_KEEPALIVE
pgl_set_popen_fn(pglite_popen_t popen_fn) {
    pglite_popen = popen_fn;
}

FILE* EMSCRIPTEN_KEEPALIVE
pgl_popen(const char *command, const char *mode) {
    if (pglite_popen) {
        return pglite_popen(command, mode);
    }
    return popen(command, mode);
}

typedef int (*pglite_pclose_t)(const FILE* fd);
pglite_pclose_t pglite_pclose = NULL;

void EMSCRIPTEN_KEEPALIVE
pgl_set_pclose_fn(pglite_pclose_t pclose_fn) {
    pglite_pclose = pclose_fn;
}

int EMSCRIPTEN_KEEPALIVE
pgl_pclose(FILE* fd) {
    if (pglite_pclose) {
        return pglite_pclose(fd);
    }
    return pclose(fd);
}

typedef char* (*pglite_fgets_t)(char * restrict str, int size, FILE * restrict stream);
pglite_fgets_t pglite_fgets = NULL;

void EMSCRIPTEN_KEEPALIVE
pgl_set_fgets_fn(pglite_fgets_t fgets_fn) {
    pglite_fgets = fgets_fn;
}

#define PGL_ERR_NO_ERROR    0
#define PGL_ERR_NOT_HANDLED 1
volatile EMSCRIPTEN_KEEPALIVE 
int pgl_errno = PGL_ERR_NO_ERROR;

int EMSCRIPTEN_KEEPALIVE
pgl_set_errno(int errno) {
    int curr = pgl_errno;
    pgl_errno = errno;
    return curr;
}

char* EMSCRIPTEN_KEEPALIVE
pgl_fgets(char * restrict str, int size, FILE * restrict stream) {
    if (pglite_fgets) {
        pgl_errno = PGL_ERR_NO_ERROR;
        char *ret = pglite_fgets(str, size, stream);
        if (pgl_errno == PGL_ERR_NO_ERROR) {
            return ret;
        }
    }
    return fgets(str, size, stream);
}

uid_t EMSCRIPTEN_KEEPALIVE
pgl_geteuid(void) {
    return 1234;   // your custom value
}


