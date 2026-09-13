class ChildProfile {
  final String id;
  final String name;
  final String deviceModel;
  final int batteryLevel;
  final bool isOnline;
  final String locationAddress;
  final String selectedDisguise;

  const ChildProfile({
    required this.id,
    required this.name,
    required this.deviceModel,
    required this.batteryLevel,
    required this.isOnline,
    required this.locationAddress,
    required this.selectedDisguise,
  });
}
