@fragment fn main(fragment: Fragment) -> Screen {
    var final_normal: vec4<f32> = vec4(normalize(fragment.normal.xyz), 0);
    var screen: Screen;
    screen.color = vec4(final_normal.xyz * 0.5 + 0.5, 1);
    return screen;
}
