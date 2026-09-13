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

  ChildProfile copyWith({
    String? id,
    String? name,
    String? deviceModel,
    int? batteryLevel,
    bool? isOnline,
    String? locationAddress,
    String? selectedDisguise,
  }) {
    return ChildProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      deviceModel: deviceModel ?? this.deviceModel,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isOnline: isOnline ?? this.isOnline,
      locationAddress: locationAddress ?? this.locationAddress,
      selectedDisguise: selectedDisguise ?? this.selectedDisguise,
    );
  }
}
