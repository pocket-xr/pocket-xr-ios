// Pocket XR for iOS: a flat interface to moonlight-common-c for Swift (App/PcScreens), as Pocket XR for Windows'
// pxr_moonlight.c, with a context pointer on every callback. Built three times with prefixed names (see pxr_api.h).
// Video arrives as whole frames (the decode unit's buffers joined), audio as Opus packets. GPLv3.

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "Limelight.h"
#include "pxr_api.h"

static PXR_CALLBACKS cb;
static unsigned char* frameBuf;
static int frameCap;

static void onStageStarting(int stage) { if (cb.stage) cb.stage(cb.ctx, 0, stage, 0); }
static void onStageComplete(int stage) { if (cb.stage) cb.stage(cb.ctx, 1, stage, 0); }
static void onStageFailed(int stage, int err) { if (cb.stage) cb.stage(cb.ctx, 2, stage, err); }
static void onStarted(void) { if (cb.started) cb.started(cb.ctx); }
static void onTerminated(int err) { if (cb.terminated) cb.terminated(cb.ctx, err); }
static void onStatus(int s) { if (cb.status) cb.status(cb.ctx, s); }

static void onLog(const char* format, ...) {
    char line[1024];
    va_list ap;
    va_start(ap, format);
    vsnprintf(line, sizeof(line), format, ap);
    va_end(ap);
    size_t n = strlen(line);
    while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r')) line[--n] = 0;
    if (cb.log) cb.log(cb.ctx, line);
}

static int onVideoSetup(int videoFormat, int width, int height, int redrawRate, void* context, int drFlags) {
    (void)context; (void)drFlags;
    return cb.videoSetup ? cb.videoSetup(cb.ctx, videoFormat, width, height, redrawRate) : 0;
}

static int onDecodeUnit(PDECODE_UNIT du) {
    if (du->fullLength > frameCap) {
        int cap = du->fullLength + 65536;
        unsigned char* b = (unsigned char*)realloc(frameBuf, (size_t)cap);
        if (b == NULL) return DR_NEED_IDR;
        frameBuf = b;
        frameCap = cap;
    }
    int at = 0;
    for (PLENTRY e = du->bufferList; e != NULL; e = e->next) {
        memcpy(frameBuf + at, e->data, (size_t)e->length);
        at += e->length;
    }
    if (!cb.videoFrame) return DR_OK;
    return cb.videoFrame(cb.ctx, frameBuf, at, du->frameType, du->frameNumber, du->receiveTimeUs);
}

static int onAudioInit(int audioConfiguration, const POPUS_MULTISTREAM_CONFIGURATION c, void* context, int arFlags) {
    (void)audioConfiguration; (void)context; (void)arFlags;
    return cb.audioInit ? cb.audioInit(cb.ctx, c->sampleRate, c->channelCount, c->streams, c->coupledStreams,
                                       c->samplesPerFrame, c->mapping) : 0;
}

static void onAudioSample(char* data, int length) {
    if (cb.audioSample) cb.audioSample(cb.ctx, (const unsigned char*)data, length);
}

