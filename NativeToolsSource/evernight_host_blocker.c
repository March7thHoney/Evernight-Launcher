#include <errno.h>
#include <netdb.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <time.h>

#define DYLD_INTERPOSE(replacement, replacee) \
    __attribute__((used)) static struct { \
        const void *replacement; \
        const void *replacee; \
    } interpose_##replacee __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)(unsigned long)&replacement, \
        (const void *)(unsigned long)&replacee \
    }

extern int res_9_query(const char *, int, int, unsigned char *, int);

static bool names_match(const char *requested, const char *configured, size_t configured_length) {
    size_t requested_length = strlen(requested);
    while (requested_length > 0 && requested[requested_length - 1] == '.') requested_length--;
    while (configured_length > 0 && configured[configured_length - 1] == '.') configured_length--;
    return requested_length == configured_length
        && strncasecmp(requested, configured, configured_length) == 0;
}

static bool host_is_configured(const char *host) {
    const char *configured = getenv("EVERNIGHT_BLOCK_HOSTS");
    if (!host || !configured || !configured[0]) return false;

    const char *entry = configured;
    while (*entry) {
        const char *separator = strchr(entry, ',');
        size_t length = separator ? (size_t)(separator - entry) : strlen(entry);
        while (length > 0 && (*entry == ' ' || *entry == '\t')) {
            entry++;
            length--;
        }
        while (length > 0 && (entry[length - 1] == ' ' || entry[length - 1] == '\t')) length--;
        if (names_match(host, entry, length)) return true;
        if (!separator) break;
        entry = separator + 1;
    }
    return false;
}

static bool should_block(const char *host) {
    const char *deadline_value = getenv("EVERNIGHT_BLOCK_UNTIL_EPOCH");
    if (!deadline_value || !host_is_configured(host)) return false;

    char *end = NULL;
    double deadline = strtod(deadline_value, &end);
    if (end == deadline_value || deadline <= 0) return false;

    struct timespec now;
    if (clock_gettime(CLOCK_REALTIME, &now) != 0) return false;
    double current = (double)now.tv_sec + (double)now.tv_nsec / 1000000000.0;
    if (current >= deadline) return false;

    fprintf(stderr, "evernight-host-blocker: blocked DNS query for %s\n", host);
    return true;
}

static int blocked_getaddrinfo(
    const char *node,
    const char *service,
    const struct addrinfo *hints,
    struct addrinfo **result
) {
    if (should_block(node)) return EAI_NONAME;
    return getaddrinfo(node, service, hints, result);
}

static struct hostent *blocked_gethostbyname(const char *name) {
    if (should_block(name)) {
        h_errno = HOST_NOT_FOUND;
        return NULL;
    }
    return gethostbyname(name);
}

static int blocked_res_query(const char *name, int dns_class, int type, unsigned char *answer, int answer_length) {
    if (should_block(name)) {
        h_errno = HOST_NOT_FOUND;
        errno = EHOSTUNREACH;
        return -1;
    }
    return res_9_query(name, dns_class, type, answer, answer_length);
}

DYLD_INTERPOSE(blocked_getaddrinfo, getaddrinfo);
DYLD_INTERPOSE(blocked_gethostbyname, gethostbyname);
DYLD_INTERPOSE(blocked_res_query, res_9_query);
