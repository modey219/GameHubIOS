#ifndef COMPAT_LINUX_INPUT_H
#define COMPAT_LINUX_INPUT_H

#include <stdint.h>

struct input_event {
    uint32_t time_sec;
    uint32_t time_usec;
    uint16_t type;
    uint16_t code;
    int32_t value;
};

struct input_id {
    uint16_t bustype;
    uint16_t vendor;
    uint16_t product;
    uint16_t version;
};

#define EV_SYN          0x00
#define EV_KEY          0x01
#define EV_REL          0x02
#define EV_ABS          0x03
#define EV_MSC          0x04

#define ABS_X           0x00
#define ABS_Y           0x01

#define KEY_RESERVED    0
#define KEY_MAX         0x2ff

#define INPUT_PROP_POINTER 0x00

#endif
