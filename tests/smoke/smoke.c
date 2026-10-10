/* Artifact smoke test: proves an unpacked release archive is linkable and
   functional with no MsQuic/OpenSSL sources present. Exercises both exported
   targets: MsQuicOpen2 (msquic::msquic) and SHA256 (msquic::crypto). */

#include <msquic.h>
#include <openssl/sha.h>

#include <stdio.h>
#include <string.h>

int main(void)
{
    const QUIC_API_TABLE *api = NULL;
    if (QUIC_FAILED(MsQuicOpen2(&api)))
    {
        printf("SMOKE_FAIL: MsQuicOpen2\n");
        return 1;
    }
    MsQuicClose(api);

    /* SHA256("abc") - known answer test against the bundled libcrypto */
    static const unsigned char expected[32] = {
        0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
        0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
        0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
        0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad
    };
    unsigned char digest[32];
    SHA256((const unsigned char *)"abc", 3, digest);
    if (memcmp(digest, expected, sizeof(digest)) != 0)
    {
        printf("SMOKE_FAIL: SHA256 known-answer\n");
        return 1;
    }

    printf("SMOKE_PASS\n");
    return 0;
}
