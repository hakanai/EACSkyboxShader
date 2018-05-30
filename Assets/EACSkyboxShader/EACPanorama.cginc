// Derived from https://github.com/Unity-Technologies/SkyboxPanoramicShader
//
// Their version supports standard Unity layouts for cube maps as well as
// cylindrical projections.
// This version only supports YouTube's equi-angular layout.

#include "UnityCG.cginc"

sampler2D _Tex;
float4 _Tex_TexelSize;
half4 _Tex_HDR;

// Layout summary, for reference:
// - Front (+X) - maps to left middle, tipped to left
// - Back (-X) - maps to right middle, upright
// - Up (+Y) - maps to right top, upright
// - Down (-Y) - maps to right bottom, upright
// - Left (+Z) - maps to left bottom, tipped to left
// - Right (-Z) - maps to left top, tipped to left

// Matrices to orient a [0..+1] square for each side
static const float3x3 ORIENT_POS_X = float3x3( 0, -1, 1, -1,  0, 1, 0, 0, 1);
static const float3x3 ORIENT_NEG_X = float3x3(-1,  0, 1,  0, -1, 1, 0, 0, 1);
static const float3x3 ORIENT_POS_Y = float3x3( 0,  1, 0,  1,  0, 0, 0, 0, 1);
static const float3x3 ORIENT_NEG_Y = float3x3( 0, -1, 1,  1,  0, 0, 0, 0, 1);
static const float3x3 ORIENT_POS_Z = float3x3( 0,  1, 0, -1,  0, 1, 0, 0, 1);
static const float3x3 ORIENT_NEG_Z = float3x3( 0, -1, 1, -1,  0, 1, 0, 0, 1);

// Vectors to offset a [0..+1/4,0..+1/3] rectangle for each side
static const float2 OFFSET_POS_X = float2(0.0,  0.33333333);
static const float2 OFFSET_NEG_X = float2(0.25, 0.33333333);
static const float2 OFFSET_POS_Y = float2(0.25, 0.66666666);
static const float2 OFFSET_NEG_Y = float2(0.25, 0.0       );
static const float2 OFFSET_POS_Z = float2(0.0,  0.0       );
static const float2 OFFSET_NEG_Z = float2(0.0,  0.66666666);

/**
 * Converts a direction vector to equi-angular cube map coordinates.
 *
 * @param coords the input direction vector.
 * @param edgeSize the size of one row of pixels around the edge.
 *        (X and Y in their respective components.)
 */
inline float2 EquiAngularCubeMap(float3 coords, float2 edgeSize)
{
    // Map the direction vector to a face and coordinate within
    // that face.
    // This bit of the maths is from:
    // https://github.com/Unity-Technologies/SkyboxPanoramicShader
    // Determine the primary axis of the normal
    float3 absn = abs(coords);
    float3 absdir = absn > float3(max(absn.y, absn.z),
                                  max(absn.x, absn.z),
                                  max(absn.x, absn.y)) ? 1 : 0;
    // Convert the normal to a local face texture coord [-1..+1, -1..+1]
    float3 tcAndLen = mul(absdir,
                          float3x3(coords.zyx,
                                   coords.xzy,
                                   float3(-coords.xy, coords.z)));
    float2 tc = tcAndLen.xy / tcAndLen.z;
    // `tcAndLen.z == dot(coords, absdir)` and thus its sign
    // tells us whether the normal is pointing positive or negative
    bool positive = tcAndLen.z > 0;

    // `tc` now contains values from [-1..+1, -1..+1].

    // Undo the equi-angular cube map
    // Uses equations documented here:
    // https://blog.google/products/google-vr/bringing-pixels-front-and-center-vr-video/
    // Except we account for the difference that after our previous step,
    // tc range is [-1..+1, -1..+1], but the documented equations show
    // the input being from [-0.5..+0.5, -0.5..+0.5].
    tc = (2 * UNITY_INV_PI) * atan(tc) + 0.5;

    // `tc` now contains values from [0..+1, 0..+1]

    // Depending on which face of the cube we landed on, flip and/or
    // rotate the coords and transform to land in the right orientation.
    float3x3 orientMatrix =
        (absdir.x > 0) ? (positive ? ORIENT_POS_X : ORIENT_NEG_X)
      : (absdir.y > 0) ? (positive ? ORIENT_POS_Y : ORIENT_NEG_Y)
      :                  (positive ? ORIENT_POS_Z : ORIENT_NEG_Z);
    tc = mul(orientMatrix, float3(tc, 1)).xy;

    // At the end of that step, the values are still from [0..+1, 0..+1].
    // Now scale to a [0..+1/4, 0..+1/3] range for one cell of the video.
    tc = mul(float2x2(0.25, 0, 0, 0.33333333), tc);

    // Clamp to edges to avoid seams (changing it in the texture isn't enough,
    // because it only solves the edges of the video, not our divisions inside
    // the video!)
    // This is done after the scaling because that's the units `edgeSize` uses.
    tc = clamp(tc, edgeSize, float2(0.25, 0.33333333) - edgeSize);

    // Translate to destination.
    float2 offsetVector = 
        (absdir.x > 0) ? (positive ? OFFSET_POS_X : OFFSET_NEG_X)
      : (absdir.y > 0) ? (positive ? OFFSET_POS_Y : OFFSET_NEG_Y)
      :                  (positive ? OFFSET_POS_Z : OFFSET_NEG_Z);
    tc += offsetVector;

#if UNITY_SINGLE_PASS_STEREO
    // Finally, if it's for the right eye, shift 0.5 to the right.
    tc.x += 0.5 * unity_StereoEyeIndex;
#endif

    return tc;
}

struct VertexInput
{
    float4 vertex : POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct FragmentInput
{
    float4 vertex : SV_POSITION;
    float3 texcoord : TEXCOORD0;
    float2 edgeSize : TEXCOORD2;
    UNITY_VERTEX_OUTPUT_STEREO
};

FragmentInput Vertex(VertexInput input)
{
    FragmentInput output;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
    output.vertex = UnityObjectToClipPos(input.vertex);
    output.texcoord = input.vertex.xyz;

    output.edgeSize = _Tex_TexelSize.xy;

    return output;
}

fixed4 Fragment(FragmentInput input) : SV_Target
{
    float2 texcoord = EquiAngularCubeMap(input.texcoord, input.edgeSize);
    half4 tex = tex2D(_Tex, texcoord);
    half3 c = DecodeHDR(tex, _Tex_HDR);
    return half4(c, 1);
}
