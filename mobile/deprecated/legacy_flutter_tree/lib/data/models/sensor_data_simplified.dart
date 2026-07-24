// Simplified sensor data models that match BLE/MQTT service expectations
// This is a temporary simplified version to get the app compiling

class Accelerometer {
  final double x;
  final double y;
  final double z;

  Accelerometer({required this.x, required this.y, required this.z});

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'z': z};
}

class Gyroscope {
  final double x;
  final double y;
  final double z;

  Gyroscope({required this.x, required this.y, required this.z});

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'z': z};
}

class Detection {
  final String weaponType;
  final double confidence;
  final BoundingBox boundingBox;

  Detection({
    required this.weaponType,
    required this.confidence,
    required this.boundingBox,
  });

  Map<String, dynamic> toJson() => {
    'weaponType': weaponType,
    'confidence': confidence,
    'boundingBox': boundingBox.toJson(),
  };
}

class BoundingBox {
  final double x;
  final double y;
  final double width;
  final double height;

  BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
}

class MotionData {
  final String deviceId;
  final DateTime timestamp;
  final Accelerometer accelerometer;
  final Gyroscope gyroscope;
  final double? motionVariance; // For stress level calculation
  final double? threatScore; // Threat score from ML model

  MotionData({
    required this.deviceId,
    required this.timestamp,
    required this.accelerometer,
    required this.gyroscope,
    this.motionVariance,
    this.threatScore,
  });

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'timestamp': timestamp.toIso8601String(),
    'accelerometer': accelerometer.toJson(),
    'gyroscope': gyroscope.toJson(),
    if (motionVariance != null) 'motionVariance': motionVariance,
    if (threatScore != null) 'threatScore': threatScore,
  };
}

class WeaponDetectionData {
  final String deviceId;
  final DateTime timestamp;
  final String imageUrl;
  final double threatScore;
  final bool weaponDetected;
  final List<Detection>? detections;

  WeaponDetectionData({
    required this.deviceId,
    required this.timestamp,
    required this.imageUrl,
    required this.threatScore,
    required this.weaponDetected,
    this.detections,
  });

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'timestamp': timestamp.toIso8601String(),
    'imageUrl': imageUrl,
    'threatScore': threatScore,
    'weaponDetected': weaponDetected,
    if (detections != null) 'detections': detections!.map((d) => d.toJson()).toList(),
  };
}

class VoiceThreatData {
  final String deviceId;
  final DateTime timestamp;
  final String audioUrl;
  final String emotion;
  final double emotionConfidence;
  final bool isThreatening;
  final String? transcription;
  final double? threatScore;

  VoiceThreatData({
    required this.deviceId,
    required this.timestamp,
    required this.audioUrl,
    required this.emotion,
    required this.emotionConfidence,
    required this.isThreatening,
    this.transcription,
    this.threatScore,
  });

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'timestamp': timestamp.toIso8601String(),
    'audioUrl': audioUrl,
    'emotion': emotion,
    'emotionConfidence': emotionConfidence,
    'isThreatening': isThreatening,
    if (transcription != null) 'transcription': transcription,
    if (threatScore != null) 'threatScore': threatScore,
  };
}
