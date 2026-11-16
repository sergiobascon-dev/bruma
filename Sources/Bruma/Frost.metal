#include <metal_stdlib>
using namespace metal;

struct Controls {
    float4 effect; // amount, radius (source pixels), Dock protection, dim
    float4 frame;  // output width, output height, perspective, reserved
};

vertex float4 frostVertex(uint i [[vertex_id]]) {
    const float2 corners[] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
    return float4(corners[i],0,1);
}

fragment float4 frostFragment(float4 p [[position]],
                               constant Controls &c [[buffer(0)]],
                               texture2d<float> picture [[texture(0)]]) {
    constexpr sampler s(filter::linear, mip_filter::linear, address::clamp_to_edge);
    float2 uv = p.xy / c.frame.xy;
    float height = clamp(1.0 - uv.y, 0.0, 1.0);
    float amount = c.effect.x;
    float weight = (1.0-c.effect.z)*0.16 + (0.84+0.16*c.effect.z)*pow(height,1.5);

    // Optional, restrained hinge-anchored recession. At zero the screenshot's
    // coordinates stay unchanged. No stretch is applied near the Dock.
    float bend = c.frame.z * amount;
    float2 sampleUV = float2(0.5+(uv.x-0.5)*(1.0+0.32*bend*height),
                             1.0-height*(1.0+0.22*bend));
    float radius = amount * c.effect.y * weight;
    float lod = clamp(log2(max(1.0,radius)),0.0,float(picture.get_num_mip_levels()-1));
    float4 color = picture.sample(s,sampleUV,level(lod));
    float edge = min(min(sampleUV.x,1.0-sampleUV.x),min(sampleUV.y,1.0-sampleUV.y));
    float feather = max(0.001,radius/float(picture.get_height())*1.5);
    float matte = smoothstep(-feather,feather,edge);
    // Do not darken the ordinary screen boundary when perspective is off.
    matte = mix(1.0,matte,smoothstep(0.0,0.04,bend));
    color.rgb *= matte * (1.0-c.effect.w*amount*pow(height,1.35));
    return float4(color.rgb,1.0);
}
