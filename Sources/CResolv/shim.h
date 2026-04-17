#ifndef CRESOLV_SHIM_H
#define CRESOLV_SHIM_H

#include <resolv.h>
#include <arpa/nameser.h>
#include <netinet/in.h>
#include <arpa/inet.h>

// --- Resolver state management ---

static inline int c_res_ninit(res_state state) {
    return res_ninit(state);
}

static inline void c_res_ndestroy(res_state state) {
    res_ndestroy(state);
}

// --- Query functions ---

static inline int c_res_nquery(res_state state, const char *dname,
                                int class, int type,
                                unsigned char *answer, int anslen) {
    return res_nquery(state, dname, class, type, answer, anslen);
}

static inline int c_res_nsearch(res_state state, const char *dname,
                                 int class, int type,
                                 unsigned char *answer, int anslen) {
    return res_nsearch(state, dname, class, type, answer, anslen);
}

static inline int c_res_nmkquery(res_state state, int op, const char *dname,
                                  int class, int type,
                                  const unsigned char *data, int datalen,
                                  const unsigned char *newrr,
                                  unsigned char *buf, int buflen) {
    return res_nmkquery(state, op, dname, class, type, data, datalen,
                        newrr, buf, buflen);
}

static inline int c_res_nsend(res_state state,
                               const unsigned char *msg, int msglen,
                               unsigned char *answer, int anslen) {
    return res_nsend(state, msg, msglen, answer, anslen);
}

// --- Server configuration ---

static inline void c_res_setservers(res_state state,
                                     const union res_sockaddr_union *set,
                                     int cnt) {
    res_setservers(state, set, cnt);
}

// --- Message parsing ---

static inline int c_ns_initparse(const unsigned char *msg, int msglen,
                                  ns_msg *handle) {
    return ns_initparse(msg, msglen, handle);
}

static inline int c_ns_parserr(ns_msg *handle, int section,
                                int rrnum, ns_rr *rr) {
    return ns_parserr(handle, (ns_sect)section, rrnum, rr);
}

// --- Name expansion ---

static inline int c_dn_expand(const unsigned char *msg,
                                const unsigned char *eom,
                                const unsigned char *src,
                                char *dst, int dstsiz) {
    return dn_expand(msg, eom, src, dst, dstsiz);
}

// --- Section constants (ns_sect enum is macro-renamed) ---

#define C_NS_S_AN  1  // Answer
#define C_NS_S_NS  2  // Authority
#define C_NS_S_AR  3  // Additional

// --- Constants used from Swift ---

#define C_NS_MAXDNAME   NS_MAXDNAME    // 1025

// Resolver option flags
#define C_RES_USEVC     RES_USEVC
#define C_RES_USE_DNSSEC RES_USE_DNSSEC

// h_errno values
#define C_HOST_NOT_FOUND HOST_NOT_FOUND
#define C_TRY_AGAIN      TRY_AGAIN
#define C_NO_RECOVERY    NO_RECOVERY
#define C_NO_DATA        NO_DATA

#endif /* CRESOLV_SHIM_H */
