#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float4 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct FragmentOut {
    float4 color [[color(0)]];
};

vertex VertexOut vertex_main(const VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = in.position;
    out.texCoord = in.texCoord;
    return out;
}

fragment FragmentOut fragment_main(VertexOut in [[stage_in]],
                                   texture2d<float> texture [[texture(0)]],
                                   sampler texSampler [[sampler(0)]]) {
    FragmentOut out;
    out.color = texture.sample(texSampler, in.texCoord);
    return out;
}
