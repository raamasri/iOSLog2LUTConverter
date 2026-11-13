#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

/// A decoded frame owns its pixel buffer for the lifetime of the frame object.
@interface FFmpegDecodedFrame : NSObject
@property (nonatomic, readonly) CVPixelBufferRef pixelBuffer;
@property (nonatomic, readonly) CMTime presentationTime;
@end

/// Local-file H.264 software decoder. Confine each instance to one serial task.
/// Supports 32BGRA and 64RGBAHalf, with no 8-bit intermediate for the half path.
@interface FFmpegVideoDecoder : NSObject
- (nullable instancetype)initWithURL:(NSURL *)url
                        pixelFormat:(OSType)pixelFormat
                              error:(NSError **)error NS_SWIFT_NAME(init(url:pixelFormat:));
- (BOOL)seekToTime:(CMTime)time error:(NSError **)error NS_SWIFT_NAME(seek(to:));
/// nil means end of stream unless lastError is nonnil.
- (nullable FFmpegDecodedFrame *)readFrame;
@property (nonatomic, readonly, nullable) NSError *lastError;
@end

NS_ASSUME_NONNULL_END
