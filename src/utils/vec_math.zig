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
