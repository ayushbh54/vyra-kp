class DeviceStatus {
  final String deviceName;
  final String model;
  final int batteryLevel;
  final bool isCharging;
  final bool isOnline;
  final DateTime lastSeen;
  final String locationAddress;
  final double latitude;
  final double longitude;

  const DeviceStatus({
    required this.deviceName,
    required this.model,
    required this.batteryLevel,
    required this.isCharging,
    required this.isOnline,
    required this.lastSeen,
    required this.locationAddress,
    required this.latitude,
    required this.longitude,
  });

  factory DeviceStatus.sample() {
    return DeviceStatus(
      deviceName: "Bhai's Phone",
      model: "Vivo T3 Pro 5G",
      batteryLevel: 84,
      isCharging: false,
      isOnline: true,
      lastSeen: DateTime.now(),
      locationAddress: "Near City Coaching Center, Sector 4",
      latitude: 28.6139,
      longitude: 77.2090,
    );
  }
}
