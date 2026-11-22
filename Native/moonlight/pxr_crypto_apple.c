// Pocket XR for iOS: moonlight-common-c's crypto (PlatformCrypto.h) on Apple's own libraries, in place of
// src/PlatformCrypto.c and OpenSSL, as Pocket XR for Windows does it on CNG (pxr_crypto_bcrypt.c). Same behaviour:
// - AES-128-GCM: one message per call, tag separate. Done in Swift with CryptoKit (pxr_api.h, pxr_set_gcm).
// - AES-128-CBC decrypt with CIPHER_FLAG_RESET_IV | CIPHER_FLAG_FINISH: one message, PKCS#7 padding removed.
// - AES-128-CBC encrypt with CIPHER_FLAG_PAD_TO_BLOCK_SIZE: PKCS#7 padded in place, the chain carried across calls
//   until CIPHER_FLAG_RESET_IV (input on hosts before generation 7).
// GPLv3, as moonlight-common-c.

#include <CommonCrypto/CommonCryptor.h>
#include <Security/SecRandom.h>
#include <stdlib.h>
#include <string.h>

#include "PlatformCrypto.h"
#include "pxr_api.h"

typedef struct {
    unsigned char key[32];
    int keyLength;
    unsigned char iv[16];
    bool cbcChained;
} PXR_CRYPTO;

PPLT_CRYPTO_CONTEXT PltCreateCryptoContext(void) {
    return (PPLT_CRYPTO_CONTEXT)calloc(1, sizeof(PXR_CRYPTO));
}

void PltDestroyCryptoContext(PPLT_CRYPTO_CONTEXT ctx) {
    PXR_CRYPTO* c = (PXR_CRYPTO*)ctx;
    if (c == NULL) return;
    memset(c, 0, sizeof(*c));
    free(c);
}

static void pkcs7Pad(unsigned char* data, int len, int* padded) {
    int p = ROUND_TO_PKCS7_PADDED_LEN(len);
    memset(data + len, (unsigned char)(16 - (len % 16)), (size_t)(p - len));
    *padded = p;
}

static bool pxrCrypt(bool encrypt, PPLT_CRYPTO_CONTEXT ctx, int algorithm, int flags,
                  unsigned char* key, int keyLength, unsigned char* iv, int ivLength,
                  unsigned char* tag, int tagLength, unsigned char* in, int inLen,
                  unsigned char* out, int* outLen) {
    PXR_CRYPTO* c = (PXR_CRYPTO*)ctx;
    if (c == NULL || keyLength > 32) return false;

    if (algorithm == ALGORITHM_AES_GCM) {
        PXR_GCM_FN gcm = pxr_get_gcm();
        if (gcm == NULL) return false;
        if (!gcm(encrypt ? 1 : 0, key, keyLength, iv, ivLength, tag, tagLength, in, inLen, out)) return false;
        *outLen = inLen;
        return true;
    }

    if (algorithm != ALGORITHM_AES_CBC || ivLength > 16) return false;
    if (c->keyLength != keyLength || memcmp(c->key, key, (size_t)keyLength) != 0) {
        memcpy(c->key, key, (size_t)keyLength);
        c->keyLength = keyLength;
        c->cbcChained = false;
    }
    if (!c->cbcChained || (flags & CIPHER_FLAG_RESET_IV)) {
        memset(c->iv, 0, sizeof(c->iv));
        memcpy(c->iv, iv, (size_t)ivLength);
        c->cbcChained = true;
    }

    size_t done = 0;
    CCCryptorStatus st;
    if (encrypt) {
        int len = inLen;
        if (flags & CIPHER_FLAG_PAD_TO_BLOCK_SIZE) {
            pkcs7Pad(in, inLen, &len);
            st = CCCrypt(kCCEncrypt, kCCAlgorithmAES, 0, c->key, (size_t)keyLength, c->iv, in, (size_t)len,
                         out, (size_t)len, &done);
        } else {
            // CIPHER_FLAG_FINISH: PKCS#7 added here; output is the padded length.
            CCOptions o = (flags & CIPHER_FLAG_FINISH) ? kCCOptionPKCS7Padding : 0;
            st = CCCrypt(kCCEncrypt, kCCAlgorithmAES, o, c->key, (size_t)keyLength, c->iv, in, (size_t)len,
                         out, (size_t)ROUND_TO_PKCS7_PADDED_LEN(len + 1), &done);
        }
        if (st != kCCSuccess) return false;
        // The chain goes on from the last cipher block.
        if (done >= 16) memcpy(c->iv, out + done - 16, 16);
    } else {
        unsigned char nextIv[16];
        if (inLen >= 16) memcpy(nextIv, in + inLen - 16, 16);
        CCOptions o = (flags & CIPHER_FLAG_FINISH) ? kCCOptionPKCS7Padding : 0;
        st = CCCrypt(kCCDecrypt, kCCAlgorithmAES, o, c->key, (size_t)keyLength, c->iv, in, (size_t)inLen,
                     out, (size_t)inLen, &done);
        if (st != kCCSuccess) return false;
        if (inLen >= 16) memcpy(c->iv, nextIv, 16);
    }
    if (flags & CIPHER_FLAG_FINISH) c->cbcChained = false;
    *outLen = (int)done;
    return true;
}

bool PltEncryptMessage(PPLT_CRYPTO_CONTEXT ctx, int algorithm, int flags,
                       unsigned char* key, int keyLength, unsigned char* iv, int ivLength,
                       unsigned char* tag, int tagLength, unsigned char* inputData, int inputDataLength,
                       unsigned char* outputData, int* outputDataLength) {
    return pxrCrypt(true, ctx, algorithm, flags, key, keyLength, iv, ivLength, tag, tagLength,
                 inputData, inputDataLength, outputData, outputDataLength);
}

bool PltDecryptMessage(PPLT_CRYPTO_CONTEXT ctx, int algorithm, int flags,
                       unsigned char* key, int keyLength, unsigned char* iv, int ivLength,
                       unsigned char* tag, int tagLength, unsigned char* inputData, int inputDataLength,
                       unsigned char* outputData, int* outputDataLength) {
    return pxrCrypt(false, ctx, algorithm, flags, key, keyLength, iv, ivLength, tag, tagLength,
                 inputData, inputDataLength, outputData, outputDataLength);
}

void PltGenerateRandomData(unsigned char* data, int length) {
    if (SecRandomCopyBytes(kSecRandomDefault, (size_t)length, data) != errSecSuccess) {
        arc4random_buf(data, (size_t)length);
    }
}
