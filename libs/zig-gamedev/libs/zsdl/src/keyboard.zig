pub const Scancode = enum(u32) {
    unknown = 0,
    a = 4,
    b = 5,
    c = 6,
    d = 7,
    e = 8,
    f = 9,
    g = 10,
    h = 11,
    i = 12,
    j = 13,
    k = 14,
    l = 15,
    m = 16,
    n = 17,
    o = 18,
    p = 19,
    q = 20,
    r = 21,
    s = 22,
    t = 23,
    u = 24,
    v = 25,
    w = 26,
    x = 27,
    y = 28,
    z = 29,
    @"1" = 30,
    @"2" = 31,
    @"3" = 32,
    @"4" = 33,
    @"5" = 34,
    @"6" = 35,
    @"7" = 36,
    @"8" = 37,
    @"9" = 38,
    @"0" = 39,
    @"return" = 40,
    escape = 41,
    backspace = 42,
    tab = 43,
    space = 44,
    minus = 45,
    equals = 46,
    leftbracket = 47,
    rightbracket = 48,
    backslash = 49,
    nonushash = 50,
    semicolon = 51,
    apostrophe = 52,
    grave = 53,
    comma = 54,
    period = 55,
    slash = 56,
    capslock = 57,
    f1 = 58,
    f2 = 59,
    f3 = 60,
    f4 = 61,
    f5 = 62,
    f6 = 63,
    f7 = 64,
    f8 = 65,
    f9 = 66,
    f10 = 67,
    f11 = 68,
    f12 = 69,
    printscreen = 70,
    scrolllock = 71,
    pause = 72,
    insert = 73,
    home = 74,
    pageup = 75,
    delete = 76,
    end = 77,
    pagedown = 78,
    right = 79,
    left = 80,
    down = 81,
    up = 82,
    numlockclear = 83,
    kp_divide = 84,
    kp_multiply = 85,
    kp_minus = 86,
    kp_plus = 87,
    kp_enter = 88,
    kp_1 = 89,
    kp_2 = 90,
    kp_3 = 91,
    kp_4 = 92,
    kp_5 = 93,
    kp_6 = 94,
    kp_7 = 95,
    kp_8 = 96,
    kp_9 = 97,
    kp_0 = 98,
    kp_period = 99,
    nonusbackslash = 100,
    application = 101,
    power = 102,
    kp_equals = 103,
    f13 = 104,
    f14 = 105,
    f15 = 106,
    f16 = 107,
    f17 = 108,
    f18 = 109,
    f19 = 110,
    f20 = 111,
    f21 = 112,
    f22 = 113,
    f23 = 114,
    f24 = 115,
    execute = 116,
    help = 117,
    menu = 118,
    select = 119,
    stop = 120,
    again = 121,
    undo = 122,
    cut = 123,
    copy = 124,
    paste = 125,
    find = 126,
    mute = 127,
    volumeup = 128,
    volumedown = 129,
    kp_comma = 133,
    kp_equalsas400 = 134,
    international1 = 135,
    international2 = 136,
    international3 = 137,
    international4 = 138,
    international5 = 139,
    international6 = 140,
    international7 = 141,
    international8 = 142,
    international9 = 143,
    lang1 = 144,
    lang2 = 145,
    lang3 = 146,
    lang4 = 147,
    lang5 = 148,
    lang6 = 149,
    lang7 = 150,
    lang8 = 151,
    lang9 = 152,
    alterase = 153,
    sysreq = 154,
    cancel = 155,
    clear = 156,
    prior = 157,
    return2 = 158,
    separator = 159,
    out = 160,
    oper = 161,
    clearagain = 162,
    crsel = 163,
    exsel = 164,
    kp_00 = 176,
    kp_000 = 177,
    thousandsseparator = 178,
    decimalseparator = 179,
    currencyunit = 180,
    currencysubunit = 181,
    kp_leftparen = 182,
    kp_rightparen = 183,
    kp_leftbrace = 184,
    kp_rightbrace = 185,
    kp_tab = 186,
    kp_backspace = 187,
    kp_a = 188,
    kp_b = 189,
    kp_c = 190,
    kp_d = 191,
    kp_e = 192,
    kp_f = 193,
    kp_xor = 194,
    kp_power = 195,
    kp_percent = 196,
    kp_less = 197,
    kp_greater = 198,
    kp_ampersand = 199,
    kp_dblampersand = 200,
    kp_verticalbar = 201,
    kp_dblverticalbar = 202,
    kp_colon = 203,
    kp_hash = 204,
    kp_space = 205,
    kp_at = 206,
    kp_exclam = 207,
    kp_memstore = 208,
    kp_memrecall = 209,
    kp_memclear = 210,
    kp_memadd = 211,
    kp_memsubtract = 212,
    kp_memmultiply = 213,
    kp_memdivide = 214,
    kp_plusminus = 215,
    kp_clear = 216,
    kp_clearentry = 217,
    kp_binary = 218,
    kp_octal = 219,
    kp_decimal = 220,
    kp_hexadecimal = 221,
    lctrl = 224,
    lshift = 225,
    lalt = 226,
    lgui = 227,
    rctrl = 228,
    rshift = 229,
    ralt = 230,
    rgui = 231,
    mode = 257,
    audionext = 258,
    audioprev = 259,
    audiostop = 260,
    audioplay = 261,
    audiomute = 262,
    mediaselect = 263,
    www = 264,
    mail = 265,
    calculator = 266,
    computer = 267,
    ac_search = 268,
    ac_home = 269,
    ac_back = 270,
    ac_forward = 271,
    ac_stop = 272,
    ac_refresh = 273,
    ac_bookmarks = 274,
    brightnessdown = 275,
    brightnessup = 276,
    displayswitch = 277,
    kbdillumtoggle = 278,
    kbdillumdown = 279,
    kbdillumup = 280,
    eject = 281,
    sleep = 282,
    app1 = 283,
    app2 = 284,
    audiorewind = 285,
    audiofastforward = 286,
    softleft = 287,
    softright = 288,
    call = 289,
    endcall = 290,
    _,
};

