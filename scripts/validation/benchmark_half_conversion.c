// Verify every normalized UInt16 converts identically through scalar and NEON
// half paths, then measure a Debug (-O0) conversion workload on Apple Silicon.
// clang -O0 scripts/validation/benchmark_half_conversion.c -o "$TMPDIR/half-bench"
#include <arm_neon.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static __attribute__((noinline)) void scalar(const uint16_t *source, __fp16 *target, size_t count) {
    const float normalization = 1.0f / 65535.0f;
    for (size_t x=0;x<count;++x) target[x]=(__fp16)(source[x]*normalization);
}
static __attribute__((noinline)) void vectorized(const uint16_t *source, __fp16 *target, size_t count) {
    const float normalization = 1.0f / 65535.0f;
    size_t x=0;
    for (;x+8<=count;x+=8) {
        uint16x8_t integers=vld1q_u16(source+x);
        float32x4_t low=vmulq_n_f32(vcvtq_f32_u32(vmovl_u16(vget_low_u16(integers))),normalization);
        float32x4_t high=vmulq_n_f32(vcvtq_f32_u32(vmovl_u16(vget_high_u16(integers))),normalization);
        vst1q_f16((float16_t *)(target+x),vcombine_f16(vcvt_f16_f32(low),vcvt_f16_f32(high)));
    }
    for (;x<count;++x) target[x]=(__fp16)(source[x]*normalization);
}
static double now(void) {
    struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);
    return t.tv_sec+t.tv_nsec/1e9;
}
int main(void) {
    size_t count=65536;
    uint16_t *input=malloc(count*sizeof(*input));
    __fp16 *a=malloc(count*sizeof(*a)),*b=malloc(count*sizeof(*b));
    if (!input||!a||!b) return 2;
    for (size_t x=0;x<count;++x) input[x]=(uint16_t)x;
    scalar(input,a,count);vectorized(input,b,count);
    if (memcmp(a,b,count*sizeof(*a))) { fprintf(stderr,"Half conversion mismatch\n");return 1; }
    double start=now();
    volatile float observed=0;
    for (int pass=0;pass<100;++pass) { scalar(input,a,count); observed+=(float)a[pass]; }
    double scalarTime=now()-start;start=now();
    for (int pass=0;pass<100;++pass) { vectorized(input,b,count); observed+=(float)b[pass]; }
    double vectorTime=now()-start;
    printf("{\"all_65536_half_patterns_identical\":true,\"scalar_seconds\":%.6f,\"neon_seconds\":%.6f,\"speedup\":%.3f}\n",scalarTime,vectorTime,scalarTime/vectorTime);
    if (observed<0) return 3;
    free(input);free(a);free(b);return 0;
}
