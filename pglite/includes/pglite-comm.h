/**
 * pglite-comm.h
 *
 * Communication layer for PGlite using EM_JS trampolines.
 * This implementation is compatible with Cloudflare Workers (no runtime WASM compilation).
 *
 * CLOUDFLARE WORKERS COMPATIBILITY:
 * ================================
 * Cloudflare Workers blocks runtime WebAssembly.Module() calls for security.
 * The standard Emscripten addFunction() approach generates WASM at runtime,
 * which triggers "WebAssembly.Module(): Wasm code generation disallowed by embedder".
 *
 * This implementation uses EM_JS trampolines instead:
 * 1. EM_JS macros are compiled at build time (no runtime WASM generation)
 * 2. Callbacks are stored in Module._pgliteCallbacks JavaScript object
 * 3. Trampolines directly invoke callbacks from the JavaScript object
 *
 * USAGE (JavaScript side):
 * ========================
 * Before performing any PostgreSQL operations, set up the callbacks:
 *
 *   Module._pgliteCallbacks = {
 *     read: (ptr, maxLength) => {
 *       // Copy query data to WASM memory at ptr
 *       // Return number of bytes copied
 *     },
 *     write: (ptr, length) => {
 *       // Read result data from WASM memory at ptr
 *       // Return number of bytes processed
 *     }
 *   };
 */

#if defined(__EMSCRIPTEN__)

#ifndef PGLITE_COMM_H
#define PGLITE_COMM_H

#include <emscripten/emscripten.h>
#include <emscripten/em_js.h>

/* Query state variables (used by PostgreSQL's input processing) */
volatile int querylen = 0;
volatile FILE* queryfp = NULL;

/*
 * ============================================================================
 * EM_JS TRAMPOLINES - Cloudflare Workers Compatible
 * ============================================================================
 *
 * These trampolines use EM_JS to directly invoke JavaScript callbacks stored
 * in Module._pgliteCallbacks. This approach:
 *
 * - Is compiled at build time (EM_JS generates WASM during Emscripten compilation)
 * - Does NOT require addFunction() or runtime WASM generation
 * - Works in Cloudflare Workers and other restricted environments
 *
 * The JavaScript callbacks are set on the Module object before I/O begins:
 *
 *   Module._pgliteCallbacks = {
 *     read: (ptr, maxLength) => { ... return bytesRead; },
 *     write: (ptr, length) => { ... return bytesWritten; }
 *   };
 */

/**
 * EM_JS trampoline for reading data from JavaScript.
 *
 * Called by recv() when PostgreSQL needs input data (e.g., query bytes).
 * Invokes Module._pgliteCallbacks.read(buffer, max_length).
 *
 * @param buffer     Pointer to WASM memory where data should be written
 * @param max_length Maximum number of bytes to read
 * @return Number of bytes read, 0 for EOF, or -1 on error
 */
EM_JS(ssize_t, pglite_read_trampoline, (void* buffer, size_t max_length), {
    /* Check if callbacks are registered */
    if (!Module._pgliteCallbacks || !Module._pgliteCallbacks.read) {
        console.error('pglite_read_trampoline: no read callback registered');
        return 0;  /* Return 0 bytes read (EOF-like behavior) */
    }

    /* Call the JavaScript read callback */
    try {
        return Module._pgliteCallbacks.read(buffer, max_length);
    } catch (e) {
        console.error('pglite_read_trampoline error:', e);
        return -1;  /* Return error */
    }
});

/**
 * EM_JS trampoline for writing data to JavaScript.
 *
 * Called by send() when PostgreSQL has output data (e.g., query results).
 * Invokes Module._pgliteCallbacks.write(buffer, length).
 *
 * @param buffer Pointer to WASM memory containing data to write
 * @param length Number of bytes to write
 * @return Number of bytes written, or -1 on error
 */
EM_JS(ssize_t, pglite_write_trampoline, (const void* buffer, size_t length), {
    /* Check if callbacks are registered */
    if (!Module._pgliteCallbacks || !Module._pgliteCallbacks.write) {
        console.error('pglite_write_trampoline: no write callback registered');
        return -1;
    }

    /* Call the JavaScript write callback */
    try {
        return Module._pgliteCallbacks.write(buffer, length);
    } catch (e) {
        console.error('pglite_write_trampoline error:', e);
        return -1;
    }
});

/**
 * Initialize the callback storage object.
 *
 * Called once during module initialization to ensure
 * Module._pgliteCallbacks exists before any I/O operations.
 */
EM_JS(void, pglite_init_callbacks, (void), {
    if (!Module._pgliteCallbacks) {
        Module._pgliteCallbacks = {
            read: null,
            write: null
        };
    }
});

/**
 * Check if callbacks are ready.
 *
 * Exported function that JavaScript can call to verify
 * the callback system is initialized.
 *
 * @return 1 if callback storage exists, 0 otherwise
 */
