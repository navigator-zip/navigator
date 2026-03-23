#import <XCTest/XCTest.h>

#import "../../Sources/MiumKit/MiumCEFBridgeContentClassification.h"

@interface MiumCEFBridgeContentClassificationTests : XCTestCase
@end

@implementation MiumCEFBridgeContentClassificationTests

- (void)testLowercasePathExtensionHandlesNilPlainAndQueryURLs {
  XCTAssertEqualObjects(lowercasePathExtensionForURLString(nil), @"");
  XCTAssertEqualObjects(lowercasePathExtensionForURLString(@""), @"");
  XCTAssertEqualObjects(lowercasePathExtensionForURLString(@"https://navigator.test/image.PNG"), @"png");
  XCTAssertEqualObjects(
    lowercasePathExtensionForURLString(@"https://navigator.test/image.with.query.jpeg?token=123#fragment"),
    @"jpeg"
  );
  XCTAssertEqualObjects(lowercasePathExtensionForURLString(@"https://navigator.test/no-extension"), @"");
}

- (void)testNormalizedLowercaseMIMETypeStringTrimsAndLowercases {
  XCTAssertEqualObjects(normalizedLowercaseMIMETypeString(nil), @"");
  XCTAssertEqualObjects(normalizedLowercaseMIMETypeString(@""), @"");
  XCTAssertEqualObjects(
    normalizedLowercaseMIMETypeString(@" Image/SVG+XML ; charset=UTF-8 "),
    @"image/svg+xml"
  );
}

- (void)testClassifyTopLevelNativeContentURLHandlesKnownAndUnknownExtensions {
  MiumCEFTopLevelNativeContentKind kind = MiumCEFTopLevelNativeContentKind::image;
  NSString* pathExtension = nil;
  NSString* uniformTypeIdentifier = nil;

  XCTAssertFalse(classifyTopLevelNativeContentURL(nil, &kind, &pathExtension, &uniformTypeIdentifier));
  XCTAssertFalse(classifyTopLevelNativeContentURL(@"", &kind, &pathExtension, &uniformTypeIdentifier));
  XCTAssertFalse(classifyTopLevelNativeContentURL(@"https://navigator.test/file", nullptr, &pathExtension, &uniformTypeIdentifier));

  XCTAssertTrue(
    classifyTopLevelNativeContentURL(
      @"https://navigator.test/stream.m3u8",
      &kind,
      &pathExtension,
      &uniformTypeIdentifier
    )
  );
  XCTAssertEqual(kind, MiumCEFTopLevelNativeContentKind::hlsStream);
  XCTAssertEqualObjects(pathExtension, @"m3u8");
  XCTAssertEqualObjects(uniformTypeIdentifier, @"public.m3u8-playlist");

  XCTAssertTrue(
    classifyTopLevelNativeContentURL(
      @"https://navigator.test/animated.GIF",
      &kind,
      &pathExtension,
      &uniformTypeIdentifier
    )
  );
  XCTAssertEqual(kind, MiumCEFTopLevelNativeContentKind::animatedImage);
  XCTAssertEqualObjects(pathExtension, @"gif");
  XCTAssertEqualObjects(uniformTypeIdentifier, @"com.compuserve.gif");

  XCTAssertTrue(
    classifyTopLevelNativeContentURL(
      @"https://navigator.test/vector.SVG",
      &kind,
      &pathExtension,
      &uniformTypeIdentifier
    )
  );
  XCTAssertEqual(kind, MiumCEFTopLevelNativeContentKind::image);
  XCTAssertEqualObjects(pathExtension, @"svg");
  XCTAssertEqualObjects(uniformTypeIdentifier, @"public.svg-image");

  uniformTypeIdentifier = @"sentinel";
  XCTAssertFalse(
    classifyTopLevelNativeContentURL(
      @"https://navigator.test/file.unknown",
      &kind,
      &pathExtension,
      &uniformTypeIdentifier
    )
  );
  XCTAssertEqualObjects(pathExtension, @"unknown");
  XCTAssertNil(uniformTypeIdentifier);
}

