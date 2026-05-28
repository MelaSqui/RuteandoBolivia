class TouristDestination {
  final String id;
  final String name;
  final String description;
  final String department;
  final double latitude;
  final double longitude;
  final String? imageUrl;
  final String difficultyLevel;
  final List<String> requiredHighways;

  TouristDestination({
    required this.id,
    required this.name,
    required this.description,
    required this.department,
    required this.latitude,
    required this.longitude,
    this.imageUrl,
    required this.difficultyLevel,
    required this.requiredHighways,
  });

  factory TouristDestination.fromJson(Map<String, dynamic> json) {
    return TouristDestination(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      department: json['department'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      imageUrl: json['image_url'] as String?,
      difficultyLevel: json['difficulty_level'] as String,
      requiredHighways: List<String>.from(json['required_highways'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'department': department,
      'latitude': latitude,
      'longitude': longitude,
      'image_url': imageUrl,
      'difficulty_level': difficultyLevel,
      'required_highways': requiredHighways,
    };
  }
}
