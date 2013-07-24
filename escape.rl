#include <stdlib.h>
#include <stdio.h>
#include <uchar.h>
#include <err.h>

struct buf_t {
    int cs;

    char32_t line[80];
    size_t pos;

    size_t registers;
    unsigned values[10]; // FIXME: fix
};

enum utf8_state utf8_feed(struct utf8_t *u, char ci)
{
    uint32_t c = ci;

    switch (u->state) {
    case UTF8_START:
    case UTF8_ACCEPT:
    case UTF8_REJECT:
        if (c == 0xC0 || c == 0xC1) {
            /* overlong encoding for ASCII, reject */
            u->state = UTF8_REJECT;
        } else if ((c & 0x80) == 0) {
            /* single byte, accept */
            u->cp = c;
            u->state = UTF8_ACCEPT;
        } else if ((c & 0xC0) == 0x80) {
            /* parser out of sync, ignore byte */
            u->state = UTF8_START;
        } else if ((c & 0xE0) == 0xC0) {
            /* start of two byte sequence */
            u->cp = (c & 0x1F) << 6;
            u->state = UTF8_EXPECT1;
        } else if ((c & 0xF0) == 0xE0) {
            /* start of three byte sequence */
            u->cp = (c & 0x0F) << 12;
            u->state = UTF8_EXPECT2;
        } else if ((c & 0xF8) == 0xF0) {
            /* start of four byte sequence */
            u->cp = (c & 0x07) << 18;
            u->state = UTF8_EXPECT3;
        } else {
            /* overlong encoding, reject */
            u->state = UTF8_REJECT;
        }
        break;
    case UTF8_EXPECT3:
        u->cp |= (c & 0x3F) << 12;
        if ((c & 0xC0) == 0x80)
            u->state = UTF8_EXPECT2;
        else
            u->state = UTF8_REJECT;
        break;
    case UTF8_EXPECT2:
        u->cp |= (c & 0x3F) << 6;
        if ((c & 0xC0) == 0x80)
            u->state = UTF8_EXPECT1;
        else
            u->state = UTF8_REJECT;
        break;
    case UTF8_EXPECT1:
        u->cp |= c & 0x3F;
        if ((c & 0xC0) == 0x80)
            u->state = UTF8_ACCEPT;
        else
            u->state = UTF8_REJECT;
        break;
    default:
        break;
    }

    return u->state;
}

%%{
    machine esc;

    action store {
        b->values[b->registers - 1] *= 10;
        b->values[b->registers - 1] += fc - '0';
    }

    action ich {}
    action cuu {}
    action cud {}
    action cuf {}
    action cub {}
    action cnl {}
    action cpl {}
    action cha {}
    action cup {}
    action cht {}
    action ed {}
    action decsed {}
    action el {}
    action decsel {}
    action il {}
    action dl {}
    action dch {}
    action su {}
    action sd {}
    action ech {}
    action cbt {}
    action sgr { printf("SGR\n"); }

    Ps = digit* >{ ++b->registers; } $store;
    Pm = Ps ( ';' Ps )*;

    csi = '[' (
            Ps '@'        @ ich    |
            Ps 'A'        @ cuu    |
            Ps 'B'        @ cud    |
            Ps 'C'        @ cuf    |
            Ps 'D'        @ cub    |
            Ps 'E'        @ cnl    |
            Ps 'F'        @ cpl    |
            Ps 'G'        @ cha    |
            Ps ';' Ps 'H' @ cup    |
            Ps 'I'        @ cht    |
            Ps 'J'        @ ed     |
        '?' Ps 'J'        @ decsed |
            Ps 'K'        @ el     |
        '?' Ps 'K'        @ decsel |
            Ps 'L'        @ il     |
            Ps 'M'        @ dl     |
            Ps 'P'        @ dch    |
            Ps 'S'        @ su     |
            Ps 'T'        @ sd     |
            Ps 'X'        @ ech    |
            Ps 'Z'        @ cbt    |
            Pm '`'                 |
            Ps 'b'                 |
            Ps 'c'                 |
        '>' Ps 'c'                 |
            Pm 'd'                 |
            Ps ';' Ps 'f'          |
            Ps 'g'                 |
            Pm 'h'                 |
        '?' Pm 'h'                 |
            Pm 'i'                 |
        '?' Pm 'i'                 |
            Pm 'l'                 |
        '?' Pm 'l'                 |
            Pm 'm'        @sgr     |
            Ps 'n'                 |
        '?' Ps 'n'                 |
        '!'    'p'                 |
            Ps ';' Ps '"p'         |
            Ps '"q'                |
            Ps ';' Ps 'r'          |
        '?' Pm 'r'                 |
        '?' Pm 's'                 |
            Ps ';' Ps ';' Ps 't'   |
            # CSI Pt ; Pl ; Pb ; Pr ` w
            Ps 'x'
            # CSI Ps ; Pu ` z
            # CSI Pm ` {
            # CSI Pm ` |
            # CSI Pe ; Pb ; Pr ; Pc ; Pp & w
    );

    sequence = 0x1B ( csi );
    text = any - 0x1B;

    input = sequence | text >{ b->line[b->pos++] = fc; ++fpc; };
    main := input*;
}%%

%%access b->;
%%alphtype unsigned long;
%%write data;

void init(struct buf_t *b)
{
    *b = (struct buf_t) {
        .cs        = 0,
        .line      = { 0 },
        .pos       = 0,
        .registers = 0,
        .values    = { 0 }
    };

    %%write init;
}

static int feed(struct buf_t *b, char32_t *buf, size_t len)
{
    char32_t *p = buf, *pe = buf + len;

    printf("LEN: %zd\n", len);

    %%write exec;

    if (b->cs == esc_error) {
        warnx("error parsing escape sequence");
        return -1;
    }

    return 0;
}

int main(void)
{
    static char32_t message[] = { U"this is a \033[1;4;43mtest" };
    struct buf_t buf;

    init(&buf);
    feed(&buf, message, sizeof(message) / sizeof(char32_t) - 1);

    for (int i = 0; i < buf.registers; ++i) {
        printf("REG: %d          \n", buf.values[i]);
    }

    printf("LINE: %ls\n", (wchar_t *)buf.line);
}
