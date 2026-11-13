#import "FFmpegVideoDecoder.h"
#if defined(ENABLE_SOFTWARE_VIDEO_DECODER) && ENABLE_SOFTWARE_VIDEO_DECODER
#import <libavformat/avformat.h>
#import <libavcodec/avcodec.h>
#import <libavutil/imgutils.h>
#import <libavutil/pixdesc.h>
#import <libswscale/swscale.h>
#import "FFmpegYUVConversion.h"

static NSString * const DecoderErrorDomain = @"SoftwareVideoDecoder";

static NSError *DecoderError(int code, NSString *operation) {
    char description[AV_ERROR_MAX_STRING_SIZE] = {0};
    av_strerror(code, description, sizeof(description));
    return [NSError errorWithDomain:DecoderErrorDomain code:code userInfo:@{
        NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@: %s", operation, description]
    }];
}

@interface FFmpegDecodedFrame ()
- (instancetype)initWithBuffer:(CVPixelBufferRef)buffer presentationTime:(CMTime)time;
@end

@implementation FFmpegDecodedFrame {
    CVPixelBufferRef _pixelBuffer;
}
- (instancetype)initWithBuffer:(CVPixelBufferRef)buffer presentationTime:(CMTime)time {
    if ((self = [super init])) {
        _pixelBuffer = CVPixelBufferRetain(buffer);
        _presentationTime = time;
    }
    return self;
}
- (CVPixelBufferRef)pixelBuffer { return _pixelBuffer; }
- (void)dealloc { if (_pixelBuffer) CVPixelBufferRelease(_pixelBuffer); }
@end

@implementation FFmpegVideoDecoder {
    AVFormatContext *_format;
    AVCodecContext *_codec;
    AVPacket *_packet;
    AVFrame *_frame;
    AVFrame *_lastSeekFrame;
    struct SwsContext *_scaler;
    struct SwsContext *_chromaScaler;
    AVFrame *_yuv444;
    int _videoIndex;
    OSType _pixelFormat;
    BOOL _demuxEOF;
    BOOL _flushSent;
    int64_t _seekTarget;
    NSError *_lastError;
    NSURL *_securityURL;
    BOOL _accessingSecurityScope;
}

- (nullable instancetype)initWithURL:(NSURL *)url pixelFormat:(OSType)pixelFormat error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    _videoIndex = -1;
    _seekTarget = AV_NOPTS_VALUE;
    _pixelFormat = pixelFormat;
    if (!url.isFileURL || (pixelFormat != kCVPixelFormatType_32BGRA && pixelFormat != kCVPixelFormatType_64RGBAHalf)) {
        if (error) *error = DecoderError(AVERROR(EINVAL), @"Unsupported software decoder input or pixel format");
        return nil;
    }
    _securityURL = url;
    _accessingSecurityScope = [url startAccessingSecurityScopedResource];
    AVDictionary *options = NULL;
    av_dict_set(&options, "protocol_whitelist", "file", 0);
    int result = avformat_open_input(&_format, url.fileSystemRepresentation, av_find_input_format("mov"), &options);
    av_dict_free(&options);
    if (result < 0) {
        if (error) *error = DecoderError(result, @"Could not open the local video");
        return nil;
    }
    result = avformat_find_stream_info(_format, NULL);
    if (result < 0) {
        if (error) *error = DecoderError(result, @"Could not read the video stream");
        return nil;
    }
    _videoIndex = av_find_best_stream(_format, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    if (_videoIndex < 0) {
        if (error) *error = DecoderError(_videoIndex, @"The file contains no decodable video");
        return nil;
    }
    AVCodecParameters *parameters = _format->streams[_videoIndex]->codecpar;
    const AVCodec *decoder = avcodec_find_decoder(parameters->codec_id);
    if (!decoder || parameters->codec_id != AV_CODEC_ID_H264) {
        if (error) *error = DecoderError(AVERROR_DECODER_NOT_FOUND, @"This video profile has no available software decoder");
        return nil;
    }
    _codec = avcodec_alloc_context3(decoder);
    if (!_codec) {
        if (error) *error = DecoderError(AVERROR(ENOMEM), @"Could not allocate the video decoder");
        return nil;
    }
    result = avcodec_parameters_to_context(_codec, parameters);
    if (result >= 0) {
        _codec->thread_count = (int)MIN(8, NSProcessInfo.processInfo.activeProcessorCount);
        _codec->thread_type = FF_THREAD_FRAME | FF_THREAD_SLICE;
        result = avcodec_open2(_codec, decoder, NULL);
    }
    if (result < 0) {
        if (error) *error = DecoderError(result, @"Could not initialize the software video decoder");
        return nil;
    }
    _frame = av_frame_alloc();
    _packet = av_packet_alloc();
    if (!_frame || !_packet) {
        if (error) *error = DecoderError(AVERROR(ENOMEM), @"Could not allocate decoder frame storage");
        return nil;
    }
    return self;
}

