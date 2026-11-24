#include "Sensor.h"
#include "device_imu.h"
static device_imu_type device;
static XArcanaQuaternion latest;
static void sample(uint64_t timestamp, device_imu_event_type event, const device_imu_ahrs_type *ahrs) {
    if (event != DEVICE_IMU_EVENT_UPDATE) return;
    device_imu_quat_type q = device_imu_get_orientation(ahrs);
    // SDK uses NED: forward, right, down. SceneKit uses right, up, back.
    latest = (XArcanaQuaternion){q.y, -q.z, -q.x, q.w, timestamp};
}
int xarcana_sensor_open(void) {
    latest = (XArcanaQuaternion){0};
    return device_imu_open(&device, sample);
}
int xarcana_sensor_read(XArcanaQuaternion *result) {
    int status = device_imu_read(&device, 250);
    *result = latest;
    return status;
}
void xarcana_sensor_close(void) { device_imu_close(&device); }
