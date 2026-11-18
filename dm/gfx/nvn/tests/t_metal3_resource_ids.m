// Texture and sampler GPU IDs occupy separate namespaces on Apple GPUs.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdatomic.h>
#include <string.h>
#include "../nvn_metal3_compat.inc"
int main(void) { @autoreleasepool {
    NX3Device *device=(id)nx3_create_device(); assert(device.native);
    [device newCommandQueue];
    NSMutableDictionary *textures=[NSMutableDictionary new], *samplers=[NSMutableDictionary new];
    id<MTLTexture> texture=nil; id<MTLSamplerState> sampler=nil;
    MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];
    td.storageMode=MTLStorageModeShared; td.usage=MTLTextureUsageShaderRead;
    for (int i=0;i<4096 && !texture;i++) {
        id<MTLTexture> t=[device.native newTextureWithDescriptor:td]; assert(t);
        textures[@(t.gpuResourceID._impl)]=t;
        MTLSamplerDescriptor *sd=[MTLSamplerDescriptor new]; sd.supportArgumentBuffers=YES; sd.lodMaxClamp=i+1;
        id<MTLSamplerState> s=[device.native newSamplerStateWithDescriptor:sd]; assert(s);
        samplers[@(s.gpuResourceID._impl)]=s;
        if (samplers[@(t.gpuResourceID._impl)]) { texture=t; sampler=samplers[@(t.gpuResourceID._impl)]; }
        else if (textures[@(s.gpuResourceID._impl)]) { texture=textures[@(s.gpuResourceID._impl)]; sampler=s; }
    }
    if (!texture) { fprintf(stderr,"No native cross-type ID collision found; fixture is inconclusive on this device\n"); return 77; }
    printf("Native cross-type collision: texture/sampler ID 0x%llx\n",texture.gpuResourceID._impl); fflush(stdout);
    uint8_t pixels[64]; for(int i=0;i<16;i++) {pixels[4*i]=255;pixels[4*i+1]=0;pixels[4*i+2]=0;pixels[4*i+3]=255;}
    [texture replaceRegion:MTLRegionMake2D(0,0,4,4) mipmapLevel:0 withBytes:pixels bytesPerRow:16];
    NSError *error=nil;
    NSString *source=@"#include <metal_stdlib>\nusing namespace metal; vertex float4 v(uint i [[vertex_id]]) { float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};return float4(p[i],0,1); } fragment float4 f(texture2d<float> t [[texture(0)]],sampler s [[sampler(0)]]) {return t.sample(s,float2(0.5));}";
    id<MTLLibrary> lib=[device.native newLibraryWithSource:source options:nil error:&error]; assert(lib);
    MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[lib newFunctionWithName:@"v"];pd.fragmentFunction=[lib newFunctionWithName:@"f"];pd.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA8Unorm;
    id<MTLRenderPipelineState> pso=[device newRenderPipelineStateWithDescriptor:pd error:&error];assert(pso);
    td.usage=MTLTextureUsageRenderTarget;id<MTLTexture> target=[device newTextureWithDescriptor:td];assert(target);
    NX3Table *table=[NX3Table new];[table setTexture:texture.gpuResourceID atIndex:0];[table setSamplerState:sampler.gpuResourceID atIndex:0];
    for(int reverse=0;reverse<2;reverse++) {
        // Both overwrite directions must preserve the two distinct resources.
        if(reverse) {nx3_register(sampler);nx3_register(texture);} else {nx3_register(texture);nx3_register(sampler);}
        NX3CommandBuffer *cb=[device newCommandBuffer];[cb beginCommandBufferWithAllocator:nil];
        MTLRenderPassDescriptor *rp=[MTLRenderPassDescriptor renderPassDescriptor];rp.colorAttachments[0].texture=target;rp.colorAttachments[0].loadAction=MTLLoadActionClear;rp.colorAttachments[0].storeAction=MTLStoreActionStore;
        NX3Encoder *enc=(id)[cb renderCommandEncoderWithDescriptor:rp];[enc setRenderPipelineState:pso];[enc setArgumentTable:table atStages:MTLRenderStageFragment];
        [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[enc endEncoding];[cb.native commit];[cb.native waitUntilCompleted];assert(!cb.native.error);
        memset(pixels,0,sizeof pixels);[target getBytes:pixels bytesPerRow:16 fromRegion:MTLRegionMake2D(0,0,4,4) mipmapLevel:0];
        for(int i=0;i<16;i++)assert(pixels[i*4]==255 && pixels[i*4+1]==0 && pixels[i*4+2]==0 && pixels[i*4+3]==255);
    }
    puts("PASS: colliding texture/sampler IDs render red in both registration orders");
}return 0;}
