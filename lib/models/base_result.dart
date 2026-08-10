class BaseResult {
  final String title;
  final String link;
  final String domain;
  final String matchType;
  final String sourceConfidence;
  final String image;
  final String thumbnail;

  BaseResult({
    required this.title,
    required this.link,
    required this.domain,
    required this.matchType,
    required this.sourceConfidence,
    required this.image,
    required this.thumbnail,
  });

  String get previewImage => image.isNotEmpty ? image : thumbnail;

  factory BaseResult.fromJson(Map<String, dynamic> json) {
    final link = (json['canonicalLink'] ??
            json['link'] ??
            json['url'] ??
            json['postUrl'] ??
            '')
        .toString();

    final image = (json['verifiedImage'] ??
            json['image'] ??
            json['thumbnail'] ??
            '')
        .toString();

    final thumbnail = (json['thumbnail'] ?? json['image'] ?? '').toString();

    var domain = (json['domain'] ?? '').toString().trim();
    if (domain.isEmpty && link.isNotEmpty) {
      try {
        domain = Uri.parse(link).host.replaceFirst(RegExp(r'^www\.'), '');
      } catch (_) {}
    }

    return BaseResult(
      title: (json['title'] ?? 'Clash of Clans image source').toString(),
      link: link,
      domain: domain.isEmpty ? 'Web source' : domain,
      matchType: (json['matchType'] ?? 'similar').toString(),
      sourceConfidence: (json['sourceConfidence'] ?? '').toString(),
      image: image,
      thumbnail: thumbnail,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'link': link,
      'domain': domain,
      'matchType': matchType,
      'sourceConfidence': sourceConfidence,
      'image': image,
      'thumbnail': thumbnail,
    };
  }
}
