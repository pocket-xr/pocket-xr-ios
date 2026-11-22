// Pocket XR for iOS: what the three copies of the stream core share. GPLv3.
#include "pxr_api.h"

static PXR_GCM_FN gcm;

void pxr_set_gcm(PXR_GCM_FN fn) { gcm = fn; }
PXR_GCM_FN pxr_get_gcm(void) { return gcm; }
