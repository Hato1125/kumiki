// Wuffs is one C file that is its own header. Only the decoders that
// `kumiki_decode_image` hands out are compiled.
#define WUFFS_IMPLEMENTATION
#define WUFFS_CONFIG__STATIC_FUNCTIONS
#define WUFFS_CONFIG__MODULES
#define WUFFS_CONFIG__MODULE__BASE
#define WUFFS_CONFIG__MODULE__ADLER32
#define WUFFS_CONFIG__MODULE__CRC32
#define WUFFS_CONFIG__MODULE__DEFLATE
#define WUFFS_CONFIG__MODULE__ZLIB
#define WUFFS_CONFIG__MODULE__PNG
#define WUFFS_CONFIG__MODULE__JPEG
#define WUFFS_CONFIG__MODULE__VP8
#define WUFFS_CONFIG__MODULE__WEBP
#include "wuffs-v0.4.c"

#include <stdint.h>
#include <stdlib.h>

// Decodes the PNG, JPG or WebP file in `data`. Returns rows from the top
// down, four bytes a pixel: red, green, blue and alpha, with the colors not
// multiplied by the alpha. The caller frees the result. NULL for a file of
// another kind, one that is broken, and the kinds of WebP that Wuffs does
// not decode yet: animated ones and lossy ones with transparency.
uint8_t *kumiki_decode_image(
    const uint8_t *data,
    size_t length,
    uint32_t *width,
    uint32_t *height
) {
    wuffs_base__image_decoder *decoder = NULL;
    wuffs_base__slice_u8 file = wuffs_base__make_slice_u8(
        (uint8_t *)data,
        length
    );
    switch (wuffs_base__magic_number_guess_fourcc(file, true)) {
    case WUFFS_BASE__FOURCC__PNG:
        decoder = wuffs_png__decoder__alloc_as__wuffs_base__image_decoder();
        break;
    case WUFFS_BASE__FOURCC__JPEG:
        decoder = wuffs_jpeg__decoder__alloc_as__wuffs_base__image_decoder();
        break;
    case WUFFS_BASE__FOURCC__WEBP:
        decoder = wuffs_webp__decoder__alloc_as__wuffs_base__image_decoder();
        break;
    }
    if (!decoder) return NULL;

    uint8_t *pixels = NULL;
    uint8_t *work = NULL;

    wuffs_base__io_buffer source = wuffs_base__ptr_u8__reader(
        (uint8_t *)data,
        length,
        true
    );
    wuffs_base__image_config config;
    wuffs_base__status status = wuffs_base__image_decoder__decode_image_config(
        decoder,
        &config,
        &source
    );
    if (!wuffs_base__status__is_ok(&status)) goto fail;

    uint32_t wide = wuffs_base__pixel_config__width(&config.pixcfg);
    uint32_t high = wuffs_base__pixel_config__height(&config.pixcfg);

    if (wide == 0 || high == 0) goto fail;

    wuffs_base__pixel_config__set(
        &config.pixcfg,
        WUFFS_BASE__PIXEL_FORMAT__RGBA_NONPREMUL,
        WUFFS_BASE__PIXEL_SUBSAMPLING__NONE,
        wide,
        high
    );

    // Wuffs allocates nothing itself: it says how much scratch memory the
    // file needs and is handed it.
    size_t pixels_length = (size_t)wide * high * 4;
    size_t work_length = (size_t)wuffs_base__image_decoder__workbuf_len(decoder).max_incl;

    pixels = malloc(pixels_length);
    work = malloc(work_length ? work_length : 1);

    if (!pixels || !work) goto fail;

    wuffs_base__pixel_buffer buffer;
    status = wuffs_base__pixel_buffer__set_from_slice(
        &buffer,
        &config.pixcfg,
        wuffs_base__make_slice_u8(pixels, pixels_length)
    );
    if (!wuffs_base__status__is_ok(&status)) goto fail;

    status = wuffs_base__image_decoder__decode_frame(
        decoder,
        &buffer,
        &source,
        WUFFS_BASE__PIXEL_BLEND__SRC,
        wuffs_base__make_slice_u8(work, work_length),
        NULL
    );
    if (!wuffs_base__status__is_ok(&status)) goto fail;

    free(work);
    free(decoder);
    *width = wide;
    *height = high;

    return pixels;

fail:
    free(work);
    free(pixels);
    free(decoder);
    return NULL;
}
