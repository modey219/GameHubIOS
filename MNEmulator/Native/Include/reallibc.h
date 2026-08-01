/*
 * reallibc.h — shared resolver for the real libc bypass layer (reallibc.c).
 *
 * reallibc_resolve(name) returns the genuine libSystem implementation of the
 * given symbol, resolved from an explicit libSystem image handle so that
 * LiveContainer's dyld interposition cannot redirect it. Never NULL-crashes:
 * returns NULL only when the symbol genuinely cannot be found.
 */
#ifndef REALLIBC_H
#define REALLIBC_H

void *reallibc_resolve(const char *name);

#endif /* REALLIBC_H */
