#pragma once

#import <Foundation/Foundation.h>

#include <cstdint>
#include <string>

enum class MiumCEFTopLevelNativeContentKind : uint8_t {
  image = 0,
  animatedImage,
  hlsStream,
};

NSString* lowercasePathExtensionForURLString(NSString* urlString);
NSString* normalizedLowercaseMIMETypeString(NSString* mimeTypeString);
NSString* NSStringFromTopLevelNativeContentKind(MiumCEFTopLevelNativeContentKind kind);
bool classifyTopLevelNativeContentURL(
  NSString* urlString,
  MiumCEFTopLevelNativeContentKind* outKind,
  NSString** outPathExtension,
  NSString** outUniformTypeIdentifier
);
bool classifyTopLevelNativeContentMIMEType(
  NSString* mimeTypeString,
  MiumCEFTopLevelNativeContentKind* outKind,
  NSString** outUniformTypeIdentifier
);
std::string topLevelNativeContentPayloadString(
  NSString* urlString,
  MiumCEFTopLevelNativeContentKind kind,
  NSString* pathExtension,
  NSString* uniformTypeIdentifier
);
