#pragma once
#include <stdint.h>
typedef struct { double x, y, z, w; uint64_t timestamp; } XArcanaQuaternion;
int xarcana_sensor_open(void);
int xarcana_sensor_read(XArcanaQuaternion *result);
void xarcana_sensor_close(void);
