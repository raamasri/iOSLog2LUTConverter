#ifndef IOSLUT_FFMPEG_YUV_CONVERSION_H
#define IOSLUT_FFMPEG_YUV_CONVERSION_H
#include <math.h>
#include <stdint.h>

/// Encoded (nonlinear) Y'CbCr -> encoded RGB. No transfer function is applied.
/// This avoids the legacy scaler's 8-bit fixed-point RGB coefficient rounding.
typedef struct {
    float yOffset, yScale, chromaCenter, chromaScale;
    float rCr, bCb, gCb, gCr;
} IOSLUTYUVMatrix;

static inline IOSLUTYUVMatrix IOSLUTYUVMatrixMake(int depth, int fullRange, float kr, float kb) {
    const float maximum = (float)((1u << depth) - 1u);
    const float shift = (float)(1u << (depth - 8));
    const float kg = 1.0f - kr - kb;
    IOSLUTYUVMatrix result = {
        .yOffset = fullRange ? 0.0f : 16.0f * shift,
        .yScale = fullRange ? 1.0f / maximum : 1.0f / (219.0f * shift),
        .chromaCenter = (float)(1u << (depth - 1)),
        .chromaScale = fullRange ? 1.0f / maximum : 1.0f / (224.0f * shift),
        .rCr = 2.0f * (1.0f - kr),
        .bCb = 2.0f * (1.0f - kb),
        .gCb = -2.0f * kb * (1.0f - kb) / kg,
        .gCr = -2.0f * kr * (1.0f - kr) / kg
    };
    return result;
}

static inline void IOSLUTYUVToRGB(float yCode, float cbCode, float crCode,
                                 const IOSLUTYUVMatrix *matrix, float output[3]) {
    const float y = (yCode - matrix->yOffset) * matrix->yScale;
    const float cb = (cbCode - matrix->chromaCenter) * matrix->chromaScale;
    const float cr = (crCode - matrix->chromaCenter) * matrix->chromaScale;
    output[0] = fminf(1.0f, fmaxf(0.0f, y + matrix->rCr * cr));
    output[1] = fminf(1.0f, fmaxf(0.0f, y + matrix->gCb * cb + matrix->gCr * cr));
    output[2] = fminf(1.0f, fmaxf(0.0f, y + matrix->bCb * cb));
}
#endif
