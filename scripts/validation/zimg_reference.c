// Independent high precision YUV->RGB reference using host libzimg (zscale's
// engine). No transfer/gamut conversion: input/output transfer and primaries
// are equal. Output is planar G-B-R float32 for FFmpeg gbrpf32le input.
// clang -O2 -I/opt/homebrew/opt/zimg/include -L/opt/homebrew/opt/zimg/lib \
//   -lzimg scripts/validation/zimg_reference.c -o "$TMPDIR/zimg-reference"
#include <zimg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void fail(const char *message) {
    char detail[512]={0};zimg_get_last_error(detail,sizeof(detail));
    fprintf(stderr,"%s: %s\n",message,detail);exit(1);
}
static void *allocate(size_t bytes) {
    void *p=NULL;if (posix_memalign(&p,64,bytes?bytes:64)) fail("Allocation failed");return p;
}
int main(int argc,char **argv) {
    if (argc!=10) { fprintf(stderr,"input output width height depth subW subH fullRange matrix\n");return 2; }
    unsigned w=atoi(argv[3]),h=atoi(argv[4]),depth=atoi(argv[5]),sw=atoi(argv[6]),sh=atoi(argv[7]);
    int full=atoi(argv[8]),matrix=atoi(argv[9]);
    if (!w||!h||depth<8||depth>16||sw>1||sh>1) return 2;
    zimg_image_format src,dst;
    zimg_image_format_default(&src,ZIMG_API_VERSION);zimg_image_format_default(&dst,ZIMG_API_VERSION);
    src.width=dst.width=w;src.height=dst.height=h;
    src.pixel_type=depth==8?ZIMG_PIXEL_BYTE:ZIMG_PIXEL_WORD;src.depth=depth;
    src.subsample_w=sw;src.subsample_h=sh;src.color_family=ZIMG_COLOR_YUV;
    src.matrix_coefficients=(zimg_matrix_coefficients_e)matrix;src.pixel_range=full?ZIMG_RANGE_FULL:ZIMG_RANGE_LIMITED;
    src.transfer_characteristics=dst.transfer_characteristics=ZIMG_TRANSFER_BT709;
    src.color_primaries=dst.color_primaries=ZIMG_PRIMARIES_BT709;
    dst.pixel_type=ZIMG_PIXEL_FLOAT;dst.depth=32;dst.color_family=ZIMG_COLOR_RGB;
    dst.matrix_coefficients=ZIMG_MATRIX_RGB;dst.pixel_range=ZIMG_RANGE_FULL;
    zimg_graph_builder_params params;zimg_graph_builder_params_default(&params,ZIMG_API_VERSION);
    params.resample_filter_uv=ZIMG_RESIZE_BICUBIC;params.filter_param_a_uv=0;params.filter_param_b_uv=.6;
    zimg_filter_graph *graph=zimg_filter_graph_build(&src,&dst,&params);if (!graph) fail("Graph build failed");
    zimg_image_buffer_const in={.version=ZIMG_API_VERSION};zimg_image_buffer out={.version=ZIMG_API_VERSION};
    FILE *file=fopen(argv[1],"rb");if (!file) fail("Input open failed");
    unsigned bytes=depth==8?1:2;
    for (int c=0;c<3;++c) {
        unsigned pw=c?w>>sw:w,ph=c?h>>sh:h;
        size_t row=((size_t)pw*bytes+63)&~(size_t)63;
        in.plane[c].data=allocate(row*ph);in.plane[c].stride=row;in.plane[c].mask=ZIMG_BUFFER_MAX;
        for (unsigned y=0;y<ph;++y) {
            if (fread((uint8_t *)in.plane[c].data+y*row,bytes,pw,file)!=pw) fail("Input frame is incomplete");
        }
        row=((size_t)w*sizeof(float)+63)&~(size_t)63;
        out.plane[c].data=allocate(row*h);out.plane[c].stride=row;out.plane[c].mask=ZIMG_BUFFER_MAX;
    }
    fclose(file);size_t tmpSize=0;
    if (zimg_filter_graph_get_tmp_size(graph,&tmpSize)) fail("Temporary size failed");
    void *temporary=allocate(tmpSize);
    if (zimg_filter_graph_process(graph,&in,&out,temporary,NULL,NULL,NULL,NULL)) fail("Conversion failed");
    file=fopen(argv[2],"wb");if (!file) fail("Output open failed");
    int order[3]={1,2,0};
    for (int p=0;p<3;++p)for (unsigned y=0;y<h;++y) {
        if (fwrite((uint8_t *)out.plane[order[p]].data+y*out.plane[order[p]].stride,sizeof(float),w,file)!=w) fail("Output write failed");
    }
    fclose(file);free(temporary);
    for (int c=0;c<3;++c) { free((void *)in.plane[c].data);free(out.plane[c].data); }
    zimg_filter_graph_free(graph);return 0;
}
