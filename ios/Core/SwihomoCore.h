#ifndef CLASH_VERGE_MIHOMO_CORE_H
#define CLASH_VERGE_MIHOMO_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int SwihomoCoreStart(uint8_t *profile, size_t profileLength, const char *homeDirectory);
int SwihomoCoreInputPacket(uint8_t *packet, size_t length, int family);
void SwihomoCoreStop(void);
char *SwihomoCoreLastError(void);
void SwihomoCoreFreeString(char *value);
void SwihomoCoreFreeData(uint8_t *value);

/* HTTP status codes are >= 100; smaller values are bridge errors. */
int SwihomoCoreAPIRequest(const char *method, const char *target, uint8_t *body,
                         size_t bodyLength, uint8_t **response, size_t *responseLength);
int SwihomoCoreAPIStreamOpen(const char *method, const char *target, uint8_t *body,
                            size_t bodyLength);
int SwihomoCoreAPIStreamRead(int id, int timeoutMs, uint8_t **data, size_t *dataLength);
void SwihomoCoreAPIStreamClose(int id);

void SwihomoCoreFreeMemory(uint64_t *before, uint64_t *after);
char *SwihomoCoreExternalResources(void);
char *SwihomoCoreProxyGroupOrder(void);
int SwihomoCoreReadExternalResource(const char *identifier, uint8_t **contents, size_t *length);
int SwihomoCoreWriteExternalResource(const char *identifier, uint8_t *contents, size_t length);

#ifdef __cplusplus
}
#endif

#endif
