#import "MiumCEFBridgeContentClassification.h"

#import <dispatch/dispatch.h>

NSString* lowercasePathExtensionForURLString(NSString* urlString) {
  if (urlString == nil || urlString.length == 0) {
    return @"";
  }

  NSURL* url = [NSURL URLWithString:urlString];
  NSString* pathExtension = url.pathExtension.lowercaseString;
  if (pathExtension.length > 0) {
    return pathExtension;
  }

  NSString* strippedString = urlString;
  NSRange queryRange = [strippedString rangeOfString:@"?"];
  if (queryRange.location != NSNotFound) {
    strippedString = [strippedString substringToIndex:queryRange.location];
  }
  NSRange fragmentRange = [strippedString rangeOfString:@"#"];
  if (fragmentRange.location != NSNotFound) {
    strippedString = [strippedString substringToIndex:fragmentRange.location];
  }
  return strippedString.pathExtension.lowercaseString ?: @"";
}

NSString* normalizedLowercaseMIMETypeString(NSString* mimeTypeString) {
  if (mimeTypeString == nil || mimeTypeString.length == 0) {
    return @"";
  }

  NSString* normalized = [[mimeTypeString componentsSeparatedByString:@";"] firstObject];
  normalized = [normalized stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  return normalized.lowercaseString ?: @"";
}

NSString* NSStringFromTopLevelNativeContentKind(MiumCEFTopLevelNativeContentKind kind) {
  switch (kind) {
    case MiumCEFTopLevelNativeContentKind::image:
      return @"image";
    case MiumCEFTopLevelNativeContentKind::animatedImage:
      return @"animatedImage";
    case MiumCEFTopLevelNativeContentKind::hlsStream:
      return @"hlsStream";
  }
  return @"";
}

bool classifyTopLevelNativeContentURL(
  NSString* urlString,
  MiumCEFTopLevelNativeContentKind* outKind,
  NSString** outPathExtension,
  NSString** outUniformTypeIdentifier
) {
  if (urlString == nil || urlString.length == 0 || outKind == nullptr) {
    return false;
  }

  NSString* pathExtension = lowercasePathExtensionForURLString(urlString);
  if (outPathExtension != nullptr) {
    *outPathExtension = pathExtension;
  }
  if (outUniformTypeIdentifier != nullptr) {
    *outUniformTypeIdentifier = nil;
  }

  if (pathExtension.length == 0) {
    return false;
  }

  if ([pathExtension isEqualToString:@"m3u8"]) {
    *outKind = MiumCEFTopLevelNativeContentKind::hlsStream;
    if (outUniformTypeIdentifier != nullptr) {
      *outUniformTypeIdentifier = @"public.m3u8-playlist";
    }
    return true;
  }

  if ([pathExtension isEqualToString:@"gif"]) {
    *outKind = MiumCEFTopLevelNativeContentKind::animatedImage;
    if (outUniformTypeIdentifier != nullptr) {
      *outUniformTypeIdentifier = @"com.compuserve.gif";
    }
    return true;
  }

  static NSSet<NSString*>* imageExtensions;
  static NSDictionary<NSString*, NSString*>* imageUniformTypeIdentifiers;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    imageExtensions = [NSSet setWithArray:@[
      @"png",
      @"jpg",
      @"jpeg",
      @"webp",
      @"bmp",
      @"tif",
      @"tiff",
      @"svg",
      @"ico",
      @"heic",
      @"heif",
      @"avif",
    ]];
    imageUniformTypeIdentifiers = @{
      @"png": @"public.png",
      @"jpg": @"public.jpeg",
      @"jpeg": @"public.jpeg",
      @"webp": @"org.webmproject.webp",
      @"bmp": @"com.microsoft.bmp",
      @"tif": @"public.tiff",
      @"tiff": @"public.tiff",
      @"svg": @"public.svg-image",
      @"ico": @"com.microsoft.ico",
      @"heic": @"public.heic",
      @"heif": @"public.heif",
      @"avif": @"public.avif",
    };
  });

  if ([imageExtensions containsObject:pathExtension]) {
    *outKind = MiumCEFTopLevelNativeContentKind::image;
    if (outUniformTypeIdentifier != nullptr) {
      *outUniformTypeIdentifier = imageUniformTypeIdentifiers[pathExtension];
    }
    return true;
  }

  return false;
}

