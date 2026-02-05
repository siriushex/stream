/*
 * Astra Module: MixAudio
 * http://cesbo.com/astra
 *
 * Copyright (C) 2012-2014, Andrey Dyldin <and@cesbo.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/*
 * Module Name:
 *      mixaudio
 *
 * Module Options:
 *      pid         - number, PID of the audio stream
 *      direction   - string, audio channel copying direction,
 *                    "LL" (by default) replace right channel to the left
 *                    "RR" replace left channel to the right
 */

#include <astra.h>

#include <libavcodec/avcodec.h>
#include <libavutil/error.h>
#include <libavutil/samplefmt.h>

#define MSG(_msg) "[mixaudio] " _msg

typedef enum
{
    MIXAUDIO_DIRECTION_NONE = 0,
    MIXAUDIO_DIRECTION_LL = 1,
    MIXAUDIO_DIRECTION_RR = 2,
} mixaudio_direction_t;

struct module_data_t
{
    MODULE_STREAM_DATA();

    int pid;
    mixaudio_direction_t direction;

    // ffmpeg
    AVFrame *frame;

    const AVCodec *decoder;
    AVCodecContext *ctx_decode;
    const AVCodec *encoder;
    AVCodecContext *ctx_encode;

    // PES packets
    mpegts_pes_t *pes_i; // input
    mpegts_pes_t *pes_o; // output

    // mpeg frame size
    size_t fsize;

    // splitted frame buffer
    uint8_t fbuffer[8192];
    size_t fbuffer_skip;

    int count;
    int max_count;
};

static void log_av_err(const char *what, int err)
{
    char buf[256];
    buf[0] = '\0';
    av_strerror(err, buf, sizeof(buf));
    asc_log_error(MSG("%s: %s"), what, buf[0] ? buf : "(unknown error)");
}

static void mix_frame_lr(module_data_t *mod, AVFrame *frame)
{
    if(!frame)
        return;
    if(mod->direction != MIXAUDIO_DIRECTION_LL && mod->direction != MIXAUDIO_DIRECTION_RR)
        return;
    if(frame->channels < 2)
        return;

    const enum AVSampleFormat fmt = (enum AVSampleFormat)frame->format;
    const int bps = av_get_bytes_per_sample(fmt);
    if(bps <= 0)
        return;

    const int nb_samples = frame->nb_samples;
    if(nb_samples <= 0)
        return;

    if(av_sample_fmt_is_planar(fmt))
    {
        const int plane_size = bps * nb_samples;
        if(!frame->data[0] || !frame->data[1])
            return;

        if(mod->direction == MIXAUDIO_DIRECTION_LL)
            memcpy(frame->data[1], frame->data[0], plane_size);
        else
            memcpy(frame->data[0], frame->data[1], plane_size);
        return;
    }

    // packed/interleaved samples
    if(!frame->data[0])
        return;

    // Only handle stereo packed formats in this simple mixer.
    if(frame->channels != 2)
        return;

    uint8_t *p = frame->data[0];
    const int frame_stride = 2 * bps;
    for(int i = 0; i < nb_samples; ++i)
    {
        uint8_t *l = p + (i * frame_stride);
        uint8_t *r = l + bps;
        if(mod->direction == MIXAUDIO_DIRECTION_LL)
            memcpy(r, l, bps);
        else
            memcpy(l, r, bps);
    }
}

/* callbacks */

static void pes_add_data(mpegts_pes_t *pes, const uint8_t *data, size_t size)
{
    if(!pes || !data || size == 0)
        return;

    if(pes->buffer_size >= PES_MAX_SIZE)
        return;

    if(pes->buffer_size + size > PES_MAX_SIZE)
        size = PES_MAX_SIZE - pes->buffer_size;

    memcpy(&pes->buffer[pes->buffer_size], data, size);
    pes->buffer_size += size;

    // Update PES_packet_length if it is present and fits.
    if(pes->buffer_size >= PES_HEADER_SIZE)
    {
        const uint32_t payload_len = pes->buffer_size - PES_HEADER_SIZE;
        if(payload_len <= 0xFFFF)
        {
            pes->buffer[4] = (payload_len >> 8) & 0xFF;
            pes->buffer[5] = payload_len & 0xFF;
        }
        else
        {
            // 0 means "unspecified" in PES.
            pes->buffer[4] = 0;
            pes->buffer[5] = 0;
        }
    }
}

