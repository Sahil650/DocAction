class PhotoSizeModel {
  final String name;
  final double width;
  final double height;
  final String unit; // 'mm' or 'in'

  const PhotoSizeModel({
    required this.name,
    required this.width,
    required this.height,
    required this.unit,
  });

  String get sizeString => "$width x $height $unit";
  
  double get aspectForPreview => width / height;
}
