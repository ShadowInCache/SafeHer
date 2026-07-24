// import 'package:cloud_firestore/cloud_firestore.dart'; // Temporarily disabled for web compatibility

class SensorData {
  final String deviceId;
  final String deviceType; // 'glove' or 'glasses'
  final DateTime timestamp;
  final Map<String, dynamic> data;
  final double? threatScore;

  SensorData({
    required this.deviceId,
    required this.deviceType,
    required this.timestamp,
    required this.data,
    this.threatScore,
  });

  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      deviceId: json['deviceId'] as String,
      deviceType: json['deviceType'] as String,
      timestamp: json['timestamp'] is String 
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      data: json['data'] as Map<String, dynamic>,
      threatScore: json['threatScore'] as double?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceType': deviceType,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
      'threatScore': threatScore,
    };
  }
}

class MotionData extends SensorData {
  final double accelerometerX;
  final double accelerometerY;
  final double accelerometerZ;
  final double gyroscopeX;
  final double gyroscopeY;
  final double gyroscopeZ;
  final bool isAnomalous;
  final double? motionVariance; // For stress level calculation

  MotionData({
    required super.deviceId,
    required super.timestamp,
    required this.accelerometerX,
    required this.accelerometerY,
    required this.accelerometerZ,
    required this.gyroscopeX,
    required this.gyroscopeY,
    required this.gyroscopeZ,
    required this.isAnomalous,
    this.motionVariance,
    super.threatScore,
  }) : super(
          deviceType: 'glove',
          data: {
            'accelerometer': {'x': accelerometerX, 'y': accelerometerY, 'z': accelerometerZ},
            'gyroscope': {'x': gyroscopeX, 'y': gyroscopeY, 'z': gyroscopeZ},
            'isAnomalous': isAnomalous,
            'motionVariance': motionVariance,
          },
        );

  factory MotionData.fromJson(Map<String, dynamic> json) {
    final accel = json['data']['accelerometer'] as Map<String, dynamic>;
    final gyro = json['data']['gyroscope'] as Map<String, dynamic>;
    
    return MotionData(
      deviceId: json['deviceId'] as String,
      timestamp: json['timestamp'] is String 
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      accelerometerX: accel['x'] as double,
      accelerometerY: accel['y'] as double,
      accelerometerZ: accel['z'] as double,
      gyroscopeX: gyro['x'] as double,
      gyroscopeY: gyro['y'] as double,
      gyroscopeZ: gyro['z'] as double,
      isAnomalous: json['data']['isAnomalous'] as bool,
      motionVariance: json['data']['motionVariance'] as double?,
      threatScore: json['threatScore'] as double?,
    );
  }
}

/// Physiological data from smart glove sensors (Heart Rate, etc.)
class PhysiologicalData extends SensorData {
  final int heartRate; // BPM
  final double? heartRateVariability; // HRV in ms
  final bool isElevated; // Is heart rate abnormally high?
  final int? stressLevel; // 0-100 stress score

  PhysiologicalData({
    required super.deviceId,
    required super.timestamp,
    required this.heartRate,
    this.heartRateVariability,
    required this.isElevated,
    this.stressLevel,
    super.threatScore,
  }) : super(
          deviceType: 'glove',
          data: {
            'heartRate': heartRate,
            'heartRateVariability': heartRateVariability,
            'isElevated': isElevated,
            'stressLevel': stressLevel,
          },
        );

  factory PhysiologicalData.fromJson(Map<String, dynamic> json) {
    return PhysiologicalData(
      deviceId: json['deviceId'] as String,
      timestamp: json['timestamp'] is String 
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      heartRate: json['data']['heartRate'] as int,
      heartRateVariability: json['data']['heartRateVariability'] as double?,
      isElevated: json['data']['isElevated'] as bool,
      stressLevel: json['data']['stressLevel'] as int?,
      threatScore: json['threatScore'] as double?,
    );
  }