static void pack_es(module_data_t *mod, uint8_t *data, size_t size)
{
    // hack to set PTS from source PES
    if(!mod->pes_o->buffer_size)
    {
        // copy PES header from original PES
        const size_t pes_hdr = 6 + 3 + mod->pes_i->buffer[8];
        memcpy(mod->pes_o->buffer, mod->pes_i->buffer, pes_hdr);
        mod->pes_o->buffer_size = pes_hdr;
    }

    pes_add_data(mod->pes_o, data, size);
    ++mod->count;

    if(mod->count == mod->max_count)
    {
        mpegts_pes_demux(mod->pes_o
                         , (ts_callback_t)__module_stream_send
                         , &mod->__stream);
        mod->pes_o->buffer_size = 0;
        mod->count = 0;
    }
}

static bool transcode(module_data_t *mod, const uint8_t *data)
{
    if(!mod->ctx_decode || !mod->ctx_encode || !mod->frame)
        return false;

    AVPacket pkt;
    memset(&pkt, 0, sizeof(pkt));
    pkt.data = (uint8_t *)data;
    pkt.size = (int)mod->fsize;

    int ret = avcodec_send_packet(mod->ctx_decode, &pkt);
    if(ret < 0)
    {
        log_av_err("error while sending packet to decoder", ret);
        mod->fsize = 0;
        return false;
    }

    while(1)
    {
        ret = avcodec_receive_frame(mod->ctx_decode, mod->frame);
        if(ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
            break;
        if(ret < 0)
        {
            log_av_err("error while decoding", ret);
            mod->fsize = 0;
            return false;
        }

        mix_frame_lr(mod, mod->frame);

        ret = avcodec_send_frame(mod->ctx_encode, mod->frame);
        if(ret < 0)
        {
            log_av_err("error while sending frame to encoder", ret);
            av_frame_unref(mod->frame);
            continue;
        }

        while(1)
        {
            AVPacket out_pkt;
            memset(&out_pkt, 0, sizeof(out_pkt));
            ret = avcodec_receive_packet(mod->ctx_encode, &out_pkt);
            if(ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
                break;
            if(ret < 0)
            {
                log_av_err("error while encoding", ret);
                break;
            }

            // TODO: read http://bbs.rosoo.net/thread-14926-1-1.html
            pack_es(mod, out_pkt.data, (size_t)out_pkt.size);
            av_packet_unref(&out_pkt);
        }

        av_frame_unref(mod->frame);
    }

    return true;
}

static const uint16_t mpeg_brate[6][16] =
{
/* ID/BR */
    /* R */
    { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    /* V1,L1 */
    { 0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, 0},
    /* V1,L2 */
    { 0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 0 },
    /* V1,L3 */
    { 0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0 },
    /* V2,L1 */
    { 0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, 0 },
    /* V2,L2/L3 */
    { 0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0 }
};

static const uint8_t mpeg_brate_id[4][4] =
{
/* V/L      R  3  2  1 */
/* 2.5 */ { 0, 5, 5, 4 },
/*   R */ { 0, 0, 0, 0 },
/*   2 */ { 0, 5, 5, 4 },
/*   1 */ { 0, 3, 2, 1 },
};

const uint16_t mpeg_srate[4][4] = {
/*   V/SR */
/* 2.5 */ { 11025, 12000, 8000, 0 },
/*   R */ { 0, 0, 0, 0 },
/*   2 */ { 22050, 24000, 16000, 0 },
/*   1 */ { 44100, 48000, 32000, 0 }
};

static void mux_pes(void *arg, mpegts_pes_t *pes)
{
    module_data_t *mod = arg;

    const uint8_t *ptr;
    if(PES_IS_SYNTAX_SPEC(pes))
        ptr = &pes->buffer[PES_HEADER_SIZE + 3 + pes->buffer[8]];
    else
        ptr = &pes->buffer[PES_HEADER_SIZE];

    const uint8_t *const ptr_end = pes->buffer + pes->buffer_size;
    const size_t es_size = ptr_end - ptr;

    if(!mod->fbuffer_skip)
    {
        while(ptr < ptr_end - 1)
        {
            if(ptr[0] == 0xFF && (ptr[1] & 0xF0) == 0xF0)
                break;
            ++ptr;
        }
    }

    if(!mod->fsize)
    {
        const uint8_t mpeg_v = (ptr[1] & 0x18) >> 3; // version
        const uint8_t mpeg_l = (ptr[1] & 0x06) >> 1; // layer
        // const uint8_t mpeg_c = (ptr[3] & 0xC0) >> 6; // channel mode
        const uint8_t mpeg_br = (ptr[2] & 0xF0) >> 4; // bitrate
        const uint8_t mpeg_sr = (ptr[2] & 0x0C) >> 2; // sampling rate
        const uint8_t mpeg_p = (ptr[2] & 0x02) >> 1; // padding
        const uint8_t brate_id = mpeg_brate_id[mpeg_v][mpeg_l];
        const uint16_t br = mpeg_brate[brate_id][mpeg_br];
        const uint16_t sr = mpeg_srate[mpeg_v][mpeg_sr];
        mod->fsize = (144 * br * 1000) / (sr + mpeg_p);

        asc_log_debug(MSG("set frame size = %lu"), mod->fsize);

        if(!(es_size % mod->fsize))
            mod->max_count = es_size / mod->fsize;
        else
            mod->max_count = 8;

        if(!mod->decoder)
        {
            enum AVCodecID codec_id = AV_CODEC_ID_NONE;
            switch(mpeg_v)
            {
                case 0:
                case 2:
                    codec_id = AV_CODEC_ID_MP2;
                    break;
                case 3:
                    codec_id = AV_CODEC_ID_MP1;
                    break;
                default:
                    break;
            }

            int is_err = 1;
            do
            {
                mod->decoder = avcodec_find_decoder(codec_id);
                if(!mod->decoder)
                {
                    asc_log_error(MSG("mpeg audio decoder is not found"));
                    break;
                }

                mod->ctx_decode = avcodec_alloc_context3(mod->decoder);
                if(avcodec_open2(mod->ctx_decode, mod->decoder, NULL) < 0)
                {
                    mod->decoder = NULL;
                    asc_log_error(MSG("failed to open audio decoder"));
                    break;
                }

                is_err = 0;
            } while(0);

            if(is_err)
            {
                mod->direction = MIXAUDIO_DIRECTION_NONE;
                return;
            }
        }
    }

    if(mod->fbuffer_skip)
    {
        const size_t rlen = mod->fsize - mod->fbuffer_skip;
        memcpy(&mod->fbuffer[mod->fbuffer_skip], ptr, rlen);
        mod->fbuffer_skip = 0;
        if(!transcode(mod, mod->fbuffer))
            return;
        ptr += rlen;
    }

    while(1)
    {
        const uint8_t *const nptr = ptr + mod->fsize;
        if(nptr < ptr_end)
        {
            if(!transcode(mod, ptr))
                break;
            ptr = nptr;
        }
        else if(nptr == ptr_end)
        {
            transcode(mod, ptr);
            break;
        }
        else /* nptr > ptr_end */
        {
            mod->fbuffer_skip = ptr_end - ptr;
            memcpy(mod->fbuffer, ptr, mod->fbuffer_skip);
            break;
        }
    }
}

static void on_ts(module_data_t *mod, const uint8_t *ts)
{
    if(mod->direction == MIXAUDIO_DIRECTION_NONE)
    {
        module_stream_send(mod, ts);
        return;
    }

    const uint16_t pid = TS_GET_PID(ts);
    if(pid == mod->pid)
        mpegts_pes_mux(mod->pes_i, ts, mux_pes, mod);
    else
        module_stream_send(mod, ts);
}

/* required */

static void ffmpeg_log_callback(void *ptr, int level, const char *fmt, va_list vl)
{
    __uarg(ptr);
    void (*log_callback)(const char *, ...);

    switch(level)
    {
        case AV_LOG_INFO:
            log_callback = asc_log_info;
            break;
        case AV_LOG_WARNING:
            log_callback = asc_log_warning;
            break;
        case AV_LOG_DEBUG:
            log_callback = asc_log_debug;
            break;
        default:
            log_callback = asc_log_error;
            break;
    }

    char buffer[1024];
    const size_t len = vsnprintf(buffer, sizeof(buffer), fmt, vl);
    buffer[len - 1] = '\0';

    log_callback(MSG("%s"), buffer);
}

static void module_init(module_data_t *mod)
{
    module_stream_init(mod, on_ts);

    if(!module_option_number("pid", &mod->pid) || mod->pid <= 0)
    {
        asc_log_error(MSG("option 'pid' is required"));
        astra_abort();
    }
    const char *direction = NULL;
    if(!module_option_string("direction", &direction, NULL))
        direction = "LL";

    if(!strcasecmp(direction, "LL"))
        mod->direction = MIXAUDIO_DIRECTION_LL;
    else if(!strcasecmp(direction, "RR"))
        mod->direction = MIXAUDIO_DIRECTION_RR;

    av_log_set_callback(ffmpeg_log_callback);

    do
    {
        mod->encoder = avcodec_find_encoder(AV_CODEC_ID_MP2);
        if(!mod->encoder)
        {
            asc_log_error(MSG("mp2 encoder is not found"));
            astra_abort();
        }
        mod->ctx_encode = avcodec_alloc_context3(mod->encoder);
        mod->ctx_encode->bit_rate = 192000;
        mod->ctx_encode->sample_rate = 48000;
        mod->ctx_encode->channels = 2;
        mod->ctx_encode->sample_fmt = AV_SAMPLE_FMT_S16;
        mod->ctx_encode->channel_layout = AV_CH_LAYOUT_STEREO;
        mod->ctx_encode->time_base = (AVRational){ .num = 1, .den = mod->ctx_encode->sample_rate };
        if(avcodec_open2(mod->ctx_encode, mod->encoder, NULL) < 0)
        {
            asc_log_error(MSG("failed to open mp2 encoder"));
            astra_abort();
        }

        mod->frame = av_frame_alloc();
        if(!mod->frame)
        {
            asc_log_error(MSG("failed to allocate AVFrame"));
            astra_abort();
        }

        mod->pes_i = mpegts_pes_init(MPEGTS_PACKET_AUDIO, mod->pid, 0);
        mod->pes_o = mpegts_pes_init(MPEGTS_PACKET_AUDIO, mod->pid, 0);
    } while(0);
}

static void module_destroy(module_data_t *mod)
{
    module_stream_destroy(mod);

    if(mod->ctx_encode)
        avcodec_free_context(&mod->ctx_encode);
    if(mod->ctx_decode)
        avcodec_free_context(&mod->ctx_decode);
    if(mod->frame)
        av_frame_free(&mod->frame);

    if(mod->pes_i)
        mpegts_pes_destroy(mod->pes_i);
    if(mod->pes_o)
        mpegts_pes_destroy(mod->pes_o);
}

MODULE_STREAM_METHODS()

MODULE_LUA_METHODS()
{
    MODULE_STREAM_METHODS_REF()
};

MODULE_LUA_REGISTER(mixaudio)
