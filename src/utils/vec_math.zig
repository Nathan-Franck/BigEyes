const zmath = @import("zmath");

pub fn eq(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return a == b;
}

pub fn add(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return a + b;
}

pub fn sub(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return a - b;
}

pub fn mul(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return a * b;
}

pub fn div(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return a / b;
}

pub fn translationRotationScaleToMatrix(translation: zmath.Vec, rotation: zmath.Vec, scale: zmath.Vec) zmath.Mat {
    const t = zmath.translationV(translation);
    const r = zmath.matFromQuat(rotation);
    const s = zmath.scalingV(scale);
    return zmath.mul(zmath.mul(r, s), t);
}
