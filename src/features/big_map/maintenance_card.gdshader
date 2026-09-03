shader_type canvas_item;
uniform vec4 accent : source_color = vec4(0.1,0.5,0.8,1.0);
uniform vec2 dimensions = vec2(400.0,104.0);
void fragment() {
 vec2 p = UV * dimensions;
 vec2 q = abs(p - dimensions * 0.5) - dimensions * 0.5 + 16.0;
 float d = length(max(q,vec2(0.0))) + min(max(q.x,q.y),0.0) - 16.0;
 vec3 c = mix(accent.rgb, mix(accent.rgb,vec3(1.0),0.25), UV.x);
 float bubble = 1.0 - smoothstep(44.0,45.0,length(p-vec2(dimensions.x-25.0,18.0)));
 c = mix(c,vec3(1.0),bubble*0.13);
 COLOR = vec4(c,1.0-smoothstep(-1.0,0.0,d));
}
