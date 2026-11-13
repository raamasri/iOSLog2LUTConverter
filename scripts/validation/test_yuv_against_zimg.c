// Independent check of encoded YUV normalization/matrix math against libzimg.
// clang -O2 -I/opt/homebrew/opt/zimg/include -L/opt/homebrew/opt/zimg/lib \
//   -lzimg scripts/validation/test_yuv_against_zimg.c -o "$TMPDIR/yuv-zimg-test"
#include "../../iOSLOG2LUTConverter/Services/SoftwareDecoder/FFmpegYUVConversion.h"
#include <zimg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void *aligned(size_t n) { void*p=NULL;if(posix_memalign(&p,64,n))exit(2);return p; }
int main(void) {
    const int width=64,height=4;
    int ids[3]={1,5,9};float kr[3]={.2126f,.299f,.2627f},kb[3]={.0722f,.114f,.0593f};
    float maximumError=0;
    for(int m=0;m<3;++m)for(int full=0;full<2;++full) {
        zimg_image_format src,dst;
        zimg_image_format_default(&src,ZIMG_API_VERSION);zimg_image_format_default(&dst,ZIMG_API_VERSION);
        src.width=dst.width=width;src.height=dst.height=height;src.pixel_type=ZIMG_PIXEL_WORD;src.depth=10;
        src.color_family=ZIMG_COLOR_YUV;src.matrix_coefficients=(zimg_matrix_coefficients_e)ids[m];src.pixel_range=full?ZIMG_RANGE_FULL:ZIMG_RANGE_LIMITED;
        src.transfer_characteristics=dst.transfer_characteristics=ZIMG_TRANSFER_BT709;
        src.color_primaries=dst.color_primaries=ZIMG_PRIMARIES_BT709;
        dst.pixel_type=ZIMG_PIXEL_FLOAT;dst.depth=32;dst.color_family=ZIMG_COLOR_RGB;dst.matrix_coefficients=ZIMG_MATRIX_RGB;dst.pixel_range=ZIMG_RANGE_FULL;
        zimg_image_buffer_const input={.version=ZIMG_API_VERSION};zimg_image_buffer output={.version=ZIMG_API_VERSION};
        for(int c=0;c<3;++c) {
            input.plane[c].data=aligned(width*height*2);input.plane[c].stride=width*2;input.plane[c].mask=ZIMG_BUFFER_MAX;
            output.plane[c].data=aligned(width*height*4);output.plane[c].stride=width*4;output.plane[c].mask=ZIMG_BUFFER_MAX;
            for(int x=0;x<width*height;++x) ((uint16_t *)input.plane[c].data)[x]=full?((x*(17+c*12)+c*193)%1024):64+((x*(17+c*12)+c*193)%(c?897:877));
        }
        zimg_filter_graph *graph=zimg_filter_graph_build(&src,&dst,NULL);if(!graph)return 3;
        size_t size=0;zimg_filter_graph_get_tmp_size(graph,&size);void*temporary=aligned(size?size:64);
        if(zimg_filter_graph_process(graph,&input,&output,temporary,NULL,NULL,NULL,NULL))return 4;
        IOSLUTYUVMatrix matrix=IOSLUTYUVMatrixMake(10,full,kr[m],kb[m]);float error=0;
        for(int x=0;x<width*height;++x) {
            float rgb[3];IOSLUTYUVToRGB(((uint16_t *)input.plane[0].data)[x],((uint16_t *)input.plane[1].data)[x],((uint16_t *)input.plane[2].data)[x],&matrix,rgb);
            for(int c=0;c<3;++c) {float reference=fminf(1,fmaxf(0,((float *)output.plane[c].data)[x]));error=fmaxf(error,fabsf(rgb[c]-reference));}
        }
        printf("matrix=%d full=%d maximum_float_error=%.9g\n",ids[m],full,error);maximumError=fmaxf(maximumError,error);
        free(temporary);zimg_filter_graph_free(graph);
        for(int c=0;c<3;++c){free((void *)input.plane[c].data);free(output.plane[c].data);}
    }
    return maximumError>0.000002f?1:0;
}
