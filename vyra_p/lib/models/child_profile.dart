class ChildProfile {
  final String id;
  final String pairingCode;
  final String name;
  final String deviceModel;
  final int batteryLevel;
  final bool isOnline;
  final String locationAddress;
  final String selectedDisguise;
  final bool isScreenOn;

  const ChildProfile({
    required this.id,
    this.pairingCode = 'VYRA-8921',
    required this.name,
    required this.deviceModel,
    required this.batteryLevel,
    required this.isOnline,
    required this.locationAddress,
    required this.selectedDisguise,
    this.isScreenOn = false,
  });

  ChildProfile copyWith({
    String? id,
    String? pairingCode,
    String? name,
    String? deviceModel,
    int? batteryLevel,
    bool? isOnline,
    String? locationAddress,
    String? selectedDisguise,
    bool? isScreenOn,
  }) {
    return ChildProfile(
      id: id ?? this.id,
      pairingCode: pairingCode ?? this.pairingCode,
      name: name ?? this.name,
      deviceModel: deviceModel ?? this.deviceModel,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isOnline: isOnline ?? this.isOnline,
      locationAddress: locationAddress ?? this.locationAddress,
      selectedDisguise: selectedDisguise ?? this.selectedDisguise,
      isScreenOn: isScreenOn ?? this.isScreenOn,
    );
  }
}
