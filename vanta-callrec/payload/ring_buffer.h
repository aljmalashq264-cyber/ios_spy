#ifndef VANTA_RINGBUF_H
#define VANTA_RINGBUF_H

#include <stdatomic.h>
#include <stdint.h>
#include <string.h>

typedef struct {
    uint8_t      *buf;
    size_t        size;        // يجب أن يكون قوة 2
    _Atomic size_t w;          // write index (producer)
    _Atomic size_t r;          // read index (consumer)
} vanta_rb_t;

// نسخ مع الالتفاف
static inline void rb_copy_in(uint8_t *dst, size_t dst_size, size_t pos,
                               const void *src, size_t n) {
    size_t first = dst_size - pos;
    if (n <= first) {
        memcpy(dst + pos, src, n);
    } else {
        memcpy(dst + pos, src, first);
        memcpy(dst, (const uint8_t*)src + first, n - first);
    }
}

static inline void rb_copy_out(void *dst, const uint8_t *src, size_t src_size,
                                size_t pos, size_t n) {
    size_t first = src_size - pos;
    if (n <= first) {
        memcpy(dst, src + pos, n);
    } else {
        memcpy(dst, src + pos, first);
        memcpy((uint8_t*)dst + first, src, n - first);
    }
}

static inline void rb_init(vanta_rb_t *rb, uint8_t *mem, size_t size) {
    rb->buf  = mem;
    rb->size = size;
    atomic_store_explicit(&rb->w, 0, memory_order_relaxed);
    atomic_store_explicit(&rb->r, 0, memory_order_relaxed);
}

// ═══════════════════════════════════════════════════════════
// Producer — يُنادى من خيط الوقت الحقيقي فقط
// التنسيق: [1B bus][4B len LE][N bytes data]
// ═══════════════════════════════════════════════════════════
static inline int rb_write(vanta_rb_t *rb, uint8_t bus,
                            const void *src, size_t n) {
    if (n == 0 || n > 0xFFFFFF) return -1;

    size_t w = atomic_load_explicit(&rb->w, memory_order_relaxed);
    size_t r = atomic_load_explicit(&rb->r, memory_order_acquire);
    size_t avail = rb->size - (w - r);
    size_t need = 5 + n;
    if (avail < need) return -1;   // ممتلئ — نتجاهل

    size_t pos = w & (rb->size - 1);

    uint8_t hdr[5];
    hdr[0] = bus;
    hdr[1] = (uint8_t)(n      );
    hdr[2] = (uint8_t)(n >>  8);
    hdr[3] = (uint8_t)(n >> 16);
    hdr[4] = (uint8_t)(n >> 24);
    rb_copy_in(rb->buf, rb->size, pos, hdr, 5);

    pos = (pos + 5) & (rb->size - 1);
    rb_copy_in(rb->buf, rb->size, pos, src, n);

    atomic_store_explicit(&rb->w, w + need, memory_order_release);
    return 0;
}

// ═══════════════════════════════════════════════════════════
// Consumer — يُنادى من خيط خلفي فقط
// ═══════════════════════════════════════════════════════════
static inline int rb_read(vanta_rb_t *rb, uint8_t *bus,
                           void *dst, size_t max, size_t *out_n) {
    size_t r = atomic_load_explicit(&rb->r, memory_order_relaxed);
    size_t w = atomic_load_explicit(&rb->w, memory_order_acquire);
    if (w == r) return -1;   // فارغ

    size_t pos = r & (rb->size - 1);

    uint8_t hdr[5];
    rb_copy_out(hdr, rb->buf, rb->size, pos, 5);

    *bus = hdr[0];
    size_t n = (size_t)hdr[1]
             | ((size_t)hdr[2] <<  8)
             | ((size_t)hdr[3] << 16)
             | ((size_t)hdr[4] << 24);

    if (n > max) n = max;

    pos = (pos + 5) & (rb->size - 1);
    rb_copy_out(dst, rb->buf, rb->size, pos, n);
    *out_n = n;

    atomic_store_explicit(&rb->r, r + 5 + n, memory_order_release);
    return 0;
}

#endif
