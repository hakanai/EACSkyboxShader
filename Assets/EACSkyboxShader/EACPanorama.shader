Shader "Skybox/Equi-Angular Cubemap Panorama"
{
    Properties
    {
        [NoScaleOffset] _Tex ("Spherical (HDR)", 2D) = "grey" {}
    }

    SubShader
    {
        Tags
        {
            "Queue" = "Background"
            "RenderType" = "Background"
            "PreviewType" = "Skybox"
        }

        Cull Off
        ZWrite Off

        Pass
        {
            CGPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment
            #pragma multi_compile_instancing
            #pragma target 2.0
            #include "EACPanorama.cginc"
            ENDCG
        }
    }

    Fallback Off
}