pub const Keycode = enum(i32) {
    unknown = 0,
    @"return" = '\r',
    escape = '\x1b',
    backspace = '\x08',
    tab = '\t',
    space = ' ',
    exclaim = '!',
    quotedbl = '"',
    hash = '#',
    percent = '%',
    dollar = '$',
    ampersand = '&',
    quote = '\'',
    leftparen = '(',
    rightparen = ')',
    asterisk = '*',
    plus = '+',
    comma = ',',
    minus = '-',
    period = '.',
    slash = '/',
    @"0" = '0',
    @"1" = '1',
    @"2" = '2',
    @"3" = '3',
    @"4" = '4',
    @"5" = '5',
    @"6" = '6',
    @"7" = '7',
    @"8" = '8',
    @"9" = '9',
    colon = ':',
    semicolon = ';',
    less = '<',
    equals = '=',
    greater = '>',
    question = '?',
    at = '@',
    leftbracket = '[',
    backslash = '\\',
    rightbracket = ']',
    caret = '^',
    underscore = '_',
    backquote = '`',
    a = 'a',
    b = 'b',
    c = 'c',
    d = 'd',
    e = 'e',
    f = 'f',
    g = 'g',
    h = 'h',
    i = 'i',
    j = 'j',
    k = 'k',
    l = 'l',
    m = 'm',
    n = 'n',
    o = 'o',
    p = 'p',
    q = 'q',
    r = 'r',
    s = 's',
    t = 't',
    u = 'u',
    v = 'v',
    w = 'w',
    x = 'x',
    y = 'y',
    z = 'z',
    capslock = @intFromEnum(Scancode.capslock) | mask,
    f1 = @intFromEnum(Scancode.f1) | mask,
    f2 = @intFromEnum(Scancode.f2) | mask,
    f3 = @intFromEnum(Scancode.f3) | mask,
    f4 = @intFromEnum(Scancode.f4) | mask,
    f5 = @intFromEnum(Scancode.f5) | mask,
    f6 = @intFromEnum(Scancode.f6) | mask,
    f7 = @intFromEnum(Scancode.f7) | mask,
    f8 = @intFromEnum(Scancode.f8) | mask,
    f9 = @intFromEnum(Scancode.f9) | mask,
    f10 = @intFromEnum(Scancode.f10) | mask,
    f11 = @intFromEnum(Scancode.f11) | mask,
    f12 = @intFromEnum(Scancode.f12) | mask,
    printscreen = @intFromEnum(Scancode.printscreen) | mask,
    scrolllock = @intFromEnum(Scancode.scrolllock) | mask,
    pause = @intFromEnum(Scancode.pause) | mask,
    insert = @intFromEnum(Scancode.insert) | mask,
    home = @intFromEnum(Scancode.home) | mask,
    pageup = @intFromEnum(Scancode.pageup) | mask,
    delete = '\x7f',
    end = @intFromEnum(Scancode.end) | mask,
    pagedown = @intFromEnum(Scancode.pagedown) | mask,
    right = @intFromEnum(Scancode.right) | mask,
    left = @intFromEnum(Scancode.left) | mask,
    down = @intFromEnum(Scancode.down) | mask,
    up = @intFromEnum(Scancode.up) | mask,
    numlockclear = @intFromEnum(Scancode.numlockclear) | mask,
    kp_divide = @intFromEnum(Scancode.kp_divide) | mask,
    kp_multiply = @intFromEnum(Scancode.kp_multiply) | mask,
    kp_minus = @intFromEnum(Scancode.kp_minus) | mask,
    kp_plus = @intFromEnum(Scancode.kp_plus) | mask,
    kp_enter = @intFromEnum(Scancode.kp_enter) | mask,
    kp_1 = @intFromEnum(Scancode.kp_1) | mask,
    kp_2 = @intFromEnum(Scancode.kp_2) | mask,
    kp_3 = @intFromEnum(Scancode.kp_3) | mask,
    kp_4 = @intFromEnum(Scancode.kp_4) | mask,
    kp_5 = @intFromEnum(Scancode.kp_5) | mask,
    kp_6 = @intFromEnum(Scancode.kp_6) | mask,
    kp_7 = @intFromEnum(Scancode.kp_7) | mask,
    kp_8 = @intFromEnum(Scancode.kp_8) | mask,
    kp_9 = @intFromEnum(Scancode.kp_9) | mask,
    kp_0 = @intFromEnum(Scancode.kp_0) | mask,
    kp_period = @intFromEnum(Scancode.kp_period) | mask,
    application = @intFromEnum(Scancode.application) | mask,
    power = @intFromEnum(Scancode.power) | mask,
    kp_equals = @intFromEnum(Scancode.kp_equals) | mask,
    f13 = @intFromEnum(Scancode.f13) | mask,
    f14 = @intFromEnum(Scancode.f14) | mask,
    f15 = @intFromEnum(Scancode.f15) | mask,
    f16 = @intFromEnum(Scancode.f16) | mask,
    f17 = @intFromEnum(Scancode.f17) | mask,
    f18 = @intFromEnum(Scancode.f18) | mask,
    f19 = @intFromEnum(Scancode.f19) | mask,
    f20 = @intFromEnum(Scancode.f20) | mask,
    f21 = @intFromEnum(Scancode.f21) | mask,
    f22 = @intFromEnum(Scancode.f22) | mask,
    f23 = @intFromEnum(Scancode.f23) | mask,
    f24 = @intFromEnum(Scancode.f24) | mask,
    execute = @intFromEnum(Scancode.execute) | mask,
    help = @intFromEnum(Scancode.help) | mask,
    menu = @intFromEnum(Scancode.menu) | mask,
    select = @intFromEnum(Scancode.select) | mask,
    stop = @intFromEnum(Scancode.stop) | mask,
    again = @intFromEnum(Scancode.again) | mask,
    undo = @intFromEnum(Scancode.undo) | mask,
    cut = @intFromEnum(Scancode.cut) | mask,
    copy = @intFromEnum(Scancode.copy) | mask,
    paste = @intFromEnum(Scancode.paste) | mask,
    find = @intFromEnum(Scancode.find) | mask,
    mute = @intFromEnum(Scancode.mute) | mask,
    volumeup = @intFromEnum(Scancode.volumeup) | mask,
    volumedown = @intFromEnum(Scancode.volumedown) | mask,
    kp_comma = @intFromEnum(Scancode.kp_comma) | mask,
    kp_equalsas400 = @intFromEnum(Scancode.kp_equalsas400) | mask,
    alterase = @intFromEnum(Scancode.alterase) | mask,
    sysreq = @intFromEnum(Scancode.sysreq) | mask,
    cancel = @intFromEnum(Scancode.cancel) | mask,
    clear = @intFromEnum(Scancode.clear) | mask,
    prior = @intFromEnum(Scancode.prior) | mask,
    return2 = @intFromEnum(Scancode.return2) | mask,
    separator = @intFromEnum(Scancode.separator) | mask,
    out = @intFromEnum(Scancode.out) | mask,
    oper = @intFromEnum(Scancode.oper) | mask,
    clearagain = @intFromEnum(Scancode.clearagain) | mask,
    crsel = @intFromEnum(Scancode.crsel) | mask,
    exsel = @intFromEnum(Scancode.exsel) | mask,
    kp_00 = @intFromEnum(Scancode.kp_00) | mask,
    kp_000 = @intFromEnum(Scancode.kp_000) | mask,
    thousandsseparator = @intFromEnum(Scancode.thousandsseparator) | mask,
    decimalseparator = @intFromEnum(Scancode.decimalseparator) | mask,
    currencyunit = @intFromEnum(Scancode.currencyunit) | mask,
    currencysubunit = @intFromEnum(Scancode.currencysubunit) | mask,
    kp_leftparen = @intFromEnum(Scancode.kp_leftparen) | mask,
    kp_rightparen = @intFromEnum(Scancode.kp_rightparen) | mask,
    kp_leftbrace = @intFromEnum(Scancode.kp_leftbrace) | mask,
    kp_rightbrace = @intFromEnum(Scancode.kp_rightbrace) | mask,
    kp_tab = @intFromEnum(Scancode.kp_tab) | mask,
    kp_backspace = @intFromEnum(Scancode.kp_backspace) | mask,
    kp_a = @intFromEnum(Scancode.kp_a) | mask,
    kp_b = @intFromEnum(Scancode.kp_b) | mask,
    kp_c = @intFromEnum(Scancode.kp_c) | mask,
    kp_d = @intFromEnum(Scancode.kp_d) | mask,
    kp_e = @intFromEnum(Scancode.kp_e) | mask,
    kp_f = @intFromEnum(Scancode.kp_f) | mask,
    kp_xor = @intFromEnum(Scancode.kp_xor) | mask,
    kp_power = @intFromEnum(Scancode.kp_power) | mask,
    kp_percent = @intFromEnum(Scancode.kp_percent) | mask,
    kp_less = @intFromEnum(Scancode.kp_less) | mask,
    kp_greater = @intFromEnum(Scancode.kp_greater) | mask,
    kp_ampersand = @intFromEnum(Scancode.kp_ampersand) | mask,
    kp_dblampersand = @intFromEnum(Scancode.kp_dblampersand) | mask,
    kp_verticalbar = @intFromEnum(Scancode.kp_verticalbar) | mask,
    kp_dblverticalbar = @intFromEnum(Scancode.kp_dblverticalbar) | mask,
    kp_colon = @intFromEnum(Scancode.kp_colon) | mask,
    kp_hash = @intFromEnum(Scancode.kp_hash) | mask,
    kp_space = @intFromEnum(Scancode.kp_space) | mask,
    kp_at = @intFromEnum(Scancode.kp_at) | mask,
    kp_exclam = @intFromEnum(Scancode.kp_exclam) | mask,
    kp_memstore = @intFromEnum(Scancode.kp_memstore) | mask,
    kp_memrecall = @intFromEnum(Scancode.kp_memrecall) | mask,
    kp_memclear = @intFromEnum(Scancode.kp_memclear) | mask,
    kp_memadd = @intFromEnum(Scancode.kp_memadd) | mask,
    kp_memsubtract = @intFromEnum(Scancode.kp_memsubtract) | mask,
    kp_memmultiply = @intFromEnum(Scancode.kp_memmultiply) | mask,
    kp_memdivide = @intFromEnum(Scancode.kp_memdivide) | mask,
    kp_plusminus = @intFromEnum(Scancode.kp_plusminus) | mask,
    kp_clear = @intFromEnum(Scancode.kp_clear) | mask,
    kp_clearentry = @intFromEnum(Scancode.kp_clearentry) | mask,
    kp_binary = @intFromEnum(Scancode.kp_binary) | mask,
    kp_octal = @intFromEnum(Scancode.kp_octal) | mask,
    kp_decimal = @intFromEnum(Scancode.kp_decimal) | mask,
    kp_hexadecimal = @intFromEnum(Scancode.kp_hexadecimal) | mask,
    lctrl = @intFromEnum(Scancode.lctrl) | mask,
    lshift = @intFromEnum(Scancode.lshift) | mask,
    lalt = @intFromEnum(Scancode.lalt) | mask,
    lgui = @intFromEnum(Scancode.lgui) | mask,
    rctrl = @intFromEnum(Scancode.rctrl) | mask,
    rshift = @intFromEnum(Scancode.rshift) | mask,
    ralt = @intFromEnum(Scancode.ralt) | mask,
    rgui = @intFromEnum(Scancode.rgui) | mask,
    mode = @intFromEnum(Scancode.mode) | mask,
    audionext = @intFromEnum(Scancode.audionext) | mask,
    audioprev = @intFromEnum(Scancode.audioprev) | mask,
    audiostop = @intFromEnum(Scancode.audiostop) | mask,
    audioplay = @intFromEnum(Scancode.audioplay) | mask,
    audiomute = @intFromEnum(Scancode.audiomute) | mask,
    mediaselect = @intFromEnum(Scancode.mediaselect) | mask,
    www = @intFromEnum(Scancode.www) | mask,
    mail = @intFromEnum(Scancode.mail) | mask,
    calculator = @intFromEnum(Scancode.calculator) | mask,
    computer = @intFromEnum(Scancode.computer) | mask,
    ac_search = @intFromEnum(Scancode.ac_search) | mask,
    ac_home = @intFromEnum(Scancode.ac_home) | mask,
    ac_back = @intFromEnum(Scancode.ac_back) | mask,
    ac_forward = @intFromEnum(Scancode.ac_forward) | mask,
    ac_stop = @intFromEnum(Scancode.ac_stop) | mask,
    ac_refresh = @intFromEnum(Scancode.ac_refresh) | mask,
    ac_bookmarks = @intFromEnum(Scancode.ac_bookmarks) | mask,
    brightnessdown = @intFromEnum(Scancode.brightnessdown) | mask,
    brightnessup = @intFromEnum(Scancode.brightnessup) | mask,
    displayswitch = @intFromEnum(Scancode.displayswitch) | mask,
    kbdillumtoggle = @intFromEnum(Scancode.kbdillumtoggle) | mask,
    kbdillumdown = @intFromEnum(Scancode.kbdillumdown) | mask,
    kbdillumup = @intFromEnum(Scancode.kbdillumup) | mask,
    eject = @intFromEnum(Scancode.eject) | mask,
    sleep = @intFromEnum(Scancode.sleep) | mask,
    app1 = @intFromEnum(Scancode.app1) | mask,
    app2 = @intFromEnum(Scancode.app2) | mask,
    audiorewind = @intFromEnum(Scancode.audiorewind) | mask,
    audiofastforward = @intFromEnum(Scancode.audiofastforward) | mask,
    softleft = @intFromEnum(Scancode.softleft) | mask,
    softright = @intFromEnum(Scancode.softright) | mask,
    call = @intFromEnum(Scancode.call) | mask,
    endcall = @intFromEnum(Scancode.endcall) | mask,
    _,

    const mask = 1 << 30;
};