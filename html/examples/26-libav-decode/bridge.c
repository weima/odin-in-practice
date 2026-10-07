/* Original Linux/FFmpeg 6 companion, informed by the documented send/receive
 * contract and remuxing example. This is a local-file worker, not a sandbox. */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/error.h>
#include <libavutil/mem.h>
#include <libavutil/time.h>
#if LIBAVFORMAT_VERSION_MAJOR != 60 || LIBAVCODEC_VERSION_MAJOR != 60 || LIBAVUTIL_VERSION_MAJOR != 58
#error "This companion requires FFmpeg 6 development headers; adapt and revalidate other majors."
#endif

typedef struct {
    int64_t packets, frames, audio_samples;
    int32_t streams;
} BookReport;
_Static_assert(sizeof(BookReport) == 32, "Odin-facing report ABI changed");
typedef struct { int64_t until; } Deadline;
static int expired(void *opaque) {
    return av_gettime_relative() >= ((Deadline *)opaque)->until;
}
int book_abi_ok(void) {
    return (avformat_version() >> 16) == LIBAVFORMAT_VERSION_MAJOR &&
           (avcodec_version() >> 16) == LIBAVCODEC_VERSION_MAJOR &&
           (avutil_version() >> 16) == LIBAVUTIL_VERSION_MAJOR;
}
int book_error(int status, char *buffer, uint64_t length) {
    return av_strerror(status, buffer, (size_t)length);
}
static int open_input(const char *path, AVFormatContext **input, Deadline *deadline) {
    struct stat st;
    if (!path || path[0] != '/' || lstat(path, &st) < 0 || !S_ISREG(st.st_mode))
        return AVERROR(EINVAL);
    *input = avformat_alloc_context();
    if (!*input) return AVERROR(ENOMEM);
    (*input)->interrupt_callback = (AVIOInterruptCB){expired, deadline};
    (*input)->probesize = 1024 * 1024;
    (*input)->max_analyze_duration = 2 * AV_TIME_BASE;
    AVDictionary *options = NULL;
    int ret = av_dict_set(&options, "protocol_whitelist", "file", 0);
    if (ret >= 0) ret = av_dict_set(&options, "max_streams", "64", 0);
    if (ret >= 0) ret = avformat_open_input(input, path, NULL, &options);
    if (ret >= 0 && av_dict_count(options) != 0) ret = AVERROR_OPTION_NOT_FOUND;
    av_dict_free(&options);
    if (ret < 0) return ret;
    ret = avformat_find_stream_info(*input, NULL);
    if (ret < 0) return ret;
    return (*input)->nb_streams <= 64 ? 0 : AVERROR(EFBIG);
}
static int drain(AVCodecContext *decoder, AVFrame *frame, BookReport *report,
                 int64_t max_frames, Deadline *deadline) {
    for (;;) {
        if (expired(deadline)) return AVERROR_EXIT;
        int ret = avcodec_receive_frame(decoder, frame);
        if (ret < 0) return ret;
        if (report->frames >= max_frames) { av_frame_unref(frame); return AVERROR(EFBIG); }
        ++report->frames;
        report->audio_samples += frame->nb_samples;
        /* Process borrowed frame data HERE, or retain a frame reference before
         * handing it off. This worker only counts frames and audio samples. */
        av_frame_unref(frame);
    }
}
static int submit(AVCodecContext *decoder, const AVPacket *packet, AVFrame *frame,
                  BookReport *report, int64_t max_frames, Deadline *deadline) {
    int ret = avcodec_send_packet(decoder, packet);
    if (ret == AVERROR(EAGAIN)) {
        int64_t before = report->frames;
        ret = drain(decoder, frame, report, max_frames, deadline);
        if (ret != AVERROR(EAGAIN) || report->frames == before)
            return ret == AVERROR(EAGAIN) ? AVERROR_BUG : ret;
        /* Same packet (or the same NULL drain marker): it was not accepted. */
        ret = avcodec_send_packet(decoder, packet);
        if (ret == AVERROR(EAGAIN)) return AVERROR_BUG;
    }
    if (ret < 0) return ret;
    ret = drain(decoder, frame, report, max_frames, deadline);
    if (packet) return ret == AVERROR(EAGAIN) ? 0 : ret;
    /* After an accepted NULL marker, normal input is over. */
    return ret == AVERROR_EOF ? 0 : (ret == AVERROR(EAGAIN) ? AVERROR_BUG : ret);
}
int book_decode(const char *path, int64_t max_frames, int64_t milliseconds, BookReport *report) {
    if (!report || max_frames < 1 || max_frames > 1000000 || milliseconds < 1 || milliseconds > 60000)
        return AVERROR(EINVAL);
    *report = (BookReport){0};
    Deadline deadline = {av_gettime_relative() + milliseconds * 1000};
    AVFormatContext *input = NULL;
    AVCodecContext *decoders[64] = {0};
    AVPacket *packet = NULL;
    AVFrame *frame = NULL;
    int ret = open_input(path, &input, &deadline);
    if (ret < 0) goto cleanup;
    for (unsigned i = 0; i < input->nb_streams; ++i) {
        AVCodecParameters *parameters = input->streams[i]->codecpar;
        if (parameters->codec_type != AVMEDIA_TYPE_AUDIO && parameters->codec_type != AVMEDIA_TYPE_VIDEO)
            continue;
        const AVCodec *codec = avcodec_find_decoder(parameters->codec_id);
        if (!codec) { ret = AVERROR_DECODER_NOT_FOUND; goto cleanup; }
        decoders[i] = avcodec_alloc_context3(codec);
        if (!decoders[i]) { ret = AVERROR(ENOMEM); goto cleanup; }
        ret = avcodec_parameters_to_context(decoders[i], parameters);
        if (ret < 0) goto cleanup;
        decoders[i]->thread_count = 1;
        decoders[i]->max_pixels = 16 * 1024 * 1024;
        decoders[i]->err_recognition = AV_EF_EXPLODE;
        ret = avcodec_open2(decoders[i], codec, NULL);
        if (ret < 0) goto cleanup;
        ++report->streams;
    }
    if (!report->streams) { ret = AVERROR_STREAM_NOT_FOUND; goto cleanup; }
    packet = av_packet_alloc();
    frame = av_frame_alloc();
    if (!packet || !frame) { ret = AVERROR(ENOMEM); goto cleanup; }
    for (;;) {
        if (expired(&deadline)) { ret = AVERROR_EXIT; goto cleanup; }
        ret = av_read_frame(input, packet);
        if (ret == AVERROR_EOF) break;
        if (ret < 0) goto cleanup;
        if (++report->packets > 100000) { ret = AVERROR(EFBIG); goto cleanup; }
        if (packet->stream_index < 0 || (unsigned)packet->stream_index >= input->nb_streams) {
            ret = AVERROR_INVALIDDATA; goto cleanup;
        }
        AVCodecContext *decoder = decoders[packet->stream_index];
        if (decoder) ret = submit(decoder, packet, frame, report, max_frames, &deadline);
        av_packet_unref(packet);
        if (ret < 0) goto cleanup;
    }
    for (unsigned i = 0; i < input->nb_streams; ++i) {
        if (!decoders[i]) continue;
        ret = submit(decoders[i], NULL, frame, report, max_frames, &deadline);
        if (ret < 0) goto cleanup;
    }
    ret = 0;
cleanup:
    av_frame_free(&frame);
    av_packet_free(&packet);
    for (unsigned i = 0; i < 64; ++i) avcodec_free_context(&decoders[i]);
    avformat_close_input(&input);
    return ret;
}