- (NSError *)lastError { return _lastError; }

- (BOOL)seekToTime:(CMTime)time error:(NSError **)error {
    if (!CMTIME_IS_NUMERIC(time) || time.timescale <= 0 || CMTimeCompare(time, kCMTimeZero) < 0) {
        if (error) *error = DecoderError(AVERROR(EINVAL), @"Invalid video seek time");
        return NO;
    }
    AVRational sourceBase = (AVRational){1, time.timescale};
    AVRational streamBase = _format->streams[_videoIndex]->time_base;
    _seekTarget = av_rescale_q_rnd(time.value, sourceBase, streamBase, AV_ROUND_NEAR_INF | AV_ROUND_PASS_MINMAX);
    int result = av_seek_frame(_format, _videoIndex, _seekTarget, AVSEEK_FLAG_BACKWARD);
    if (result < 0) {
        if (error) *error = DecoderError(result, @"Could not seek the software video decoder");
        return NO;
    }
    avcodec_flush_buffers(_codec);
    av_packet_unref(_packet);
    av_frame_unref(_frame);
    av_frame_free(&_lastSeekFrame);
    _demuxEOF = NO;
    _flushSent = NO;
    _lastError = nil;
    return YES;
}

- (nullable FFmpegDecodedFrame *)readFrame {
    _lastError = nil;
    for (;;) {
        int result = avcodec_receive_frame(_codec, _frame);
        if (result == 0) {
            int64_t pts = _frame->best_effort_timestamp;
            if (pts == AV_NOPTS_VALUE) pts = _frame->pts;
            if (pts == AV_NOPTS_VALUE) {
                av_frame_unref(_frame);
                _lastError = DecoderError(AVERROR_INVALIDDATA, @"Decoded video frame has no presentation timestamp");
                return nil;
            }
            if (_seekTarget != AV_NOPTS_VALUE && pts < _seekTarget) {
                av_frame_free(&_lastSeekFrame);
                _lastSeekFrame = av_frame_clone(_frame);
                av_frame_unref(_frame);
                if (!_lastSeekFrame) {
                    _lastError = DecoderError(AVERROR(ENOMEM), @"Could not retain the final preview frame");
                    return nil;
                }
                continue;
            }
            _seekTarget = AV_NOPTS_VALUE;
            av_frame_free(&_lastSeekFrame);
            FFmpegDecodedFrame *output = [self convertedFrame:_frame];
            av_frame_unref(_frame);
            return output;
        }
        if (result == AVERROR_EOF) {
            if (_lastSeekFrame) {
                FFmpegDecodedFrame *output = [self convertedFrame:_lastSeekFrame];
                av_frame_free(&_lastSeekFrame);
                _seekTarget = AV_NOPTS_VALUE;
                return output;
            }
            return nil;
        }
        if (result != AVERROR(EAGAIN)) {
            _lastError = DecoderError(result, @"Software video decoding failed");
            return nil;
        }
        if (_demuxEOF) {
            if (_flushSent) {
                _lastError = DecoderError(AVERROR_INVALIDDATA, @"Video decoder did not finish draining");
                return nil;
            }
            result = avcodec_send_packet(_codec, NULL);
            _flushSent = YES;
            if (result < 0 && result != AVERROR_EOF) {
                _lastError = DecoderError(result, @"Could not finish video decoding");
                return nil;
            }
            continue;
        }
        for (;;) {
            result = av_read_frame(_format, _packet);
            if (result < 0 || _packet->stream_index == _videoIndex) break;
            av_packet_unref(_packet);
        }
        if (result == AVERROR_EOF) {
            _demuxEOF = YES;
            continue;
        }
        if (result < 0) {
            _lastError = DecoderError(result, @"Could not read the next video packet");
            return nil;
        }
        result = avcodec_send_packet(_codec, _packet);
        av_packet_unref(_packet);
        if (result < 0) {
            _lastError = DecoderError(result, @"Could not submit a video packet for software decoding");
            return nil;
        }
    }
}