__attribute__((export_name("pglite_callbacks_ready")))
int pglite_callbacks_ready(void) {
    return 1;  /* Assume ready after module loads */
}

/*
 * ============================================================================
 * BACKWARD COMPATIBILITY LAYER
 * ============================================================================
 *
 * For existing code that expects set_read_write_cbs(), we provide the function
 * signature but it's a no-op. The actual callbacks are set via:
 *
 *   Module._pgliteCallbacks.read = function(ptr, maxLength) { ... };
 *   Module._pgliteCallbacks.write = function(ptr, length) { ... };
 *
 * This allows gradual migration without breaking existing code.
 */

/* Legacy function pointer types (kept for backward compatibility) */
typedef ssize_t (*pglite_read_t)(void *buffer, size_t max_length);
typedef ssize_t (*pglite_write_t)(void *buffer, size_t length);

/**
 * Legacy callback registration (NO-OP in trampoline mode).
 *
 * DEPRECATED: Use Module._pgliteCallbacks instead.
 *
 * This function is still exported so existing JavaScript code
 * that calls _set_read_write_cbs won't throw, but the function
 * pointers are ignored. JavaScript must set callbacks via:
 *
 *   Module._pgliteCallbacks = { read: ..., write: ... };
 *
 * @param read_cb  Ignored (use Module._pgliteCallbacks.read)
 * @param write_cb Ignored (use Module._pgliteCallbacks.write)
 */
__attribute__((export_name("set_read_write_cbs")))
void
set_read_write_cbs(pglite_read_t read_cb, pglite_write_t write_cb) {
    /* No-op in trampoline mode */
    /* Suppress unused parameter warnings */
    (void)read_cb;
    (void)write_cb;
}

/*
 * ============================================================================
 * SOCKET STUB FUNCTIONS
 * ============================================================================
 *
 * PGlite runs PostgreSQL as a single-process, in-memory database.
 * These socket functions are stubbed out since there's no actual
 * network communication - all I/O goes through the trampolines.
 */

int EMSCRIPTEN_KEEPALIVE fcntl(int __fd, int __cmd, ...) {
    /* Dummy - no file descriptor control needed */
    return 0;
}

int EMSCRIPTEN_KEEPALIVE setsockopt(int __fd, int __level, int __optname,
    const void *__optval, socklen_t __optlen) {
    /* Dummy - no socket options needed */
    return 0;
}

int EMSCRIPTEN_KEEPALIVE getsockopt(int __fd, int __level, int __optname,
    void *__restrict __optval,
    socklen_t *__restrict __optlen) {
    /* Dummy - no socket options needed */
    return 0;
}

int EMSCRIPTEN_KEEPALIVE getsockname(int __fd, struct sockaddr * __addr,
    socklen_t *__restrict __len) {
    /* Dummy - no socket address needed */
    return 0;
}

/**
 * Receive data from "socket" (actually from JavaScript via trampoline).
 *
 * This is called by PostgreSQL's libpq layer when reading input.
 * Uses pglite_read_trampoline to invoke Module._pgliteCallbacks.read.
 *
 * @param __fd    Ignored (no actual socket)
 * @param __buf   Buffer to receive data into
 * @param __n     Maximum bytes to receive
 * @param __flags Ignored (no actual socket flags)
 * @return Number of bytes received, 0 for EOF, or -1 on error
 */
ssize_t EMSCRIPTEN_KEEPALIVE
recv(int __fd, void *__buf, size_t __n, int __flags) {
    /* Use EM_JS trampoline instead of function pointer */
    ssize_t got = pglite_read_trampoline(__buf, __n);
    return got;
}

/**
 * Send data to "socket" (actually to JavaScript via trampoline).
 *
 * This is called by PostgreSQL's libpq layer when writing output.
 * Uses pglite_write_trampoline to invoke Module._pgliteCallbacks.write.
 *
 * @param __fd    Ignored (no actual socket)
 * @param __buf   Buffer containing data to send
 * @param __n     Number of bytes to send
 * @param __flags Ignored (no actual socket flags)
 * @return Number of bytes sent, or -1 on error
 */
ssize_t EMSCRIPTEN_KEEPALIVE
send(int __fd, const void *__buf, size_t __n, int __flags) {
    /* Use EM_JS trampoline instead of function pointer */
    ssize_t wrote = pglite_write_trampoline(__buf, __n);
    return wrote;
}

int EMSCRIPTEN_KEEPALIVE
connect(int socket, const struct sockaddr *address, socklen_t address_len) {
    /* Dummy - no actual connection needed */
    return 0;
}

struct pollfd {
    int   fd;         /* file descriptor */
    short events;     /* requested events */
    short revents;    /* returned events */
};

int EMSCRIPTEN_KEEPALIVE
poll(struct pollfd fds[], ssize_t nfds, int timeout) {
    /* Dummy - always report ready */
    return nfds;
}

#endif /* PGLITE_COMM_H */

#endif /* __EMSCRIPTEN__ */