  /// Calculate stress level from heart rate and HRV
  static int calculateStressLevel(int heartRate, double? hrv, {int? baselineHR}) {
    int stress = 0;
    
    // Heart rate contribution (0-50 points)
    if (baselineHR != null) {
      int hrIncrease = heartRate - baselineHR;
      stress += (hrIncrease * 50 / 40).clamp(0, 50).toInt(); // Max at +40 BPM
    } else {
      // Use general thresholds
      if (heartRate > 100) {
        stress += 30;
      }
      if (heartRate > 120) {
        stress += 20;
      }
    }
    
    // HRV contribution (0-50 points) - Lower HRV = Higher stress
    if (hrv != null) {
      if (hrv < 20) {
        stress += 50;      // Very low HRV = high stress
      } else if (hrv < 40) {
        stress += 30; // Low HRV = medium stress
      } else if (hrv < 60) {
        stress += 10; // Normal HRV = low stress
      }
    }
    
    return stress.clamp(0, 100);
  }
}

class WeaponDetectionData extends SensorData {
  final String imageUrl;
  final List<DetectedWeapon> detectedWeapons;
  final bool weaponDetected;

  WeaponDetectionData({
    required super.deviceId,
    required super.timestamp,
    required this.imageUrl,
    required this.detectedWeapons,
    required this.weaponDetected,
    super.threatScore,
  }) : super(
          deviceType: 'glasses',
          data: {
            'imageUrl': imageUrl,
            'detectedWeapons': detectedWeapons.map((w) => w.toJson()).toList(),
            'weaponDetected': weaponDetected,
          },
        );

  factory WeaponDetectionData.fromJson(Map<String, dynamic> json) {
    final weaponsData = json['data']['detectedWeapons'] as List;
    
    return WeaponDetectionData(
      deviceId: json['deviceId'] as String,
      timestamp: json['timestamp'] is String 
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      imageUrl: json['data']['imageUrl'] as String,
      detectedWeapons: weaponsData
          .map((w) => DetectedWeapon.fromJson(w as Map<String, dynamic>))
          .toList(),
      weaponDetected: json['data']['weaponDetected'] as bool,
      threatScore: json['threatScore'] as double?,
    );
  }
}

class DetectedWeapon {
  final String type; // 'gun' or 'pistol'
  final double confidence;
  final BoundingBox boundingBox;

  DetectedWeapon({
    required this.type,
    required this.confidence,
    required this.boundingBox,
  });

  factory DetectedWeapon.fromJson(Map<String, dynamic> json) {
    return DetectedWeapon(
      type: json['type'] as String,
      confidence: json['confidence'] as double,
      boundingBox: BoundingBox.fromJson(json['boundingBox'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'confidence': confidence,
      'boundingBox': boundingBox.toJson(),
    };
  }
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

  factory BoundingBox.fromJson(Map<String, dynamic> json) {
    return BoundingBox(
      x: json['x'] as double,
      y: json['y'] as double,
      width: json['width'] as double,
      height: json['height'] as double,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
  }
}

class VoiceThreatData extends SensorData {
  final String audioUrl;
  final String emotion; // 'anger', 'fear', 'neutral', 'sadness'
  final double emotionConfidence;
  final bool isThreatening;
  final String? transcription;

  VoiceThreatData({
    required super.deviceId,
    required super.timestamp,
    required this.audioUrl,
    required this.emotion,
    required this.emotionConfidence,
    required this.isThreatening,
    this.transcription,
    super.threatScore,
  }) : super(
          deviceType: 'glasses',
          data: {
            'audioUrl': audioUrl,
            'emotion': emotion,
            'emotionConfidence': emotionConfidence,
            'isThreatening': isThreatening,
            'transcription': transcription,
          },
        );

  factory VoiceThreatData.fromJson(Map<String, dynamic> json) {
    return VoiceThreatData(
      deviceId: json['deviceId'] as String,
      timestamp: json['timestamp'] is String 
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      audioUrl: json['data']['audioUrl'] as String,
      emotion: json['data']['emotion'] as String,
      emotionConfidence: json['data']['emotionConfidence'] as double,
      isThreatening: json['data']['isThreatening'] as bool,
      transcription: json['data']['transcription'] as String?,
      threatScore: json['threatScore'] as double?,
    );
  }
}