/// Convert native-depth planar video directly to normalized half RGB. The
/// scaler only upsamples chroma; its legacy 8-bit RGB coefficients are bypassed.
- (BOOL)fillHalfBuffer:(CVPixelBufferRef)buffer fromFrame:(AVFrame *)frame {
    const AVPixFmtDescriptor *description = av_pix_fmt_desc_get(frame->format);
    int depth = description ? description->comp[0].depth : 0;
    if (!description || depth < 8 || depth > 16) {
        _lastError = DecoderError(AVERROR_INVALIDDATA, @"Unsupported decoded component precision");
        return NO;
    }
    uint8_t *destination = CVPixelBufferGetBaseAddress(buffer);
    size_t destinationStride = CVPixelBufferGetBytesPerRow(buffer);
    const int width = frame->width, height = frame->height;
    if (description->flags & AV_PIX_FMT_FLAG_RGB) {
        // H.264 High 4:4:4 RGB decodes to planar GBR. Never reinterpret RGB as YUV.
        if (!(description->flags & AV_PIX_FMT_FLAG_PLANAR) ||
            (description->flags & (AV_PIX_FMT_FLAG_FLOAT | AV_PIX_FMT_FLAG_BE)) || description->nb_components < 3) {
            _lastError = DecoderError(AVERROR_INVALIDDATA, @"Unsupported RGB layout for high precision software decoding");
            return NO;
        }
        for (int component = 0; component < 3; ++component) {
            if (description->comp[component].depth != depth ||
                description->comp[component].step != (depth == 8 ? 1 : 2) || description->comp[component].shift != 0) {
                _lastError = DecoderError(AVERROR_INVALIDDATA, @"Unsupported planar RGB component layout");
                return NO;
            }
        }
        const float normalization = 1.0f / (float)((1u << depth) - 1u);
        for (int y = 0; y < height; ++y) {
            __fp16 *target = (__fp16 *)(destination + (size_t)y * destinationStride);
            const uint8_t *planes[3];
            for (int c = 0; c < 3; ++c) {
                AVComponentDescriptor component = description->comp[c];
                planes[c] = frame->data[component.plane] + (size_t)y * frame->linesize[component.plane] + component.offset;
            }
            for (int x = 0; x < width; ++x) {
                for (int c = 0; c < 3; ++c) {
                    unsigned code = depth == 8 ? planes[c][x] : ((const uint16_t *)planes[c])[x];
                    target[x * 4 + c] = (__fp16)(code * normalization);
                }
                target[x * 4 + 3] = (__fp16)1.0f;
            }
        }
        return YES;
    }
    if (description->nb_components < 3) {
        _lastError = DecoderError(AVERROR_INVALIDDATA, @"Unsupported monochrome software decoder layout");
        return NO;
    }
    enum AVPixelFormat planarFormat;
    switch (depth) {
        case 8: planarFormat = AV_PIX_FMT_YUV444P; break;
        case 9: planarFormat = AV_PIX_FMT_YUV444P9LE; break;
        case 10: planarFormat = AV_PIX_FMT_YUV444P10LE; break;
        case 12: planarFormat = AV_PIX_FMT_YUV444P12LE; break;
        case 14: planarFormat = AV_PIX_FMT_YUV444P14LE; break;
        case 16: planarFormat = AV_PIX_FMT_YUV444P16LE; break;
        default:
            _lastError = DecoderError(AVERROR_INVALIDDATA, @"Unsupported decoded YUV precision");
            return NO;
    }
    enum AVColorRange range = frame->color_range;
    if (range == AVCOL_RANGE_UNSPECIFIED) range = _format->streams[_videoIndex]->codecpar->color_range;
    enum AVColorSpace space = frame->colorspace;
    if (space == AVCOL_SPC_UNSPECIFIED) space = _format->streams[_videoIndex]->codecpar->color_space;
    float kr = .299f, kb = .114f;
    int matrixID = SWS_CS_ITU601;
    if (space == AVCOL_SPC_BT709 || (space == AVCOL_SPC_UNSPECIFIED && height >= 720)) {
        kr = .2126f; kb = .0722f; matrixID = SWS_CS_ITU709;
    } else if (space == AVCOL_SPC_BT2020_NCL) {
        kr = .2627f; kb = .0593f; matrixID = SWS_CS_BT2020;
    } else if (space == AVCOL_SPC_FCC) {
        kr = .30f; kb = .11f; matrixID = SWS_CS_FCC;
    } else if (space == AVCOL_SPC_SMPTE240M) {
        kr = .212f; kb = .087f; matrixID = SWS_CS_SMPTE240M;
    } else if (space == AVCOL_SPC_BT2020_CL) {
        _lastError = DecoderError(AVERROR_INVALIDDATA, @"Constant luminance BT.2020 requires a different color conversion");
        return NO;
    }
    IOSLUTYUVMatrix matrix = IOSLUTYUVMatrixMake(depth, range == AVCOL_RANGE_JPEG, kr, kb);
    if (!_yuv444 || _yuv444->format != planarFormat || _yuv444->width != width || _yuv444->height != height) {
        av_frame_free(&_yuv444);
        _yuv444 = av_frame_alloc();
        if (!_yuv444) {
            _lastError = DecoderError(AVERROR(ENOMEM), @"Could not allocate high precision video planes");
            return NO;
        }
        _yuv444->format = planarFormat;
        _yuv444->width = width;
        _yuv444->height = height;
        int result = av_frame_get_buffer(_yuv444, 64);
        if (result < 0) {
            av_frame_free(&_yuv444);
            _lastError = DecoderError(result, @"Could not allocate high precision video plane storage");
            return NO;
        }
    }
    _chromaScaler = sws_getCachedContext(_chromaScaler, width, height, frame->format, width, height, planarFormat,
                                        SWS_BICUBIC | SWS_ACCURATE_RND, NULL, NULL, NULL);
    if (!_chromaScaler) {
        _lastError = DecoderError(AVERROR(ENOMEM), @"Could not prepare high precision chroma upsampling");
        return NO;
    }
    const int *coefficients = sws_getCoefficients(matrixID);
    int result = sws_setColorspaceDetails(_chromaScaler, coefficients, range == AVCOL_RANGE_JPEG,
                                         coefficients, range == AVCOL_RANGE_JPEG, 0, 1 << 16, 1 << 16);
    if (result >= 0) result = av_frame_make_writable(_yuv444);
    if (result >= 0) result = sws_scale(_chromaScaler, (const uint8_t * const *)frame->data, frame->linesize,
                                      0, height, _yuv444->data, _yuv444->linesize);
    if (result != height) {
        _lastError = DecoderError(result < 0 ? result : AVERROR_INVALIDDATA, @"High precision chroma upsampling failed");
        return NO;
    }
    for (int y = 0; y < height; ++y) {
        const uint8_t *planes[3];
        for (int c = 0; c < 3; ++c) planes[c] = _yuv444->data[c] + (size_t)y * _yuv444->linesize[c];
        __fp16 *target = (__fp16 *)(destination + (size_t)y * destinationStride);
        for (int x = 0; x < width; ++x) {
            float codes[3], rgb[3];
            for (int c = 0; c < 3; ++c) codes[c] = depth == 8 ? planes[c][x] : ((const uint16_t *)planes[c])[x];
            IOSLUTYUVToRGB(codes[0], codes[1], codes[2], &matrix, rgb);
            target[x * 4] = (__fp16)rgb[0];
            target[x * 4 + 1] = (__fp16)rgb[1];
            target[x * 4 + 2] = (__fp16)rgb[2];
            target[x * 4 + 3] = (__fp16)1.0f;
        }
    }
    return YES;
}