- (void)testClassifyTopLevelNativeContentMIMETypeHandlesKnownAndUnknownTypes {
  MiumCEFTopLevelNativeContentKind kind = MiumCEFTopLevelNativeContentKind::image;
  NSString* uniformTypeIdentifier = nil;

  XCTAssertFalse(classifyTopLevelNativeContentMIMEType(nil, &kind, &uniformTypeIdentifier));
  XCTAssertFalse(classifyTopLevelNativeContentMIMEType(@"", &kind, &uniformTypeIdentifier));
  XCTAssertFalse(classifyTopLevelNativeContentMIMEType(@"image/png", nullptr, &uniformTypeIdentifier));

  XCTAssertTrue(
    classifyTopLevelNativeContentMIMEType(
      @"application/vnd.apple.mpegurl; charset=utf-8",
      &kind,
      &uniformTypeIdentifier
    )
  );
  XCTAssertEqual(kind, MiumCEFTopLevelNativeContentKind::hlsStream);
  XCTAssertEqualObjects(uniformTypeIdentifier, @"public.m3u8-playlist");

  XCTAssertTrue(classifyTopLevelNativeContentMIMEType(@"image/gif", &kind, &uniformTypeIdentifier));
  XCTAssertEqual(kind, MiumCEFTopLevelNativeContentKind::animatedImage);
  XCTAssertEqualObjects(uniformTypeIdentifier, @"com.compuserve.gif");

  XCTAssertTrue(classifyTopLevelNativeContentMIMEType(@"image/webp", &kind, &uniformTypeIdentifier));
  XCTAssertEqual(kind, MiumCEFTopLevelNativeContentKind::image);
  XCTAssertEqualObjects(uniformTypeIdentifier, @"org.webmproject.webp");

  uniformTypeIdentifier = @"sentinel";
  XCTAssertFalse(classifyTopLevelNativeContentMIMEType(@"text/html", &kind, &uniformTypeIdentifier));
  XCTAssertNil(uniformTypeIdentifier);
}

- (void)testPayloadSerializationIncludesExpectedFields {
  const std::string payload = topLevelNativeContentPayloadString(
    @"https://navigator.test/image.png",
    MiumCEFTopLevelNativeContentKind::image,
    @"png",
    @"public.png"
  );
  NSData* data = [NSData dataWithBytes:payload.data() length:payload.size()];
  NSDictionary* dictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];

  XCTAssertEqualObjects(NSStringFromTopLevelNativeContentKind(MiumCEFTopLevelNativeContentKind::image), @"image");
  XCTAssertEqualObjects(NSStringFromTopLevelNativeContentKind(MiumCEFTopLevelNativeContentKind::animatedImage), @"animatedImage");
  XCTAssertEqualObjects(NSStringFromTopLevelNativeContentKind(MiumCEFTopLevelNativeContentKind::hlsStream), @"hlsStream");
  XCTAssertEqualObjects(dictionary[@"kind"], @"image");
  XCTAssertEqualObjects(dictionary[@"url"], @"https://navigator.test/image.png");
  XCTAssertEqualObjects(dictionary[@"pathExtension"], @"png");
  XCTAssertEqualObjects(dictionary[@"uniformTypeIdentifier"], @"public.png");

  const std::string minimalPayload = topLevelNativeContentPayloadString(
    nil,
    MiumCEFTopLevelNativeContentKind::animatedImage,
    nil,
    nil
  );
  NSData* minimalData = [NSData dataWithBytes:minimalPayload.data() length:minimalPayload.size()];
  NSDictionary* minimalDictionary = [NSJSONSerialization JSONObjectWithData:minimalData options:0 error:nil];
  XCTAssertEqualObjects(minimalDictionary[@"kind"], @"animatedImage");
  XCTAssertEqualObjects(minimalDictionary[@"url"], @"");
  XCTAssertNil(minimalDictionary[@"pathExtension"]);
  XCTAssertNil(minimalDictionary[@"uniformTypeIdentifier"]);
}

@end
