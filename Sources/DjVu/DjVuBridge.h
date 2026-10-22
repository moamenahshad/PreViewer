#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface DPCancellation : NSObject
@property(nonatomic, readonly) BOOL cancelled;
- (void)cancel;
@end
@interface DPDecoder : NSObject
- (nullable instancetype)initWithURL:(NSURL *)url cancellation:(DPCancellation *)cancellation error:(NSError **)error;
@property(nonatomic, readonly) NSInteger pageCount;
@property(nonatomic, strong) DPCancellation *cancellation;
@property(nonatomic, readonly) NSString *version;
- (nullable NSDictionary *)pageInfo:(NSInteger)index error:(NSError **)error;
- (nullable NSDictionary *)render:(NSInteger)index maximumDimension:(NSInteger)limit cancellation:(DPCancellation *)request error:(NSError **)error;
- (nullable NSArray *)text:(NSInteger)index cancellation:(DPCancellation *)request error:(NSError **)error;
- (NSArray *)outline;
- (NSDictionary<NSString *, NSString *> *)metadata;
@end
NS_ASSUME_NONNULL_END