bool classifyTopLevelNativeContentMIMEType(
  NSString* mimeTypeString,
  MiumCEFTopLevelNativeContentKind* outKind,
  NSString** outUniformTypeIdentifier
) {
  if (outKind == nullptr) {
    return false;
  }

  NSString* normalizedMIMEType = normalizedLowercaseMIMETypeString(mimeTypeString);
  if (normalizedMIMEType.length == 0) {
    return false;
  }
  if (outUniformTypeIdentifier != nullptr) {
    *outUniformTypeIdentifier = nil;
  }

  static NSDictionary<NSString*, NSString*>* imageUniformTypeIdentifiers;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    imageUniformTypeIdentifiers = @{
      @"image/avif": @"public.avif",
      @"image/bmp": @"com.microsoft.bmp",
      @"image/gif": @"com.compuserve.gif",
      @"image/heic": @"public.heic",
      @"image/heif": @"public.heif",
      @"image/jpeg": @"public.jpeg",
      @"image/jpg": @"public.jpeg",
      @"image/png": @"public.png",
      @"image/svg+xml": @"public.svg-image",
      @"image/tif": @"public.tiff",
      @"image/tiff": @"public.tiff",
      @"image/vnd.microsoft.icon": @"com.microsoft.ico",
      @"image/webp": @"org.webmproject.webp",
      @"image/x-icon": @"com.microsoft.ico",
    };
  });

  if ([normalizedMIMEType isEqualToString:@"application/vnd.apple.mpegurl"]
      || [normalizedMIMEType isEqualToString:@"application/x-mpegurl"]) {
    *outKind = MiumCEFTopLevelNativeContentKind::hlsStream;
    if (outUniformTypeIdentifier != nullptr) {
      *outUniformTypeIdentifier = @"public.m3u8-playlist";
    }
    return true;
  }

  if ([normalizedMIMEType isEqualToString:@"image/gif"]) {
    *outKind = MiumCEFTopLevelNativeContentKind::animatedImage;
    if (outUniformTypeIdentifier != nullptr) {
      *outUniformTypeIdentifier = imageUniformTypeIdentifiers[normalizedMIMEType];
    }
    return true;
  }

  if (![normalizedMIMEType hasPrefix:@"image/"]) {
    return false;
  }

  *outKind = MiumCEFTopLevelNativeContentKind::image;
  if (outUniformTypeIdentifier != nullptr) {
    *outUniformTypeIdentifier = imageUniformTypeIdentifiers[normalizedMIMEType];
  }
  return true;
}

std::string topLevelNativeContentPayloadString(
  NSString* urlString,
  MiumCEFTopLevelNativeContentKind kind,
  NSString* pathExtension,
  NSString* uniformTypeIdentifier
) {
  NSMutableDictionary<NSString*, id>* payload = [NSMutableDictionary dictionaryWithCapacity:4];
  payload[@"kind"] = NSStringFromTopLevelNativeContentKind(kind);
  payload[@"url"] = urlString == nil ? @"" : urlString;
  if (pathExtension != nil && pathExtension.length > 0) {
    payload[@"pathExtension"] = pathExtension;
  }
  if (uniformTypeIdentifier != nil && uniformTypeIdentifier.length > 0) {
    payload[@"uniformTypeIdentifier"] = uniformTypeIdentifier;
  }

  NSError* error = nil;
  NSData* jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
  if (jsonData == nil || error != nil) {
    return std::string("{\"kind\":\"unknown\",\"url\":\"\"}");
  }
  return std::string(static_cast<const char*>(jsonData.bytes), jsonData.length);
}