- (nullable FFmpegDecodedFrame *)convertedFrame:(AVFrame *)frame {
    int width = frame->width, height = frame->height;
    if (width <= 0 || height <= 0 || width > 16384 || height > 16384 || (int64_t)width * height > 67108864) {
        _lastError = DecoderError(AVERROR_INVALIDDATA, @"Unsupported decoded video dimensions");
        return nil;
    }
    CVPixelBufferRef buffer = NULL;
    NSDictionary *attributes = @{(__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
                                 (__bridge NSString *)kCVPixelBufferMetalCompatibilityKey: @YES};
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, _pixelFormat,
                                        (__bridge CFDictionaryRef)attributes, &buffer);
    if (status != kCVReturnSuccess || !buffer) {
        _lastError = DecoderError(AVERROR(ENOMEM), @"Could not allocate the decoded pixel buffer");
        return nil;
    }
    CVPixelBufferLockBaseAddress(buffer, 0);
    BOOL converted = NO;
    if (_pixelFormat == kCVPixelFormatType_64RGBAHalf) {
        converted = [self fillHalfBuffer:buffer fromFrame:frame];
    } else {
        // Preserve the existing lower-quality BGRA path and its native 8-bit output.
        _scaler = sws_getCachedContext(_scaler, width, height, frame->format, width, height, AV_PIX_FMT_BGRA,
                                      SWS_BICUBIC | SWS_ACCURATE_RND, NULL, NULL, NULL);
        if (_scaler) {
            int matrix = SWS_CS_DEFAULT;
            if (frame->colorspace == AVCOL_SPC_BT709 || (frame->colorspace == AVCOL_SPC_UNSPECIFIED && height >= 720)) matrix = SWS_CS_ITU709;
            else if (frame->colorspace == AVCOL_SPC_BT2020_NCL || frame->colorspace == AVCOL_SPC_BT2020_CL) matrix = SWS_CS_BT2020;
            else if (frame->colorspace == AVCOL_SPC_FCC) matrix = SWS_CS_FCC;
            else if (frame->colorspace == AVCOL_SPC_SMPTE240M) matrix = SWS_CS_SMPTE240M;
            enum AVColorRange sourceRange = frame->color_range;
            if (sourceRange == AVCOL_RANGE_UNSPECIFIED) sourceRange = _format->streams[_videoIndex]->codecpar->color_range;
            const int *coefficients = sws_getCoefficients(matrix);
            int result = sws_setColorspaceDetails(_scaler, coefficients, sourceRange == AVCOL_RANGE_JPEG,
                                                 coefficients, 1, 0, 1 << 16, 1 << 16);
            if (result >= 0) {
                uint8_t *outputPlanes[4] = {CVPixelBufferGetBaseAddress(buffer), NULL, NULL, NULL};
                int outputStrides[4] = {(int)CVPixelBufferGetBytesPerRow(buffer), 0, 0, 0};
                result = sws_scale(_scaler, (const uint8_t * const *)frame->data, frame->linesize, 0, height, outputPlanes, outputStrides);
                converted = result == height;
            }
            if (!converted) _lastError = DecoderError(result < 0 ? result : AVERROR_INVALIDDATA, @"Decoded video color conversion failed");
        } else {
            _lastError = DecoderError(AVERROR(ENOMEM), @"Could not initialize decoded video color conversion");
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    if (!converted) {
        CVPixelBufferRelease(buffer);
        return nil;
    }
    int64_t pts = frame->best_effort_timestamp == AV_NOPTS_VALUE ? frame->pts : frame->best_effort_timestamp;
    AVRational timeBase = _format->streams[_videoIndex]->time_base;
    if (timeBase.den <= 0 || timeBase.num <= 0 || pts > INT64_MAX / timeBase.num || pts < INT64_MIN / timeBase.num) {
        CVPixelBufferRelease(buffer);
        _lastError = DecoderError(AVERROR_INVALIDDATA, @"Invalid decoded video timestamp");
        return nil;
    }
    CMTime time = CMTimeMake(pts * timeBase.num, timeBase.den);
    FFmpegDecodedFrame *output = [[FFmpegDecodedFrame alloc] initWithBuffer:buffer presentationTime:time];
    CVPixelBufferRelease(buffer);
    return output;
}

- (void)dealloc {
    av_frame_free(&_lastSeekFrame);
    av_frame_free(&_frame);
    av_packet_free(&_packet);
    avcodec_free_context(&_codec);
    avformat_close_input(&_format);
    sws_freeContext(_scaler);
    sws_freeContext(_chromaScaler);
    av_frame_free(&_yuv444);
    if (_accessingSecurityScope) [_securityURL stopAccessingSecurityScopedResource];
}
@end
#endif