static int start(const char* address, const char* appVersion, const char* gfeVersion, const char* rtspSessionUrl,
                 int serverCodecModeSupport, int width, int height, int fps, int bitrateKbps, int packetSize,
                 int streamingRemotely, int audioConfiguration, int supportedVideoFormats, int clientRefreshRateX100,
                 const unsigned char* riKey16, int riKeyId, int encryptionFlags, int colorSpace, int colorRange,
                 int videoCapabilities, const PXR_CALLBACKS* callbacks) {
    cb = *callbacks;

    SERVER_INFORMATION server;
    LiInitializeServerInformation(&server);
    server.address = address;
    server.serverInfoAppVersion = appVersion;
    server.serverInfoGfeVersion = gfeVersion;
    server.rtspSessionUrl = rtspSessionUrl;
    server.serverCodecModeSupport = serverCodecModeSupport;

    STREAM_CONFIGURATION config;
    LiInitializeStreamConfiguration(&config);
    config.width = width;
    config.height = height;
    config.fps = fps;
    config.bitrate = bitrateKbps;
    config.packetSize = packetSize;
    config.streamingRemotely = streamingRemotely;
    config.audioConfiguration = audioConfiguration;
    config.supportedVideoFormats = supportedVideoFormats;
    config.clientRefreshRateX100 = clientRefreshRateX100;
    config.encryptionFlags = encryptionFlags;
    config.colorSpace = colorSpace;
    config.colorRange = colorRange;
    memcpy(config.remoteInputAesKey, riKey16, 16);
    memset(config.remoteInputAesIv, 0, sizeof(config.remoteInputAesIv));
    config.remoteInputAesIv[0] = (char)((riKeyId >> 24) & 0xff);
    config.remoteInputAesIv[1] = (char)((riKeyId >> 16) & 0xff);
    config.remoteInputAesIv[2] = (char)((riKeyId >> 8) & 0xff);
    config.remoteInputAesIv[3] = (char)(riKeyId & 0xff);

    CONNECTION_LISTENER_CALLBACKS listener;
    LiInitializeConnectionCallbacks(&listener);
    listener.stageStarting = onStageStarting;
    listener.stageComplete = onStageComplete;
    listener.stageFailed = onStageFailed;
    listener.connectionStarted = onStarted;
    listener.connectionTerminated = onTerminated;
    listener.logMessage = onLog;
    listener.connectionStatusUpdate = onStatus;

    DECODER_RENDERER_CALLBACKS video;
    LiInitializeVideoCallbacks(&video);
    video.setup = onVideoSetup;
    video.submitDecodeUnit = onDecodeUnit;
    video.capabilities = videoCapabilities;

    AUDIO_RENDERER_CALLBACKS audio;
    LiInitializeAudioCallbacks(&audio);
    audio.init = onAudioInit;
    audio.decodeAndPlaySample = onAudioSample;
    audio.capabilities = CAPABILITY_DIRECT_SUBMIT;

    return LiStartConnection(&server, &config, &listener, &video, &audio, NULL, 0, NULL, 0);
}

static void stop(void) { LiStopConnection(); }
static void interrupt(void) { LiInterruptConnection(); }
static const char* launchQuery(void) { return LiGetLaunchUrlQueryParameters(); }
static const char* stageName(int stage) { return LiGetStageName(stage); }
static void requestIdr(void) { LiRequestIdrFrame(); }

static int rtt(unsigned int* rttMs, unsigned int* varianceMs) {
    uint32_t r = 0, v = 0;
    bool ok = LiGetEstimatedRttInfo(&r, &v);
    *rttMs = r;
    *varianceMs = v;
    return ok ? 1 : 0;
}

static int mousePosition(short x, short y, short refW, short refH) { return LiSendMousePositionEvent(x, y, refW, refH); }
static int mouseMove(short dx, short dy) { return LiSendMouseMoveEvent(dx, dy); }
static int mouseButton(int press, int button) {
    return LiSendMouseButtonEvent(press ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE, button);
}
static int scroll(short amount) { return LiSendHighResScrollEvent(amount); }
static int hscroll(short amount) { return LiSendHighResHScrollEvent(amount); }
static int key(short keyCode, int down, int modifiers) {
    return LiSendKeyboardEvent(keyCode, down ? KEY_ACTION_DOWN : KEY_ACTION_UP, (char)modifiers);
}
static int text(const char* utf8, unsigned int length) { return LiSendUtf8TextEvent(utf8, length); }

static const PXR_API api = {
    start, stop, interrupt, launchQuery, stageName, requestIdr, rtt,
    mousePosition, mouseMove, mouseButton, scroll, hscroll, key, text,
};

// Renamed per copy by the generated prefix header (pxr1_pxr_api and so on).
const PXR_API* pxr_api(void) { return &api; }
