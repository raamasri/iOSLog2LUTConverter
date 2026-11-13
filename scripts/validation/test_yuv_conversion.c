// clang -O2 scripts/validation/test_yuv_conversion.c -o "$TMPDIR/yuv-test"
#include "../../iOSLOG2LUTConverter/Services/SoftwareDecoder/FFmpegYUVConversion.h"
#include <stdio.h>
#include <stdlib.h>

static void expect(float actual, float target) {
    if (fabsf(actual-target)>0.000001f) {
        fprintf(stderr,"YUV matrix mismatch: %.9f expected %.9f\n",actual,target);exit(1);
    }
}
int main(void) {
    float rgb[3];
    for (int depth=8;depth<=16;++depth) {
        unsigned shift=1u<<(depth-8);
        IOSLUTYUVMatrix m=IOSLUTYUVMatrixMake(depth,0,.2126f,.0722f);
        IOSLUTYUVToRGB(16*shift,128*shift,128*shift,&m,rgb);
        for (int c=0;c<3;++c) expect(rgb[c],0);
        IOSLUTYUVToRGB(125.5f*shift,128*shift,128*shift,&m,rgb);
        for (int c=0;c<3;++c) expect(rgb[c],.5f);
        IOSLUTYUVToRGB(235*shift,128*shift,128*shift,&m,rgb);
        for (int c=0;c<3;++c) expect(rgb[c],1);
        m=IOSLUTYUVMatrixMake(depth,1,.2126f,.0722f);
        IOSLUTYUVToRGB((1u<<depth)-1,1u<<(depth-1),1u<<(depth-1),&m,rgb);
        for (int c=0;c<3;++c) expect(rgb[c],1);
    }
    // Limited-range Rec.709 red, represented without premature integer rounding.
    IOSLUTYUVMatrix m=IOSLUTYUVMatrixMake(10,0,.2126f,.0722f);
    IOSLUTYUVToRGB(64+.2126f*876,512-(.2126f/(2*(1-.0722f)))*896,960,&m,rgb);
    expect(rgb[0],1);expect(rgb[1],0);expect(rgb[2],0);
    puts("Validated limited/full black/midgray/white anchors at depths8..16 and Rec709 red.");
    return 0;
}