typedef struct { int fd; int64_t written, max_bytes; Deadline *deadline; } Output;
static int write_output(void *opaque, uint8_t *buffer, int length) {
    Output *out = opaque;
    off_t position = lseek(out->fd, 0, SEEK_CUR);
    if (position < 0) return AVERROR(errno);
    if (length < 0 || out->written > out->max_bytes - length ||
        position > out->max_bytes - length) return AVERROR(EFBIG);
    int total = 0;
    while (total < length) {
        if (expired(out->deadline)) return AVERROR_EXIT;
        ssize_t n = write(out->fd, buffer + total, (size_t)(length - total));
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return AVERROR(n < 0 ? errno : EIO);
        total += (int)n;
        out->written += n;
    }
    return length;
}
static int64_t seek_output(void *opaque, int64_t offset, int whence) {
    Output *out = opaque;
    if (whence == AVSEEK_SIZE) {
        struct stat st;
        return fstat(out->fd, &st) == 0 ? st.st_size : AVERROR(errno);
    }
    if (offset > out->max_bytes || offset < -out->max_bytes) return AVERROR(EFBIG);
    int origin = whence & ~AVSEEK_FORCE;
    int64_t base = 0;
    if (origin == SEEK_CUR) {
        base = lseek(out->fd, 0, SEEK_CUR);
        if (base < 0) return AVERROR(errno);
    } else if (origin == SEEK_END) {
        struct stat st;
        if (fstat(out->fd, &st) < 0) return AVERROR(errno);
        base = st.st_size;
    } else if (origin != SEEK_SET) return AVERROR(EINVAL);
    if (base < 0 || base > out->max_bytes || base + offset < 0 || base + offset > out->max_bytes)
        return AVERROR(EFBIG);
    off_t result = lseek(out->fd, (off_t)(base + offset), SEEK_SET);
    return result >= 0 ? (int64_t)result : AVERROR(errno);
}
int book_remux(const char *path, const char *destination, int64_t max_bytes,
               int64_t milliseconds, BookReport *report) {
    if (!report || !destination || destination[0] != '/' || max_bytes < 1 ||
        max_bytes > 1024LL * 1024 * 1024 || milliseconds < 1 || milliseconds > 60000)
        return AVERROR(EINVAL);
    *report = (BookReport){0};
    Deadline deadline = {av_gettime_relative() + milliseconds * 1000};
    AVFormatContext *input = NULL, *output = NULL;
    AVIOContext *io = NULL;
    AVPacket *packet = NULL;
    int mapping[64];
    for (unsigned i = 0; i < 64; ++i) mapping[i] = -1;
    Output sink = {-1, 0, max_bytes, &deadline};
    int ret = open_input(path, &input, &deadline);
    if (ret < 0) goto cleanup;
    ret = avformat_alloc_output_context2(&output, NULL, "matroska", destination);
    if (ret < 0 || !output) { if (ret >= 0) ret = AVERROR(ENOMEM); goto cleanup; }
    output->interrupt_callback = (AVIOInterruptCB){expired, &deadline};
    for (unsigned i = 0; i < input->nb_streams; ++i) {
        AVCodecParameters *parameters = input->streams[i]->codecpar;
        if (parameters->codec_type != AVMEDIA_TYPE_AUDIO && parameters->codec_type != AVMEDIA_TYPE_VIDEO &&
            parameters->codec_type != AVMEDIA_TYPE_SUBTITLE) continue;
        AVStream *stream = avformat_new_stream(output, NULL);
        if (!stream) { ret = AVERROR(ENOMEM); goto cleanup; }
        mapping[i] = stream->index;
        ret = avcodec_parameters_copy(stream->codecpar, parameters);
        if (ret < 0) goto cleanup;
        stream->codecpar->codec_tag = 0;
        stream->time_base = input->streams[i]->time_base;
        ++report->streams;
    }
    if (!report->streams) { ret = AVERROR_STREAM_NOT_FOUND; goto cleanup; }
    /* Never overwrite an existing path; job-owned staging directory required. */
    sink.fd = open(destination, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (sink.fd < 0) { ret = AVERROR(errno); goto cleanup; }
    uint8_t *buffer = av_malloc(32768);
    if (!buffer) { ret = AVERROR(ENOMEM); goto cleanup; }
    io = avio_alloc_context(buffer, 32768, 1, &sink, NULL, write_output, seek_output);
    if (!io) { av_free(buffer); ret = AVERROR(ENOMEM); goto cleanup; }
    output->pb = io;
    output->flags |= AVFMT_FLAG_CUSTOM_IO;
    ret = avformat_write_header(output, NULL);
    if (ret < 0) goto cleanup;
    packet = av_packet_alloc();
    if (!packet) { ret = AVERROR(ENOMEM); goto cleanup; }
    int64_t read_packets = 0;
    for (;;) {
        if (expired(&deadline)) { ret = AVERROR_EXIT; goto cleanup; }
        ret = av_read_frame(input, packet);
        if (ret == AVERROR_EOF) break;
        if (ret < 0) goto cleanup;
        if (++read_packets > 100000) { ret = AVERROR(EFBIG); goto cleanup; }
        int index = packet->stream_index;
        if (index < 0 || (unsigned)index >= input->nb_streams) { ret = AVERROR_INVALIDDATA; goto cleanup; }
        if (mapping[index] < 0) { av_packet_unref(packet); continue; }
        AVStream *source = input->streams[index], *target = output->streams[mapping[index]];
        av_packet_rescale_ts(packet, source->time_base, target->time_base);
        packet->stream_index = mapping[index];
        packet->pos = -1;
        ret = av_interleaved_write_frame(output, packet);
        av_packet_unref(packet); /* Safe even when the writer already consumed it. */
        if (ret < 0) goto cleanup;
        ++report->packets;
    }
    ret = av_write_trailer(output);
    if (ret < 0) goto cleanup;
    avio_flush(io);
    if (io->error < 0) { ret = io->error; goto cleanup; }
    if (fsync(sink.fd) < 0) { ret = AVERROR(errno); goto cleanup; }
    ret = 0;
cleanup:
    av_packet_free(&packet);
    avformat_free_context(output);
    if (io) { av_freep(&io->buffer); avio_context_free(&io); }
    if (sink.fd >= 0 && close(sink.fd) < 0 && ret >= 0) ret = AVERROR(errno);
    avformat_close_input(&input);
    /* Failed staging output remains explicitly incomplete; never publish it. */
    return ret;
}
