// Pocket XR for iOS: the interface between the Swift app and moonlight-common-c (Moonlight's stream core, GPLv3).
//
// moonlight-common-c keeps one connection in process-wide globals, and an iOS app is one process, so the core is
// built three times with every global name given its own prefix (scripts/gen-moonlight.sh): CMoonlight1, 2 and 3,
// one per PC screen. Each copy hands Swift this same table of functions (pxr1_pxr_api() and so on).
#pragma once

#include <stdint.h>

typedef struct {
    void* ctx;
    void (*stage)(void* ctx, int kind, int stage, int errorCode); // kind 0 starting, 1 complete, 2 failed
    void (*started)(void* ctx);
    void (*terminated)(void* ctx, int errorCode);
    void (*log)(void* ctx, const char* message);
    void (*status)(void* ctx, int connectionStatus);
    int (*videoSetup)(void* ctx, int videoFormat, int width, int height, int fps);
    // A whole frame (Annex B); returns 0 (DR_OK) or -1 (DR_NEED_IDR).
    int (*videoFrame)(void* ctx, const unsigned char* data, int length, int frameType, int frameNumber,
                      unsigned long long receiveUs);
    int (*audioInit)(void* ctx, int sampleRate, int channels, int streams, int coupledStreams, int samplesPerFrame,
                     const unsigned char* mapping);
    void (*audioSample)(void* ctx, const unsigned char* data, int length);
} PXR_CALLBACKS;

typedef struct {
    int (*start)(const char* address, const char* appVersion, const char* gfeVersion, const char* rtspSessionUrl,
                 int serverCodecModeSupport, int width, int height, int fps, int bitrateKbps, int packetSize,
                 int streamingRemotely, int audioConfiguration, int supportedVideoFormats, int clientRefreshRateX100,
                 const unsigned char* riKey16, int riKeyId, int encryptionFlags, int colorSpace, int colorRange,
                 int videoCapabilities, const PXR_CALLBACKS* callbacks);
    void (*stop)(void);
    void (*interrupt)(void);
    const char* (*launchQuery)(void);
    const char* (*stageName)(int stage);
    void (*requestIdr)(void);
    int (*rtt)(unsigned int* rttMs, unsigned int* varianceMs);
    int (*mousePosition)(short x, short y, short refW, short refH);
    int (*mouseMove)(short dx, short dy);
    int (*mouseButton)(int press, int button);
    int (*scroll)(short amount);
    int (*hscroll)(short amount);
    int (*key)(short keyCode, int down, int modifiers);
    int (*text)(const char* utf8, unsigned int length);
} PXR_API;

// AES-GCM for the stream core, done in Swift with CryptoKit (CommonCrypto has no public GCM). Returns 1 on success.
// The tag is written on encrypt and checked on decrypt.
typedef int (*PXR_GCM_FN)(int encrypt, const unsigned char* key, int keyLength, const unsigned char* iv, int ivLength,
                          unsigned char* tag, int tagLength, const unsigned char* input, int length,
                          unsigned char* output);

void pxr_set_gcm(PXR_GCM_FN fn);
PXR_GCM_FN pxr_get_gcm(void);
